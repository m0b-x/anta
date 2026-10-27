# Cloud Sync Phase 02 — the review (2026-10-26)

**Status: PLANNED 2026-10-26 (Fable 5.1). Thirteen sessions A0–A9 over two
nights, each one `claude -p` run started by `tool\review\overnight.ps1`;
nothing has run yet. §7 carries the defaults this plan assumes; the owner
changes a letter by editing §7 before the night.** The eleven `sync:`
commits of 2026-10-24/25 (`b9d1ab9` … `ac56abf`, base `25a5c94`; record
`docs/cloud-sync-phase-02-own-space.md`) built the engine, the wire, the
Firestore gateway and the open-editor rule in one session: 149 files,
about 21,700 lines, every slice reviewed once by one Opus reviewer on a
snapshot. Each of those reviews found a data-loss path the slice's own
tests had not produced, and each looked at one slice. This review looks
at the whole: the pre-existing app first ("did we break anything"), then
the engine, the wire, the gateway, then the scenarios that cross every
module — and builds the fixes in three passes, gated, before a final
device pass of the three saved suites.

## Contents

0. How to run this — the runner, the kickoff, what every session does
1. What the per-slice reviews could not see
2. The sessions A0–A9
3. The ledger — session log and findings
4. Must not change
5. Budget
6. Off the schedule, and deferred
7. Decisions (D1–D7)

---

## 0. How to run this

### 0.1 The runner

```
tool\review\overnight.ps1 -Sessions A0,A1a,A1b,A1c,A2,A3a,A3b,A4,A5     # night 1: the reviews
tool\review\overnight.ps1 -Sessions A6,A7,A8,A9 -Commit                  # night 2: the fixes, the gate
tool\review\overnight.ps1 -Sessions A2 -DryRun                            # print the command, run nothing
```

Each session is one `claude -p` run from `frontend/anta` on the model §2
names (Opus 5.5 at `high` for reviews and fixes, Sonnet 5.5 at `medium`
for A0 and A9), `--permission-mode auto`, its output copied to
`build\review-logs\<date>\<session>.log`. Sessions run one after another
because `flutter test` runs one at a time and the fix sessions edit the
tree. The chain stops at the first session whose last line says
`BLOCKED`; the morning starts by reading §3's session log.

The kickoff the runner sends (also the line to paste into an interactive
session):

> Run session `<ID>` of `docs/cloud-sync-phase-02-review-2026-10-26.md`.
> Read its section 0 and the section 2 block for `<ID>` only, plus the
> sections that block names; then do what it says. The owner is asleep:
> never ask a question, take the lettered default and write it into the
> record. [`-Commit`: You may commit on main after the gate: one commit, a
> short natural subject, no ledger in the message. | otherwise: Do not
> commit; end with a ready-to-run commit (paths and subject).] Finish with
> the line `SESSION <ID>: DONE`, `PARTIAL` or `BLOCKED` and one sentence.

### 0.2 Before the night

- `git status --short` clean outside `docs/` — the runner refuses to start
  otherwise (on 2026-10-26 the tree held another session's fasting-schedule
  work in 23 files; it is committed or stashed first); no `flutter run`,
  no `qa run`, no other Claude session editing the tree.
- The workspace is trusted for print mode: `claude -p` ignores the repo's
  `permissions.allow` entries until `claude` has been run interactively
  once in `frontend/anta` and the trust dialog accepted (the smoke test
  of 2026-10-26 printed that warning). The execution policy is
  `RemoteSigned` for the user, so `tool\review\overnight.ps1` runs
  directly from the owner's shell.
- The machine stays awake (power plan, or the Awake PowerToy); the fleet
  guest `anta_qa_1` may be down — A0 boots it, A9 reuses it.
- Night 2 starts only after the owner has read §3: strike an id by
  changing its severity to `—` (the fix sessions skip it) and flip any
  letter in §7. `-Commit` is the owner's grant for that night; without it
  every session ends with a ready commit and the tree keeps the changes.
- The Firebase emulator suite is not needed: A4's probe starts its own on
  free ports. The six stray emulator Java processes on 8080 and 8085–8089
  (phase record §8) stay the owner's call and block nothing here.

### 0.3 What every session does

1. Reads this §0 and its §2 block; reads the phase record and the code by
   the sections and `file:line` the block names — never a record whole.
2. `git status --short`: a review session expects nothing outside `docs/`;
   a fix session expects the tree its predecessor left (a committed tree
   under `-Commit`, uncommitted gated changes otherwise). Changes under
   `lib/` or `test/` that no §3 session-log line accounts for mean a
   session died mid-way: stop with `BLOCKED` and say what is there.
3. Reads §3's session log: a predecessor it depends on (§2 names it) that
   ended `BLOCKED` stops this session with `BLOCKED` too.
4. Spawns exactly the agents its block names, one at a time (`delegation`
   skill loaded first); the lead itself reads only to verify a surprising
   finding against the code, and never redoes the agent's work.
5. Writes outcomes into §3: a review session appends findings in the
   ledger shape and one session-log line; a fix session writes `→` on
   every id it touched, one session-log line and, at the end of night 2,
   the status header.
6. After a reviewer: `git status --short` must show nothing of the
   reviewer's — a probe file in the tree is `git restore`d and reported
   (the reviewer-probe trap: probes run only in a `git archive HEAD`
   snapshot under the scratchpad, mapped `subst T:` and addressed by
   absolute path).
7. Ends with the `SESSION` line. Under `-Commit` the commit comes first
   (code and record together; a review session commits the record alone).
8. Runs everything in the foreground. A `claude -p` run ends the moment
   the lead writes its final message, and a background command, a
   `Monitor`, a `ScheduleWakeup` or an agent told to "notify when done"
   dies with it — on 2026-10-27 A0 ended after five minutes with the
   device pass still pending that way. A long command takes the tool's
   `timeout` (up to ten minutes per call) and runs one at a time; an agent
   is briefed to run its commands in the foreground too and to return
   only with the result in hand.

### 0.4 The reviewer brief (the lead fills the brackets)

Goal and why: [the block's question] — the readers are the owner, who
decides, and the fix session, which works from the ledger alone.
Facts: the files [absolute paths], the diff `git diff 25a5c94 HEAD --
<files>` (the sync commits sit between `b9d1ab9` and `ac56abf`; later
commits are docs), the phase record sections [as named], the tests [as
named], the skills [`anta-context`, plus the block's]. Must not change:
phase record §5 and this record §4. Questions: [the block's list, in
order]. Probes: only in a snapshot (`git archive HEAD | tar -x -C
<scratchpad>\snap`, `subst T: <scratchpad>\snap`, absolute paths), never
the tree; `dart analyze lib` and the named suites may run in the tree
read-only; one `flutter test` at a time. Report: every finding, ordered
data loss and persisted compatibility → crash or stuck state → behaviour
against the record or §4 → the gate's rules → tests → quality; each
CONFIRMED (quote the tool result) or PLAUSIBLE, with `file:line`, the
input or state that triggers it, what goes wrong, and the fix the
reviewer would make in one line; existing `///` comments are house style;
report by turn 60 even if a question is left, saying which. Close with
what was verified end to end and what could not be. OS: `win32`,
PowerShell primary, Git Bash for scripts; no `perl -i`, no `sed -i`.

### 0.5 The fix brief

Goal and why: the ledger ids [list, each with its text copied] — these are
reviewed findings; the owner has read them. Facts: the files, the phase
record sections the ids cite, §4 here, the tests beside each file.
Rules: fix every id in the list and nothing else; an H or M gets a named
test that fails before the fix; an id the implementer judges wrong is
left alone and reported `declined: <why>` — never silently; no scope
growth, no new docs, no refactor beyond the id; files are CRLF
(`git diff --stat` must show hunks, not whole-file rewrites; `unix2dos`
after any tool that normalised one). Gate: `dart analyze lib test
test_driver`, `flutter test` whole (10,486 passed on 2026-10-25; the one
Windows-only `host_devices_test` failure is known), `flutter gen-l10n` and
an empty `untranslated.txt` when an ARB changed, the 27 goldens byte-equal
(a sync fix changes no screen). Report per id: `fixed <file:line> / test
<name>` or `declined: <why>`. Then one `reviewer` at `effort: medium` on
`git diff` of the fix against the same ids, the same probe rule; its
findings go to the ledger as new ids assigned to the same session, fixed
in the same session when small, else `→ deferred`.

### 0.6 The ledger shape

```
- **R07** (H, CONFIRMED; A2) `lib/services/sync/sync_puller.dart:118` — <the defect in one sentence>. Input: <state or steps>. Fix: <intent>. Fix session: A7. → A7: fixed `ac12345`, test `pull keeps a row pushed late` | declined: <why> | deferred: <where>.
```

Severity: **H** data loss, a row or a keystroke gone on any device, or
persisted-data compatibility; **M** a crash, a stuck state, behaviour
against the record; **L** everything else. Ids run `R1`, `R2`, … across
all sessions (read the last id before appending). The fix session is
assigned by file: editor, coordinator, autosave, note and folder
repositories and DAOs, counters, vocabularies, DI, lifecycle, the bloc →
A6; engine, puller, pusher, outbox, status, scheduler, bridge, binding
service, wire, merge, bindings, DAO `mergeRemote`, hooks → A7; gateway,
rules, indexes, `main.dart`, the QA seam, `tool/firebase` → A8. A row the
owner strikes gets severity `—`.

---

## 1. What the per-slice reviews could not see

Each slice review read one diff against its brief. Three questions fell
between them:

- **Q1 — the unbound app.** Every install today has no bound space (nothing
  binds one until S4b-2), so for every user the only thing that may have
  changed is nothing. The sync commits edited the editor page (+526
  lines), the save coordinator, the autosave, the note and folder
  repositories and DAOs, the counter service and blocs, the vocabulary
  service, DI, the lifecycle and `main.dart`. A1a–A1c read those edits
  with one question: with no bound space, is the behaviour the same byte
  for byte — timing, writes, state, strings?
- **Q2 — the rows and the keystrokes.** The risk register's four highs
  (phase record §6) were each pinned by one test in one slice. A2, A3 and
  A5 trace them across modules: a push racing a newer document, a pull
  missing a row, the same note open on two devices, a column a binding
  forgot.
- **Q3 — the contract.** The gateway, the rules, the probe and the tooling
  were written against §3.3 and §3.7 at different hours; A4 reads them
  against each other, field by field.

The two unbuilt fix lists — the S4b-1b review's M1–M3, L4–L8, L10–L12
(phase record §4, the S4b-1b review block) and the S5b review's M1–M3,
L4, L6, L10 (the S5b review block) — are inputs to A6 and A8 whatever the
reviews find (D7).

---

## 2. The sessions A0–A9

Every block: **Goal** · **Files** · **Read** · **Questions** · **Agents** ·
**Writes**. A session that cannot do a step reports it `PARTIAL` with the
step named, never a guess.

### A0 — Baseline device pass (Sonnet lead; `qa-runner`)

**Goal.** The three saved suites on the tree as it is, before any fix: the
"did we break anything" evidence, and the baseline A9 compares against.
**Read.** `qa-emulator` skill (the agent loads it). **Agents.** One
`qa-runner`, briefed: `qa fleet status`, boot `anta_qa_1` if down, `qa
fleet install --build` once, then `qa pass calendar -d emulator-5556`, `qa
pass browser -d emulator-5556`, `qa pass alerts -d emulator-5556`, each as
a foreground call with a ten-minute tool timeout — never in the background
and never "notify me when done", §0.3 item 8; the brief says in so many
words that this overrides step 4 of the agent's own procedure, because a
print-mode session cannot be woken — one `--only` rerun per red; the agent
returns only with the three reports read; the browser suite's
selection-mode semantics offset is a known pre-existing item (QA rework
record §6), report it as such. **Writes.** §3 session log: per suite
green/red/flaky counts and the report paths; a red that is not known
becomes a ledger id (severity M, PLAUSIBLE, fix session by file). Leaves
the guest up with the build installed.

### A1a — The editor, with and without a bound space (Opus lead; `reviewer`)

**Goal.** Q1 and Q2 for the page that carries the app: the open-editor
rule (phase record §3.9) must be inert for an unbound database and
lossless for a bound one. **Files.** `lib/pages/optimized_note_editor_page.dart`
(the diff hunks, not the 3,455 lines), `lib/controllers/note_save_coordinator.dart`,
`lib/services/auto_save_service.dart`, `lib/repositories/note_repository.dart`,
`lib/database/daos/note_dao.dart`, `lib/database/daos/content_chunk_dao.dart`,
`lib/models/note_change.dart`, `lib/services/sync/conflict_copy_title.dart`;
tests `test/widgets/optimized_note_editor_page_test.dart`,
`test/controllers/note_save_coordinator_test.dart`,
`test/services/auto_save_service_test.dart`, `test/database/note_merge_test.dart`.
**Read.** Phase record §3.9; the S4a, S4b-1 and S4b-1b review blocks in
§4; `markdown-engine` skill (the autosave section). **Questions.** (1)
Unbound: the autosave's debounce, flush on leave, pause, move and share,
`SaveStatus`, undo history and the title path unchanged — the S4b-1 H1
rule ("a save that returns while the user typed leaves the page dirty
and re-arms") now applies to every user: trace a slow save followed by an
exit flush, and a save that fails, for a lost clean state or a lost
keystroke. (2) `beforeWrite` is a no-op when no remote work is pending —
prove the gate cannot hold a save forever when nothing will release it (a
stuck `_remoteBusy`, a filing that never completes). (3) Bound: the four
branches — clean reload, dirty with a differing body (copy filed,
autosave held, then wins), remote delete on a clean page (pop only when
current), on a dirty one (keep-as-new, the page keeps editing) — and the
keystroke-during-held-save rule. (4) The S4b-1b list M1–M3, L4–L8,
L10–L12: still open? (expected yes; record each as a ledger id for A6
with the record's fix text, or mark it built). (5) `NoteDao.updateNote`
on a tombstoned row: what the caller sees today. (6) `announceMerged` and
the 50-entry content LRU (M3). **Agents.** One `reviewer`. **Writes.**
Ledger ids; session log.

### A1b — Counters and vocabularies (Opus lead; `reviewer`)

**Goal.** Q1 for the counters (taps kept as deltas across a pull) and the
vocabularies. **Files.** `lib/services/counter_service.dart`,
`lib/database/daos/counter_dao.dart`, `lib/bloc/counter/counter_bloc.dart`,
`lib/bloc/counter_per_note/counter_per_note_bloc.dart` (+ `_event`,
`_state`), `lib/pages/counter_per_note_page.dart`,
`lib/database/daos/vocabulary_dao.dart`, `lib/services/vocabulary_service.dart`,
`lib/pages/vocabularies_page.dart`; tests `test/services/counter_service_test.dart`,
`test/bloc/counter_bloc_test.dart`, `test/bloc/counter_per_note_bloc_test.dart`,
`test/pages/counter_per_note_page_test.dart`, `test/database/counter_merge_test.dart`,
`test/services/vocabulary_service_test.dart`, `test/pages/vocabularies_page_test.dart`.
**Read.** Phase record §3.5 (the hooks: counters flushed before and
reloaded after their page), the S3c and S4a review blocks; "Counter and
category semantics after v43" in
`.claude/skills/anta-context/references/sync-and-accounts.md`.
**Questions.** (1) Unbound: a tap's latency and its write (one per tap?
coalesced?), taps on background and exit, the pinned counters,
`noteId == ''`, the per-note page's state after the +15 lines — anything
that changed for a user who never syncs. (2) `CounterService.changes`:
who listens, rebuild counts on the counter pages, a stream never closed.
(3) The delta path: a tap during a flush, a flush that throws (deltas
kept — the S4b-1 fix), a reload of a pulled page that races a tap (the
accepted millisecond window, phase record §8 — confirm it is
milliseconds). (4) Every read path still filters `is_deleted = 0` after
the new `get…IncludingDeleted` methods; `upsertValue` semantics
unchanged. (5) Vocabularies: the page's listener (+24 lines), `saveItems`
tombstoning, a merge-created duplicate term (phase record §8, accepted —
is the UI stable with two items of one term?). The `importData`
`noteIdMap` defect is deferred by the readiness record and is not a
finding. **Agents.** One `reviewer`. **Writes.** Ledger ids; session log.

### A1c — The app around the engine: folders, DI, lifecycle, main, the bloc (Opus lead; `reviewer`)

**Goal.** Q1 for the wiring: an unbound database on an Android build with
Firebase constructs and starts the engine — prove it does nothing. The
hunks are small; read each file whole where it is under 200 lines.
**Files.** `lib/core/di/injection.dart`, `lib/main.dart`,
`lib/database/database_lifecycle.dart`, `lib/database/database.dart`,
`lib/services/firebase_auth_service.dart`, `lib/services/sync/sync_lifecycle_bridge.dart`,
`lib/services/sync/sync_binding_service.dart`, `lib/services/sync/sync_status_service.dart`,
`lib/bloc/sync/sync_bloc.dart` (+ `_event`, `_state`),
`lib/repositories/folder_repository.dart`, `lib/database/daos/folder_dao.dart`,
`lib/services/folder_storage_service.dart`, `lib/models/folder_change.dart`,
`lib/constants/app_constants.dart`; tests `test/services/sync/sync_lifecycle_bridge_test.dart`,
`sync_binding_service_test.dart`, `sync_status_service_test.dart`,
`sync_engine_switch_test.dart`, `test/bloc/sync_bloc_test.dart`,
`test/database/folder_merge_test.dart`, `test/database/database_instance_test.dart`.
**Read.** Phase record §3.6 (bind, unbind, mismatch), the S3a and S3c
review blocks, §3.5's trigger list; the readiness invariants ("the clock
seeded before the instance is handed out", "an idle launch is
write-free") in `sync-and-accounts.md`. **Questions.** (1) Unbound and
signed out, then unbound and signed in: no gateway call at all
(`watchSpace`, `readSpace`, `listSpaces`), no `sync_metadata` or outbox
write at launch, no timer left armed (the 30 s drain, the hourly retry,
the back-off), no auth-stream side effect; the status stream's first
value. (2) `SyncEngine.getInstance()` on reset and on
`registerSwitchedHandler`: a switch mid-run, a reset mid-run
(`generation`), the engine of the old database stopped and unreachable,
no listener leaked. (3) `main.dart`: the Firebase init path with and
without `google-services.json`, the dead `demo-anta` branch (S5b M1 — a
ledger id for A8 if still there). (4) `SyncBindingService.bind`: one
transaction, a failure leaves nothing bound; the floor only when absent;
refused while bound or suspended. (5) `SyncBloc`: the signed-out and
mismatch states, `RefreshSyncStatus`'s 3 s timeout, the Sharing page
untouched (S4b-2 pending). (6) Folders: `announceMerged`, `moved`,
`nearestLiveFolderId`, the browser's refresh on `moved`; an unbound
database never emits `remote`. **Agents.** One `reviewer`, "report by
turn 60". **Writes.** Ledger ids; session log.

### A2 — The engine core (Opus lead; `reviewer`)

**Goal.** Q2 inside the engine: one run must never drop, duplicate or
re-order a row, and must stop cleanly under every pause. **Files.**
`lib/services/sync/sync_engine.dart`, `sync_puller.dart`, `sync_pusher.dart`,
`sync_status.dart`, `sync_scheduler.dart`, `sync_suspension.dart`,
`lib/database/daos/sync_outbox_dao.dart`, `lib/database/daos/sync_dao.dart`;
tests `test/services/sync/sync_engine_test.dart`, `sync_engine_failures_test.dart`,
`sync_engine_lifecycle_test.dart`, `test/database/sync_outbox_test.dart`,
`sync_outbox_requeue_test.dart`, `test/support/manual_sync_scheduler.dart`,
`test/services/sync/support/sync_pair.dart`. **Read.** Phase record §3.5
whole (it is the engine's spec), §3.3 (the cursor), §6 (the risk
register), the S3b and S3d review blocks. **Questions.** (1) A run's
shape: pull every table while `bind_merge_pending`, else the stale ones;
one transaction per page; `persistClock` once per page; then the drain —
can a drain ever run before the pull on a bind-merge-pending database?
(2) The cursor: `resumed: true` on a table's first page, the 10 s overlap,
at-least-once delivery — is every merge idempotent for a replayed page
(equal stamps a no-op, the conflict copy filed once)? (3) The drain:
`pending(limit: maxBatch)`, rows loaded tombstones included, `ackThrough`
at the stamp read at load time — a row edited between load and ack stays
queued; an entry whose row is gone is retired; the 8 MiB cap bisects a
batch that never fits (a single oversized row parks, not loops). (4)
Failures: back-off 30 s → 10 min, `quotaExhausted` hourly, the
`permissionDenied` diagnosis through one `readSpace` (gone → `noAccess`;
`schema` above ours → `appOutdated`; else bisect-and-park; > 20 parked →
`noAccess`), `invalidData` bisect-and-park; a non-gateway exception in a
merge parks the envelope while a transaction-aborting SQLite error fails
the page whole — trace both through `DriftRemoteException` (S5 M3). (5)
Concurrency: two triggers at once (signal + Sync now + resume) give one
run; a trigger during a run re-runs once; `SyncSuspension` checked
before push, pull and bind, and a suspension that begins mid-run. (6)
`pauseOver`'s precedence and every pause's exit. (7) Risk-register H1
and H2 traced end to end with `sync_pair.dart` in a snapshot: a push
landing over a newer document is repaired by the receiver's re-queue on
the next drain; a row pushed late with a lower stamp is pulled. (8) The
scheduler: how "30 s after the last outbox write" is observed, and what
happens with the app in the background for an hour. **Agents.** One
`reviewer`, "report by turn 60". **Writes.** Ledger ids; session log.

### A3a — The wire and the merge: core and the browser tables (Opus lead; `reviewer`)

**Goal.** Q2 at the row: every synced column travels, every key reproduces
its document id, every merge path keeps the newer row. **Files.**
`lib/services/sync/sync_table_binding.dart` (with `WireFields`),
`sync_tables.dart`, `lib/database/crdt/crdt_merge.dart`, `merge_outcome.dart`,
`synced_tables.dart`, `lib/services/sync/tables/folders_binding.dart`,
`notes_binding.dart`, `counters_binding.dart`, `counter_values_binding.dart`,
`vocabularies_binding.dart`, `vocabulary_items_binding.dart`; tests
`test/services/sync/sync_codec_test.dart`, `sync_tables_test.dart`,
`test/database/support/merge_contract.dart`, `folder_merge_test.dart`,
`note_merge_test.dart`, `counter_merge_test.dart`, `vocabulary_merge_test.dart`.
**Read.** Phase record §3.1, §3.2, §3.4, the S2a review block; the table
definitions under `lib/database/tables/`. **Questions.** (1) The column
matrix: for each of the six tables list every column of the Drift table
and tick it in `encode` and `decode` — a column that does not travel is
an H (it diverges silently between devices); `createdAtMs`/`updatedAtMs`
in milliseconds from Drift's seconds (the readiness repair trap), `position`
for notes and counters, `ownerId`. (2) `WireFields`: a live envelope with a
missing or mistyped key throws; a tombstone takes defaults; a key that
disagrees with the row key is refused — and the decode of a document
written by a *newer* app (an extra key) is lenient. (3) `mergeRemoteRow`'s
five paths against §3.4, including the bind-floor path; `db.hlc.update` on
every path; `ackThrough` and `requeueRow` never mint a stamp (the guard
test's allow-list). (4) Notes: chunk replacement, the FTS index after a
merged title or body (searchable?), the loser rule's four conditions,
`mergeNoteDocument` on a tombstone (no chunks). (5) Folders: a remote
move that closes a cycle (the local cycle check does not run on merge —
what does the browser do with one?), a tombstoned parent with a live
child. (6) Counters: `noteId == ''`, a value whose counter is tombstoned.
(7) Backup round-trip of a merged database: export then import
preserves `owner_id` and every merged row. **Agents.** One `reviewer`,
"report by turn 60". **Writes.** Ledger ids; session log.

### A3b — The wire and the merge: the eleven calendar tables and the hooks (Opus lead; `reviewer`)

**Goal.** The same matrix for the calendar, plus what a pull does to a
loaded calendar. **Files.** `lib/services/sync/tables/calendar_events_binding.dart`,
`calendar_categories_binding.dart`, `calendar_event_templates_binding.dart`,
`calendar_event_occurrences_binding.dart`, `calendar_event_absences_binding.dart`,
`calendar_event_skips_binding.dart`, `calendar_event_alerts_binding.dart`,
`calendar_category_alerts_binding.dart`, `event_digests_binding.dart`,
`calendar_filter_presets_binding.dart`, `overview_views_binding.dart`;
the `mergeRemote…` and `get…ByIdsIncludingDeleted` hunks of the eleven
DAOs (`git diff 25a5c94 HEAD -- lib/database/daos/calendar_event_dao.dart
calendar_category_dao.dart event_template_dao.dart event_occurrence_dao.dart
event_absence_dao.dart event_skip_dao.dart event_alert_dao.dart
category_alert_dao.dart event_digest_dao.dart filter_preset_dao.dart
overview_view_dao.dart`); `lib/services/sync/app_sync_apply_hooks.dart`
(`afterRun`, `_appReloadCalendar`, `_appReloadAlerts`, `_appReconcileAlerts`);
tests `test/database/calendar_*_merge_test.dart`, `event_digests_merge_test.dart`,
`overview_views_merge_test.dart`, `calendar_filter_presets_merge_test.dart`,
`test/services/sync/app_sync_apply_hooks_test.dart`. **Read.** Phase
record §3.4, the S2b review block; `calendar-events` skill (Hardest
constraints; Presence, skips, occurrences; Category alerts and digests);
`.claude/skills/calendar-events/references/context-log.md`, the
2026-10-25 entry "Calendar and cloud sync Phase 02". **Questions.** (1)
The column matrix for all eleven tables against `lib/database/tables/` —
the event row alone has the recurrence shape, until, count and style,
retroactive, priority, `allDay`, `start_minute`/`duration_minutes`,
description scope, presence fields: every one ticked in both directions.
(2) Day keys `eventId|dayEpochMs` reproduce `dayRowKey` byte for byte
(seconds × 1000) for occurrences, absences, skips — and a day at a DST
boundary. (3) A child row whose parent event is absent or tombstoned on
this device (arrives first, or the parent was deleted here): what the
merge stores, what the grid shows. (4) Categories: a built-in id arriving
as a tombstone (refused locally — and on merge?), `is_hidden`, a custom
category's colour and icon. (5) Alerts: `calendar_event_alerts` and
`calendar_category_alerts` travel, `alert_registrations` stay local and
`reconcileAll(sync)` rebuilds them once per run — a ring on both devices
is intended (readiness D11); a digest row that travels: does the second
device re-deliver a digest the first already showed? State the intended
semantics and whether the code matches. (6) The hooks' reload order and
`notifyExternalChange` → `ExternalCalendarChange`: the bloc's caches and
revisions survive an in-place reload with the mode, filters and
drill-down kept (QA rework record §4, slice 6a); a sub-sheet open during
the reload. (7) "Delete all events" on one device against an edit on the
other: per-row LWW resurrects the edited event — intended? (8)
`tombstoneAll` and the merge never cascade. **Agents.** One `reviewer`,
"report by turn 60; the matrix first". **Writes.** Ledger ids; session
log.

### A4 — The Firestore gateway, the rules, the seam and the tooling (Opus lead; `reviewer`)

**Goal.** Q3: the gateway, the rules, the probe and the tooling agree
with §3.3, §3.7 and §3.8, and with Firestore as it is. **Files.**
`lib/services/sync/firestore_sync_gateway.dart`, `sync_gateway.dart`,
`firestore.rules`, `firestore.indexes.json`, `firebase.emulators.json`,
`lib/core/qa/qa_mode.dart`, `lib/main.dart` (the init hunk),
`tool/firebase/emulators.cmd`, `emulators.sh`, `rules_probe.ps1`,
`test/firestore/rules_test.dart`; tests `test/services/sync/firestore_sync_gateway_test.dart`,
`fake_sync_gateway_test.dart`, `test/support/fake_sync_gateway.dart`.
**Read.** Phase record §3.3, §3.7, §3.8, the S1, S5 and S5b review blocks;
`sync-and-accounts.md` (Phase 01's rules notes). **Questions.** (1) The
rules against the contract field by field: every key the gateway writes
is allowed and every key the rules require is written; `pushedAt ==
request.time`, `schema >= stored`, no deletes, owner-only; the space
document's `touched`/`lastWriter`/`lastWriteAt` merge; `pairs`/`invites`
untouched (`git diff 25a5c94 HEAD -- firestore.rules` shows additions
only). (2) `runTransaction(maxAttempts: 1)` write-only: the per-commit
limit — settle S5b L9 (does a `serverTimestamp()` transform still count
as a second write? read the current Firestore limits page; 499 rows plus
the space document) and say whether `maxBatch` 499 is safe. (3)
`pullPage`: `orderBy(pushedAt).orderBy(documentId)`, `startAfter` with
the plain string id, the 10 s overlap on `resumed`, the page size;
whether the query needs a composite index (and the indexes file has it).
(4) `watchSpace`: server snapshots only, the first snapshot offline, the
stream's error and end, re-subscription after `noAccess` lifts. (5) The
error map: `unavailable`/`deadline-exceeded` → offline,
`resource-exhausted` → quota, `permission-denied`/`unauthenticated` →
permissionDenied, `invalid-argument` → invalidData, `failed-precondition`
(a missing index) logged only — is a missing index then an endless silent
retry? (6) The 60 s timeout and a commit that lands after it (S5b L5, a
recorded risk): is `ackThrough` ever called for a batch the device thinks
failed? (7) `createSpace` duplicates (S5 M4) and the one server `get`
before giving up (S5b L4). (8) The QA seam: `ANTA_QA_CLOUD`,
`ANTA_QA_FIREBASE_EMULATOR`, `ANTA_QA_ACCOUNT`, the unsigned token,
persistence off app-wide; the `demo-anta` defaults in the three tools and
the test (S5b M2). (9) Run the probe unattended: `powershell
-ExecutionPolicy Bypass -File tool\firebase\rules_probe.ps1` (own ports,
own emulator) — the exit code is the number of failing cases; and
`flutter test test/firestore`. (10) The S5b carry-overs M1–M3, L4, L6,
L10: each a ledger id for A8 with the record's fix text, unless already
built. **Agents.** One `reviewer`, "report by turn 60". **Writes.** Ledger
ids; session log.

### A5 — The scenarios that cross every module (Opus lead; `reviewer` — `fable-max` only under D3 B)

**Goal.** The interactions no slice owned. The reviewer traces each
scenario through the modules it crosses and drives the ones
`test/services/sync/support/sync_pair.dart` can drive, in a snapshot.
**Files.** As the scenarios need; start from `sync_engine.dart`,
`app_sync_apply_hooks.dart`, `optimized_note_editor_page.dart` (hunks),
`counter_service.dart`, `sync_binding_service.dart`, `database_lifecycle.dart`,
`lib/services/backup_service.dart` (the `SyncSuspension.run` block),
`sync_pair.dart`. **Read.** Phase record §3.5, §3.6, §3.9, §6; "Wipes and
restores" in `sync-and-accounts.md`; A1–A4's ledger ids (to not repeat
them). **Scenarios.** (1) The same note open and dirty on A and B, both
sync: both texts survive on both, and each device ends with the same set
of notes (one copy, not one per device per round). (2) A database switch
mid-pull: no row of the old database lands in the new one; the old
engine is dead. (3) A backup restore mid-drain: the suspension holds, the
unbind runs, a push prepared before the restore never lands after it; the
floor. (4) Sign-out mid-run, sign-in as another account: nothing pushed
under the wrong uid, `accountMismatch` holds, `owner_id` untouched. (5)
Backgrounded mid-transaction: the page commits or rolls back whole; the
leave drains only. (6) Quota pause → hourly retry → resume: no row pushed
twice with a new stamp, `ackThrough` right. (7) Schema skew: the newer
app raises `schema`; the older device pauses `appOutdated` and keeps its
outbox. (8) Clock: a device an hour ahead, a far-future remote stamp
(`clampedRemotes`), the persisted clock after a pull. (9) A delete on A
while B edits the same note; and "Delete all events" on A against an
edit on B. (10) Taps on both devices during a pull: counters are LWW
(readiness) — no crash, the documented loss only. (11) The conflict copy
filed inside the page transaction when the page rolls back: no listener
told of a row that does not exist. **Agents.** One `reviewer` (D3 A) with
the eleven scenarios and "report by turn 60; a scenario you could not
drive is reported as such". **Writes.** Ledger ids; session log; the
night-1 summary line at the top of §3.2 (counts per severity, the H list).

### A6 — Fix pass I: the editor, the counters, the app around the engine (Opus lead; `implementer`, `reviewer`)

**Inputs.** Every ledger id with fix session A6 whose severity is not `—`
(A1a, A1b, A1c and A5's ids by file), plus the S4b-1b list (D7 A) as A1a
recorded it. **Brief** per §0.5; the implementer reads phase record §3.9
and the S4b-1b review block for the fix text; `markdown-engine` and
`anta-context` skills. **Order.** The H ids first, then M, then L; if the
list exceeds about twelve ids, two implementer runs by file group (editor
first), the second after the first's gate. **Then** the medium-effort
`reviewer` on the diff; the gate; the commit under `-Commit`. **Writes.**
`→` on every id; session log with the hash or the ready commit.

### A7 — Fix pass II: the engine, the wire, the merge, the hooks (Opus lead; `implementer`, `reviewer`)

**Inputs.** The A7 ids (A2, A3a, A3b and A5's by file). **Brief** per §0.5;
the implementer reads §3.4 and §3.5 for the ids' sections;
`drift-migrations` skill if a DAO changes (no migration without the owner
— a finding that needs one is `→ deferred: needs v44, owner`);
`calendar-events` for a calendar binding. **Order.** As A6; the
column-matrix H ids first (a column that did not travel needs no
migration — the wire gains the key, and a document already pushed
without it is re-pushed by `requeueRow` on the next merge or by the fix's
one-time requeue; the implementer decides and says which). **Then** the
reviewer, the gate, the commit. **Writes.** As A6.

### A8 — Fix pass III: the gateway, the rules, the seam, the tooling (Opus lead; `implementer`, `reviewer`)

**Inputs.** The A8 ids (A4's and A1c's `main.dart` id), plus the S5b
list M1–M3, L4, L6, L10 (D7 A) as A4 recorded it. **Brief** per §0.5; the
implementer reads §3.3, §3.7, §3.8; the rules change only by addition and
are **not deployed** (owner's yes, phase record §7); the probe
(`rules_probe.ps1`) and `flutter test test/firestore` must pass after any
rules edit; `tool/firebase/*` gain a project argument defaulting to
`alexs-note-tracking-app` (S5b M2) — `*.cmd` stays CRLF, `*.sh` LF.
**Then** the reviewer, the gate, the commit. **Writes.** As A6.

### A9 — The gate, the device pass, the docs (Sonnet lead; `qa-runner`, `docs-writer`)

**Goal.** Prove the tree after the fixes: the whole suite, the three
device suites against A0's baseline, the records in line. **Steps.** (1)
`dart analyze lib test test_driver`; `flutter test` whole; `flutter
gen-l10n` + `untranslated.txt` empty if an ARB changed; goldens byte-equal
(`git status` shows no PNG). (2) One `qa-runner`: `qa fleet install
--build`, then the three suites as A0, one `--only` rerun per red; the
verdict per flow against A0's counts — a flow green in A0 and red now is
a ledger id (H if data, else M) `→ deferred: owner` and the session ends
`PARTIAL`. (3) The lead writes, and `docs-writer` places: this record's
status header (REVIEWED + FIXED, the hashes, counts per severity, the
deferred ids); one paragraph "Review 2026-10-26" at the end of the phase
record's §4 pointing here, with the carry-overs' new state; the
`sync-and-accounts.md` Phase 02 bullet where a behaviour changed; the
calendar `context-log.md` 2026-10-25 entry if a calendar binding changed.
(4) Under `-Commit`: one docs commit. **Writes.** Session log; the
status header; the final line.

---

## 3. The ledger

### 3.1 Session log

One line per session, appended by the session itself:
`- <ID> — <date time> — DONE|PARTIAL|BLOCKED — <model> — <agents run> — <ids added or touched> — <hash or "ready commit: …"> — <one sentence>`.

- A0 — 2026-10-27 08:06 — PARTIAL (no SESSION line) — sonnet — qa-runner ×3 — — — no commit — the lead ended its turn waiting for a background pass and the print-mode run exited after five minutes; §0.3 item 8 added, step 4 of `.claude/agents/qa-runner.md` given the print-mode exception (uncommitted, outside `docs/` on purpose), A0 rerun alone after A5 (its own line follows the A5 line). The times on this log are the runner's; the sessions' own clock guesses were corrected by hand.
- A1a — 2026-10-27 08:11 — DONE — opus/high — one reviewer — R1–R20 added (4 H, 2 M, 14 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A1a editor review goes into the ledger" — the unbound editor is inert bar the sanctioned H1 re-check, the gate cannot leak, all eleven S4b-1b items are still open, and the H1 re-check itself brought a new data-loss path (R1, probe-confirmed); A0's device pass was running on the emulator, so `flutter test` ran only the four named files (370 tests green) and nothing was checked on a device.
- A1b — 2026-10-27 08:33 — DONE — opus/high — one reviewer — R21–R35 added (0 H, 5 M, 10 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A1b counter and vocabulary review goes into the ledger" — the counters and the vocabularies are inert for an unbound database bar one sanctioned string (the S3c F13 localization), the delta path keeps a tap across a merged page under a probe so the phase record's §8 "a tap can be lost" is stale (R34), and the two probe-confirmed mediums are a failed flush that arms no retry (R21) and `CounterService.changes` being per-instance where the vocabulary twin is static (R22); `dart analyze lib` clean and the seven named suites green (85 tests), the whole suite not run.
- A1c — 2026-10-27 08:54 — DONE — opus/high — one reviewer — R36–R43 added (0 H, 2 M, 6 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A1c wiring review goes into the ledger" — an unbound database is inert end to end under a probe on the real engine (no gateway call, no write, no timer, no status emit, signed in or out; the status stream's first value is `SyncStatus.empty` dropped by the dedupe, and on a real install `pendingCount` alone), the bind rollback and the switch rebuild hold, and the two mediums are `SyncBindingService`/`SyncStatusService.getInstance()` missing the engine's `generation` guard so a switch can leave a singleton bound to the closed database (R36) and the still-present `demo-anta` branch (R37, S5b M1, A8); `dart analyze lib` clean and the seven named suites green (+100), the whole suite not run, nothing on a device.
- A2 — 2026-10-27 09:16 — DONE — opus/high — one reviewer — R44–R61 added (1 H, 2 M, 15 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A2 engine review goes into the ledger" — the engine's own shape holds (a drain can never precede the pull under the floor, a replayed page is idempotent, the ack is at the load-time stamp so an edit mid-push stays queued, the bisection terminates and a single oversized row parks, N triggers give one run, no pause can stick within one space, and S5 M3 is real and fixed with the rare background-isolate test to prove it), risk-register H1 and H2 are CONFIRMED by running the two `sync_pair` tests by name, and the one H is at the gateway/puller seam where `page.envelopes.isEmpty` breaks the pull without storing `page.next`, pinning that table's cursor for good (R44) while the gateway's own comment says the opposite; the two mediums are the engine's pause, quota hold, back-off and parked sets surviving `stop()`/`start()` and a rebind with `appOutdated` having no in-session exit at all (R45) and the pusher parking a whole table group on one `loadByKeys` fault (R46); no decision of §7 came into question, the defaults stand; `dart analyze lib` clean and the five named suites green (151 tests), the whole suite not run, no snapshot needed and nothing on a device.
- A3a — 2026-10-27 09:39 — DONE — opus/high — one reviewer — R62–R75 added (2 H, 2 M, 10 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A3a wire and merge review goes into the ledger" — the column matrix is complete for all six browser tables with nothing unclassified and the wire itself is sound (Drift's default unix-second storage makes the `fieldMs` round trip exact, so the readiness repair trap does not bite; `WireFields`' four strictness properties hold and are pinned for every table; the five merge paths match §3.4 including the bind floor, `db.hlc.update` fires on all five, and `ackThrough`/`requeueRow` mint no stamp), the notes answers all come out clean (atomic chunk replacement, a merged note really is searchable because the FTS row is removed while the content table still holds it, the loser rule's four conditions are correct, a tombstone soft-deletes its chunks), and `noteId == ''` survives the round trip exactly; the two highs are both outside the codec — the backup restore drops `created_at`, `updated_at` and the two folder sort orders because `importFromJson` calls `createFolder`/`createNote` where `importFolder`/`importNote` exist for exactly that (R62, lead-verified, pre-existing) and a remote move can close a `parent_id` cycle that takes its folders and all their notes out of the browser for good with nothing to repair it and a backup making it permanent (R63); the two mediums are a live child folder under a remotely-tombstoned parent being reachable from nowhere (R64) and the clock advance sitting outside the puller's page transaction so a rolled-back page lets a local edit out-stamp a remote row this device never merged (R65); R72 is the one lead-verified test hole that matters — the outbox fence's regexes do not match `syncOutboxDao`, so `crdt_merge`, `sync_puller` and `sync_pusher` all mutate the queue outside the rights map and a future `syncOutboxDao.clear()` anywhere would pass the gate; no decision of §7 came into question, the defaults stand, and the two lead defaults are lettered (a) and (b) in the findings block — R62 and R71 to A6, and R62's `position` claim dropped because both `importX` methods re-append position on purpose; `dart analyze lib` clean and the six named suites green (189 tests) plus the guard suite (+4), the whole suite not run, no snapshot needed, nothing written in the tree and nothing on a device.
- A3b — 2026-10-27 10:01 — DONE — opus/high — one reviewer (resumed once at its 80-turn cap) — R76–R86 added (1 H, 2 M, 8 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A3b calendar wire and merge review goes into the ledger" — the column matrix is complete for all eleven calendar tables with nothing unclassified, and each binding's map is pinned equal to its service's real `exportData` by `expect(envelope.data, await exported())`, so the event row's whole shape travels both ways (recurrence, until, count, style, retroactive, priority, `allDay`, `startMinute`/`durationMinutes`, description scope and the four presence fields) and the alert bindings keep the raw-column rule A3a's R66 found broken for `scope` and `label`; the day keys reproduce `dayRowKey` byte for byte in Dart and in the `requeueRow` SQL and DST does not bite (the three `_dateOnlyUtc` helpers normalise through the epoch, and the codec test pins the spring-forward day), an orphan child row is stored verbatim and shown by no surface because every facade is keyed by a listed event, the loaded calendar survives an in-place reload with the mode, filters, drill-down and the slice-6a flags kept, no sub-sheet has an unguarded event lookup to crash on, and nothing cascades on merge; the one high is the built-in category seed, which runs above `bind_floor` when `CategoryService`'s first touch lands after the bind and before the space's category rows, inserts the defaults, is requeued by the `keptLocal` path and overwrites the other device's renamed, recoloured or archived built-ins for good (R76, lead-verified on the floor rule and the enqueue); the two mediums are a delete meeting a concurrent edit resurrecting one event without its presence, descriptions, skips or alerts (R77, intended per-row LWW but written down nowhere) and an alerts-only pull reloading the caches without ever dispatching `ExternalCalendarChange`, so the phone rings for a badge the open screen does not show and nothing in `lib/` reads `EventAlerts.revision` either (R78, lead-verified); every id is assigned to A7 by §0.6's file rule, R83 may land as `→ deferred` under D4 A, and the two lead defaults are lettered (a) and (b) in the findings block — R77 takes the record sentence rather than a merge-side cascade, which §3.4 (4) and phase record §5 forbid, and the digest semantics (each device delivers its own copy, readiness D11 A; `DigestPlanner._fires` cannot replay today's) are recorded rather than coded; no decision of §7 came into question, the defaults stand; `dart analyze lib` clean and the eleven merge suites green (162 tests) plus `sync_codec_test` and `app_sync_apply_hooks_test` (+90), the whole suite not run, no snapshot needed, nothing written in the tree and nothing on a device.
- A4 — 2026-10-27 10:23 — DONE — opus/high — one reviewer — R87–R97 added (0 H, 5 M, 6 L) — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A4 gateway and rules review goes into the ledger" — the contract holds field for field (the eight keys the gateway writes are exactly the ones `validEnvelope()` allows, `ownerId` is asserted before the write, every stamp is `request.time`, the space merge masks only `lastWriter`/`schema`, the 17 rules table names equal the 17 bindings with `content_chunks` absent, and the rules diff removes only comments, so `pairs`/`invites` are byte-identical), S5 H1's `watchSpace` fix is complete, and the two open contract questions are now settled: **S5b L9 — `maxBatch` 499 is safe** (the current quotas page carries no per-commit write row at all; the live limit is 500 field transformations *per document*, and the space document takes at most 18), and **`pullPage` needs no composite index** (the `__name__` tiebreaker inherits the last sort's direction, so the automatic `pushedAt` index serves it) — which matters because `failed-precondition` falls to `unknown` → back-off, so a missing index would have been an endless silent retry; the five mediums are `createSpace` losing its drawn id on a failure whose commit landed, so a retry makes a second orphaned space (R87, S5b L4 never built, the code comment says it is intended), `_regainsAccess` lifting `noAccess` without testing the space's schema so an outdated device re-burns a pull and a denied push on every resume (R88, S5b L6 never built), the three emulator tools and the rules suite still running as `demo-anta` while the Android app's id is `alexs-note-tracking-app`, so S6's pass would judge rules in a second project namespace (R89, S5b M2; §3.8 also names a `-Project` parameter the probe does not have), and the two test holes that leave the one surface with no local safety net uncovered — nothing pins the rules' table list to `syncTables` (R90) and `test/firestore` is the Phase 01 pairs suite, skipped by default, with zero Phase 02 cases (R91, `All tests skipped` verified); the probe ran unattended to **exit code 0** (20 cases PASS, one INFO: a row alone under a missing space is allowed because the rules never check the parent, which the gateway's same-batch space write is what the denial actually rests on), `dart analyze lib` clean and `flutter test test/services/sync test/core/qa` green (283), the whole suite not run; R88 goes to A7 by the file rule and the other ten to A8; five lead defaults are lettered (a)–(e) in the findings block; no decision of §7 came into question, the defaults stand; nothing written in the tree and nothing on a device.
- A5 — 2026-10-27 10:47 — DONE — opus/high — one reviewer (D3 A) — R98–R106 added (1 H, 3 M, 5 L); R77 upgraded to CONFIRMED in place — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A5 cross-module scenarios go into the ledger" — all eleven scenarios were traced and nine of them driven by sixteen probe cases in a `git archive HEAD` snapshot (all green, the snapshot and the `subst T:` mapping removed, `git status --porcelain lib test` empty): the engine's checkpoints hold at every boundary (a suspension, a sign-out, an account change, a `stop()`, a schema skew and a background leave each halt the run with the outbox intact and `owner_id` untouched; a conflict copy round-trips four times without re-forking; a page merges or rolls back whole across a leave and the leave's drain mints no stamp; two simultaneous taps during a pull are both kept, so the record §8's accepted counter loss is stale a third time; the rolled-back page's copy reaches no listener), and the damage is at the seams no slice owned — the one H is a far-future remote stamp that is clamped for the clock but stored **verbatim** on the row, so every later local edit of that row mints below it and is silently reverted on every device for good (R98, probe-confirmed, lead-verified against `crdt_merge.dart:58` and `hlc.dart:174-182`; it names no single fix because every option touches merge semantics or the HLC encoding, both on §4 — default (e) leaves the choice to the owner), and the three mediums are a dirty open editor filing **two** conflict copies where §3.9 promises one (R99), and the two halves of a mid-session database switch leaving the rebuilt engine's hooks on repository singletons that are never re-registered, which wedges the notes pull on a conflict (R100) and silently stops every merge from reaching a surface (R101, both lead-verified — `resetDependencies()` has no caller in `lib/`); R77 is now CONFIRMED by probe A5-9c and R45, R34, R88, R3, R5 and R7 were deliberately not re-filed; five lead defaults are lettered (a)–(e) in the findings block and the night-1 summary line is written at the top of §3.2 (R1–R106: 9 H, 23 M, 74 L); no decision of §7 came into question, the defaults stand; `dart analyze lib` clean in the real tree, the named suites green, the whole suite deliberately not run, nothing written in the tree and nothing on a device.
- A0 — 2026-10-27 11:30 — DONE — sonnet — qa-runner ×1 — — — ready commit: `docs/cloud-sync-phase-02-review-2026-10-26.md` "docs: the A0 baseline device pass goes into the ledger" — the rerun ran all three suites in the foreground with a 600 s timeout, one after another, per §0.3 item 8: calendar 26/26 green (371.0 s), browser 3/3 green (55.5 s), alerts 5/5 green (312.2 s), no reds and no reruns needed, the known pre-existing browser selection-mode semantics offset (QA rework record §6) did not surface; build `38faf86`, guest `anta_qa_1` left up with that build installed for A9 to compare against.
- A6 — 2026-10-27 — DONE — opus/high — three implementers (by file group) + one medium reviewer + one implementer on the review's findings — R1–R3, R5, R7–R16, R18–R26, R28–R31, R33–R35, R40, R42, R43, R62, R71, R99–R101, R106 touched; R107–R128 added (1 H, 5 M, 16 L) — one commit on `main` under D2 A, `sync: fix the editor, counter and restore findings of the phase 02 review` (code and record together; the subject rather than the hash because this line is inside the commit it names) — the H and M ids of A1a, A1b, A1c, A3a and A5 are built and gated, and the review of the fixes was worth its cost: four of the 33 fixes took something away, one of them an H — R26's abort predicate, lifted from `sync_puller.dart:352` as "every `SqliteException` but 19", made a clean `SQLITE_BUSY` rollback **discard** the counter tap the pre-fix code had restored, worse than the hole R21 was closing (R107; the lesson is that a predicate is only safe together with the response it drives, and the puller rethrows where the flush throws the delta away) — the other three being R40 left half closed (R112), R100/R101's rebind unsequenced behind the engine's own switched handler and its failure swallowed (R113, fixed by making the notice carry the `AppDatabase`) and R2's tombstone refusal travelling the generic failure path, spending the retry ladder R10 had just protected (R115); four implementer deviations stand on the record — R1 captures the baseline at the dispatch (`writeIssued()`) rather than before `await onSave`, because the bare read also fired on an adoption made while the write was held at the gate and cost an extra write, push and outbox row after every filed copy; R62 widened `importFolder`/`importNote` with `ownerId`, which routing the restore through them unchanged would otherwise have dropped on every row; R23's guard is keyed on the caller's term snapshot because no vocabulary row carries a stamp; and R100/R101 re-point the two repository instances instead of replacing them in `get_it`, because six services, every mounted page and the hooks hold them — **R99 was declined and re-routed to A7** (the editor branch the id offered loses the other device's text; the hook branch is the sound one and needs a new seam), **R17 and R43 are deferred under D4 A** (no H or M fix of this session opens their files) and R114, R116, R118, R121, R125 and R128's puller sentence are deferred to A7 or to the owner; five lead defaults are lettered (a)–(e) at the top of the A6 findings block; no decision of §7 came into question, the defaults stand — `dart analyze lib test test_driver` clean and `flutter test` whole **10,553 passed, 10 skipped, 1 failed** (the documented Windows-only `test/qa/host_devices_test.dart` `MacosDevice locate` case), no ARB and `untranslated.txt` `{}`, no golden, no PNG, no schema change and no migration; nothing on a device — A9 owns the device pass against A0's baseline.
- A7 — 2026-10-27 — DONE — opus/high — three implementers (by file group) + one medium reviewer + one implementer on the review's findings + the lead on R41 — R4, R6, R27, R32, R36, R38, R39, R41, R44–R61, R63–R70, R72–R86, R88, R98, R99, R102–R105, R114, R125, R128 touched; R129–R148 added (1 H, 5 M, 14 L) — one commit on `main` under D2 A, `sync: fix the engine, wire and merge findings of the phase 02 review` (code and record together; the subject rather than the hash because this line is inside the commit it names) — the H and M ids of A2, A3a, A3b, A4 and A5's by-file share are built and gated, and **the fix review earned its cost a second time**: of 55 fixes read, seven took something away and **one was an H** — R99's new `OpenNoteRegistry` asked its question at **merge** time, inside the page transaction, while the editor answered a different one at **announcement** time, so a pending title-only edit (§3.9 M6), a save landing in the window or a page going clean each left the losing body with **no copy at all**, worse than the double copy R99 closed (R129; A6's R107 lesson one layer up — the two sides of a suppression must ask the same question at the same moment, and the fix makes the registry a claim the page latches, not a question the hook asks) — the other six being the folder repair running during the bind's initial merge and pushing a flattening move (R130) and minting below the move it repairs once R65 moved the clock off the merge (R131), R65 leaving `persistClock()` outside the page transaction against `crdt_write.dart`'s own invariant (R132), R79's UTC-midnight requirement able to park a legacy row forever (R133), R46's run-ending throw leaving the entry queued and so failing **every** later run (R134), and R114's helper turning a drift broadcast stream into a single-subscription one (R140); five implementer deviations stand on the record — R65 moved the clock advance out of `mergeRemoteRow` entirely (the reviewer checked every caller: `mergeRemote` has one in `lib/`, and the restore and the bind go through `CrdtWrite`), R66's `label` half is declined because the wire carries the label's *name* and an index this build cannot name has no verbatim form, R67 excludes `counter_dao.dart` because `counters` and `counter_values` have **no** `updated_at` column (a migration, so the owner's), R80 made `reload()` itself seed rather than adding `reloadWithSeed()` because the hooks were another run's file, and R133 normalises the day on the way out in `encode` only, never in `rowKeyOf`, because normalising the local key would make `_prepare`'s lookup miss and silently retire the entry — **R86 was declined** (both branches it names regress: the hook's `events` reload feeds `AlertScheduler.reconcileAll`, and `backup_service.dart:366` fires the same signal without a prior reload), **R98 is deferred to the owner** under A5's default (e), **R39 → S4b-2** and **R83 left under D4 A**, and R130's second half, R148 and the `watchNoteById`/`watchFolderById` twins are deferred; five lead defaults are lettered (a)–(e) at the top of the A7 findings block, including the one that needed data rather than a guess — a copy of the owner's export (never opened in place) holds 96 day rows across the three tables and **every one** is at UTC midnight, so R133's park-forever path is latent and needs no migration; no decision of §7 came into question, the defaults stand — `dart analyze lib test test_driver` clean and `flutter test` whole **10,656 passed, 10 skipped, 1 failed** (the documented Windows-only `test/qa/host_devices_test.dart` `MacosDevice locate` case), no ARB and no `gen-l10n`, no golden, no PNG, no schema change and no migration; nothing on a device — A9 owns the device pass against A0's baseline.

### 3.2 Findings

Shape in §0.6. The night-1 summary line goes first when A5 writes it.

**Night 1 — R1–R106: 9 H, 23 M, 74 L** (A1a 4/2/14, A1b 0/5/10, A1c 0/2/6,
A2 1/2/15, A3a 2/2/10, A3b 1/2/8, A4 0/5/6, A5 1/3/5). Seven reviewers ran;
A0's device pass is now done, all three saved suites green with no reds, so
**nothing in this ledger was seen failing on a device, but no finding below
was itself probed on one**. The nine highs, in id order:
**R1** a body write in flight overwrites the baseline the page adopted for a
merge (A1a, A6); **R2** a write that lands on a tombstone is lost silently and
the page says it saved (A1a, A6); **R3** an exit while the delete filing is
queued takes the deleted note's text (A1a, A6); **R4** `remoteContent` is read
after the merge transaction committed (A1a, A6); **R44** a page whose envelopes
were all skipped breaks the pull without storing `page.next`, pinning that
table's cursor for good (A2, A7); **R62** the backup restore drops `created_at`,
`updated_at` and the two folder sort orders (A3a, A6); **R63** a remote move can
close a `parent_id` cycle and take its folders and all their notes out of the
browser for good (A3a, A7); **R76** the built-in category seed overwrites the
space's renamed, recoloured or archived built-ins (A3b, A7); **R98** a far-future
remote stamp is clamped for the clock but stored verbatim on the row, so every
later local edit of that row is reverted on every device, forever (A5, A7).
Four of the nine are CONFIRMED by a probe or a named test (R1, R2, R3, R62,
R98 — five); the rest are PLAUSIBLE from the code. A5 also upgraded **R77**
from PLAUSIBLE to CONFIRMED (probe A5-9c) and confirmed **R34**'s "the record's
accepted counter loss is stale" a third time.

**A1a (the editor) — 4 H, 2 M, 14 L.** All eleven open items of the
S4b-1b list are still open (none was built), and the H1 re-check the
S4b-1 review asked for brought one new data-loss path of its own (R1).
The lead re-read R1 and R2 against the code before writing them.
**Q1 — unbound: inert, with one sanctioned delta.** `_onStorageChange`
drops everything with `!change.remote` and only `announceMerged` mints
`remote: true`; `_writesMayProceed` returns a plain `true`
*synchronously* while `_remoteBusy == 0 && _unfiled.isEmpty`, so the save
path takes no extra async hop and the debounce, interval, flush, pause,
move, share, `SaveStatus` and failure paths are unchanged; the
`_reloadContentIfChanged` guard is byte-for-byte the two old `if`s and
`noteChanges` is already broadcast. The one delta is the S4b-1 H1
re-check, which now applies to every user — §3.9's own rule and a fix for
a pre-existing window, so not a regression, but it ships two visible side
effects (R14, R15).
**Q2 — the gate cannot leak.** Every `_remoteBusy` increment has a
matching `finally` decrement inside a catch-everything body, and
`_awaitRemoteWork`'s inner `while` re-reads `_remoteWork` each turn, so
the `do … while` terminates. Two indefinite holds are deliberate: a
filing that keeps failing holds every non-leaving write for the page's
life (R10), and a failed keep-as-new filing makes the page refuse to pop
(the recorded M3 decision). The only unbounded loop in the new code is
R16.
**Q3 — the four branches hold** (clean reload with the caret kept; dirty
→ copy filed, autosave held, local text wins; a delete popping only when
the route is current; a dirty delete retargeted before the held write
reads the id) **except** R1, R4, R2/R3 and R5.
`R4` and `R6` share one fix — the merge handing the merged body to
`SyncAppliedRow` — so both are assigned to **A7**, which owns the merge,
rather than split across A6 and A7 (the lead's default; the owner moves
them by editing the `Fix session:` field).

- **R1** (H, CONFIRMED; A1a) `lib/services/auto_save_service.dart:126-131` — a body write already in flight when a merge is filed overwrites the baseline the page adopted for the merge, and the H1 re-check then reads the page **clean over text the row does not hold**. `_performSave` captures `currentContent` before `await onSave(...)` and on success sets `_savedContentHash/_savedContentLength` from it unconditionally, undoing any `adoptSavedContent(merged)` that ran during the await (the M6 comment at `:124` anticipates exactly this for a title-only write, but the `contentChanged` branch does not); `isSavedContent(live)` is then true, so the clean branch runs — `_hasPendingChanges = false`, `SaveStatus.saved`, `onChangeDetected(false)` — which also cancels the `markChanged()` that `NoteSaveCoordinator.adoptStoredContent` (`lib/controllers/note_save_coordinator.dart:221-224`) had just armed, and its debounce fires into `if (!_hasPendingChanges) return;`. Input: bound device, note dirty with "mine", the debounced write of "mine" in flight (held by the gate, or merely slow — the bloc awaits `loadNoteContent` + `updateIndex` after the commit); a pull merges "theirs" with a newer HLC, `_adoptRemoteUpdate` files the copy and calls `adoptStoredContent("theirs")`, then the write resolves. Result: the row holds "theirs", the editor shows "mine", `hasChanges == false`, no further save is ever scheduled, and the next `didPopNext` → `_reloadContentIfChanged` replaces "mine" with "theirs" on screen; the conflict copy it filed duplicates the row instead of preserving the user's text. Reproduced by an `AutoSaveService`-only probe in a `git archive HEAD` snapshot: `AFTER WRITE: isSavedContent(theirs)=false isSavedContent(mine)=true pending=false status=SaveStatus.saved` / `CALLS AFTER DEBOUNCE: [mine]`. The existing unit test "a title-only write leaves a body baseline adopted meanwhile (M6)" (`test/services/auto_save_service_test.dart:526`) covers only `contentChanged == false`. Fix: version the baseline — bump a counter in `adoptSavedContent`, read it before `await onSave`, and on success skip the `contentChanged` baseline write and take the unsaved branch when it moved. Fix session: A6. → A6: fixed `lib/services/auto_save_service.dart:40-48,147,160-181` + `lib/controllers/note_save_coordinator.dart:396-399`, tests `a body write in flight leaves the baseline a merge adopted meanwhile, and its own text stays unsaved (R1)` and `a baseline adopted before the write went out is replaced by what the write landed (R1)`. **Deviation:** the capture point is the dispatch itself (`AutoSaveService.writeIssued()`, `:263-272`, called by the coordinator after the hold and the title lookup), not a generation read before `await onSave` — the bare read also tripped on an adoption made *while the write was held at the gate*, costing an extra identical write, push and outbox row after every filed copy (it broke six existing sync cases). Only an adoption from the dispatch on wins the baseline; an unbound device never bumps the generation. R120 pins the write count.
- **R2** (H, CONFIRMED; A1a) `lib/database/daos/note_dao.dart:298` + `lib/bloc/optimized_note/optimized_note_bloc.dart:291` — S4b-1b **M2**, still open: a write that lands on the tombstone between the delete merge's commit and its change event is lost silently and the page says it saved. `updateNote` returns `null` for a deleted row, `NoteStorageService.updateNote` returns `null` too (`lib/services/note_storage_service.dart:230`), and the bloc calls `event.completer?.complete()` unconditionally — the `metadata != null` check only skips the search index — so the coordinator returns normally, `AutoSaveService` stamps the baseline, clears pending and shows `SaveStatus.saved`; the delete event then finds a clean page and `_onRemoteDelete` (`lib/pages/optimized_note_editor_page.dart:1401`) closes it with the text gone. Input: bound device, note open and dirty, the other device deletes it, the local debounce fires after the merge commit but before `announceMerged` emits. Fix (the record's): make `updateNote` **report** the refused write — the refusal itself stays — so the autosave keeps the text unsaved and the page stays dirty for the delete handler. Fix session: A6. → A6: fixed `lib/bloc/optimized_note/optimized_note_bloc.dart:11-25,305-319` (new `NoteWriteRefusedException`; the completer now errors) + a `///` on `lib/services/note_storage_service.dart:218-222`, test `a write the tombstone refused leaves the text unsaved, so the delete behind it keeps it as a new note (M2)`, verified failing pre-fix. The DAO's and the service's `null` returns are unchanged, as the id asked. Residual: the refusal first travelled the generic failure path and spent the retry ladder — R115, fixed in this session.
- **R3** (H, CONFIRMED; A1a) `lib/pages/optimized_note_editor_page.dart:2878-2879` — S4b-1b **M1**, still open: `_keptDeletedNotesText` tests `_holdsDeletedNotesText` immediately and never waits for `_remoteBusy`, so an exit that happens while the delete handler is queued but has not yet listed its filing lets the page leave and the text is never kept. Reachable because the exit flush does not always ask the gate: `AutoSaveService._performSave:107-112` returns before `onSave` when nothing changed — e.g. right after R2 marked the page clean. Input: bound device, dirty note deleted elsewhere, the user hits back in the same tick the merge commits. Fix (the record's): await the remote chain (`_awaitRemoteWork`-style) before deciding, not just the list's current contents. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:2907-2925` (`_awaitRemoteWork(leaving: true)` in place of the list snapshot), test `leaving while a delete is still being handled waits for its filing instead of taking the text along (M1)`, verified failing pre-fix. Residuals: the wait was unbounded (R109) and could end silent (R111), both fixed in this session.
- **R4** (H, PLAUSIBLE; A1a) `lib/repositories/note_repository.dart:658` — the record's own **Residual** (and L9's wording), still open: `remoteContent` is read *after* the merge transaction committed, so a local save that commits in the window merge-commit → end of `announceMerged`'s reads makes `remoteContent` the user's **own** text; `_adoptRemoteUpdate` (`lib/pages/optimized_note_editor_page.dart:358-361`) then hits `arriving == _contentController.text`, returns, files nothing, and the other device's text is gone on both devices. Input: bound device, note open and dirty, a pull merges a newer body while the local debounce commits inside that window. Fix (the record's): have the merge hand the body it wrote to `SyncAppliedRow` (`mergeNoteDocument` already holds it) and carry that to `announceMerged` instead of re-reading the row. Fix session: A7 (shares the carry with R6). → A7: fixed `lib/repositories/note_repository.dart:675` + `merge_outcome.dart:52`, `note_dao.dart:1031`, `sync_apply_hooks.dart:63`, `sync_puller.dart:305`, `app_sync_apply_hooks.dart:125` — the merge hands the body it wrote back on `MergeOutcome.mergedContent`, the puller carries it onto `SyncAppliedRow.content` and `announceMerged` takes it as a parameter with **no re-read fallback**. Test `the body the merge wrote rides the announcement, not the row as a save in flight left it (R4)`, verified failing pre-fix (`Expected: 'theirs' / Actual: 'mine'`). The fix review enumerated the callers: `announceMerged` has one in `lib/` and it passes `bodies` for every row, and `remoteContent` is null only for a tombstone, which it already forced to null.
- **R5** (M, CONFIRMED; A1a) `lib/pages/optimized_note_editor_page.dart:1219-1224` — S4b-1b **L4**, still open; recorded here as M because it persists a duplicate row and discards typed text. `_retryEachUnfiled` iterates a snapshot (`List.of(_unfiled)`) and never re-checks membership, so a filing that completed during the iteration runs a second time (`filing.attempt` is back to `null` and the filing is already off `_unfiled`). Input: `_unfiled = [copyFiling(failed), keepFiling(first attempt running)]`; the user hits back, `_keptDeletedNotesText` → `_retryUnfiled` awaits `copyFiling` while `keepFiling` succeeds. Result: a **second** conflict-copy note for a copy filing; for a keep-as-new filing a second `retarget`, a second `syncNoteKeptAsNew` snackbar and `_titleController.text` forced back to `kept.title`, discarding any title typed since. Fix: `if (!_unfiled.contains(filing)) continue;` at the top of the loop body. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:1225` (`if (!_unfiled.contains(filing)) continue;`), test `a merge arriving during the retry of a failed filing is filed behind it, and each filing runs once (L4/L10)`. **No pre-fix-failing test:** with R3 in, no path starts the loop while a filing is running, so the double run is no longer reachable from the UI; the guard is kept as the invariant.
- **R6** (M, CONFIRMED; A1a) `lib/repositories/note_repository.dart:658` (+ `:152-173`) — S4b-1b **M3**, still open: `announceMerged` calls `loadContentForNotes` with every live id of the pulled page; that method decompresses each missing body and `put`s every one into `_contentCache`. With `maxContentCacheSize = 50` (`lib/constants/app_constants.dart:61`) and a pull page of `maxBatch => 499` (`lib/services/sync/firestore_sync_gateway.dart:55`), up to **499 bodies are held in one map at once and 499 puts walk a 50-slot LRU**, evicting the user's whole working cache on every sync and leaving only the last 50 pulled bodies. Fix (the record's): carry the body on `SyncAppliedRow` so the read goes, and drop the cache put. Fix session: A7 (shares the carry with R4). → A7: fixed `lib/repositories/note_repository.dart:683` — the `loadContentForNotes` call is gone with R4's carry, so no pulled body is put through the 50-slot LRU. Test `a merged body is not put through the content cache (R6)`, verified failing pre-fix (`Expected: false / Actual: <true>`).
- **R7** (L, CONFIRMED; A1a) `lib/pages/optimized_note_editor_page.dart:1219-1224` — S4b-1b **L5**, still open: `_retryEachUnfiled` continues past a failure (`_run` swallows it), so filings complete out of order and a late-succeeding older filing moves the baseline backwards through `adoptStoredContent`. Fix (the record's): stop at the first failure. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:1227-1230` (stop at the first failure), covered by R5's test and the existing `failed filings wait in order … (L7)` case.
- **R8** (L, CONFIRMED; A1a) `lib/pages/optimized_note_editor_page.dart:2882-2888` vs `:1245-1288` — S4b-1b **L6**, still open: the exit path raises `syncNoteKeptAsNewFailed` itself while `_run` already showed it at the first failure (`_run` suppresses only a second `_run`, not the exit's own snackbar), so the user sees the same error twice. Fix (the record's): let the exit reuse the filing's notice bookkeeping instead of raising its own. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:2917-2922` — the exit re-arms the keep filings' `failed` flag and lets `_run` raise the notice once. Residuals: the ordinary case then stacked two notices (R110), the backstop could go silent (R111) and the wrong filing was picked (R127) — all three fixed in this session.
- **R9** (L, CONFIRMED; A1a) `lib/pages/optimized_note_editor_page.dart:1363` + `:1022` — S4b-1b **L7**, still open: the title-pending reload goes through `_adoptLoadedContent` → `_contentController.loadText(content)`, which its own doc says resets the undo history, so a remote body merge on a title-dirty page costs the user's undo stack; and the branch never applies `change.note.title`, so a concurrent remote rename loses to the pending local title with no notice. Fix (the record's): state the LWW rule, and splice the body instead of reloading it if that is cheap. Fix session: A6. → A6: fixed as **documentation only**, `lib/pages/optimized_note_editor_page.dart:1304-1315`: the title LWW rule is stated. Splicing was declined — a whole-document splice that keeps undo means a second document-replacement path on the typing path, re-deriving stats, `_edits.syncLength`, the caret clamp and the preview push that `_adoptLoadedContent` owns, which the id itself allows. **So both behaviours the id named still stand:** a remote body merge on a title-dirty page still resets the undo stack, and a concurrent remote rename still loses to the pending local title with no notice — lead default (c), R118.
- **R10** (L, CONFIRMED; A1a) `lib/controllers/note_save_coordinator.dart:364` + `lib/services/auto_save_service.dart:157-162` — S4b-1b **L8**, still open: `_WriteHeld` is an ordinary throw, so a deliberate hold shows `SaveStatus.error` in the app bar and burns a rung of the 3-rung retry ladder; after three holds only the 30 s interval retries, and a later genuine failure gets no ladder until a success resets `_retryCount`. Fix (the record's): a typed hold that re-arms the debounce without counting a retry and without the error status. Fix session: A6. → A6: fixed `lib/services/auto_save_service.dart:6-22,188-194` (typed `SaveHeld`: a held write keeps `unsaved`, re-arms the debounce, spends no rung) + `lib/controllers/note_save_coordinator.dart:366` (the private `_WriteHeld` is gone), test `a held write stays unsaved without the error status, re-arms the debounce and spends no rung (L8)`. `test/controllers/note_save_coordinator_test.dart:230` pinned the old `SaveStatus.error` + 2 s rung and was updated — see R121 for what that changes for the user.
- **R11** (L, CONFIRMED; A1a) `test/widgets/optimized_note_editor_page_test.dart:4411,4428` — S4b-1b **L12**, still open: the `readGate` seam gates nothing now that the page files from `remoteContent` instead of re-reading, and `grep -rn "remoteContent" test/` returns no match — there is no repository test for `remoteContent` at all (null for a tombstone, `''` for an empty body, absent on `moved`). Fix (the record's): drop the dead gate, add the three repository cases. Fix session: A6. → A6: fixed — the dead `readGate` seam is gone from `_FlakyStorage` (replaced by `loadGate`/`loads` on `loadNoteWithContent`, which R3's and R13's cases use) and the new `test/repositories/note_repository_announce_merged_test.dart` adds the three `remoteContent` cases (tombstone → null, emptied body → `''`, `moved` → absent).
- **R12** (L, PLAUSIBLE; A1a) `test/widgets/optimized_note_editor_page_test.dart` — S4b-1b **L11**, still open: no widget test types during a held save and asserts the keystroke reaches the row; the H1 rule is pinned only as a unit test (`test/services/auto_save_service_test.dart:494`). Fix: one widget test that types during the hold and asserts the row after the release. Fix session: A6. → A6: fixed — test `a keystroke made while the save waits for a filing reaches the row once the filing lands (H1)`: types during the held save and asserts the row after the release. R120 later made it pin the write count too.
- **R13** (L, PLAUSIBLE; A1a) `test/widgets/optimized_note_editor_page_test.dart:4310,4362` — S4b-1b **L10**, narrower than recorded: the gate-wait is exercised by one update case and one delete case, but neither distinguishes the outer `do … while` from a single pass (the inner `while` carries both); a case where a merge arrives *during* `_retryUnfiled()` is missing. Fix: add that case. Fix session: A6. → A6: fixed — test `a merge arriving during the retry of a failed filing is filed behind it, and each filing runs once (L4/L10)`: the second merge arrives inside `_retryUnfiled()`, so the outer `do … while` is what picks it up.
- **R14** (L, PLAUSIBLE; A1a) `lib/services/auto_save_service.dart:146-151` — the H1 re-check cancels the debounce the keystroke armed and starts a **fresh** `debounceDelay`, so a keystroke made during a slow save can wait up to twice the debounce instead of its own deadline. Unbound users see this too. Fix: re-arm only when no timer is pending, or arm the remainder. Fix session: A6. → A6: fixed `lib/services/auto_save_service.dart:208-219` (`_rearmDebounce` keeps a pending deadline), test `a keystroke made while it waits keeps its own debounce deadline (R14)`, verified failing pre-fix.
- **R15** (L, PLAUSIBLE; A1a) `lib/services/auto_save_service.dart:142-143` — the re-check sets `_hasPendingChanges`/`SaveStatus.unsaved` but never calls `onChangeDetected(true)` (only the clean branch notifies), so `NoteSaveCoordinator.hasChanges` — and with it `_hasUnsavedText`, the app-bar dot and the `_reloadContentIfChanged` guard — can read false while text is pending. Latent today only because every path into `_performSave` has already set it. Fix: `onChangeDetected?.call(true)` in that branch. Fix session: A6. → A6: fixed `lib/services/auto_save_service.dart:181`, test `the text it keeps pending is announced as a change (R15)`, verified failing pre-fix. R115 extended the same call to the generic catch.
- **R16** (L, PLAUSIBLE; A1a) `lib/pages/optimized_note_editor_page.dart:1376-1390` — `_createWithFreeTitle` is an unbounded `for (var copy = 1; ; copy++)` retrying on every `DuplicateNameException`; numbering escapes `NoteStorageService.createNote`'s check in practice, but any other source of that exception spins a DB round trip per turn inside a `_remoteBusy` link and holds every write for the page's life. Fix: cap the attempts and fail the filing, which already holds and retries. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:1386-1420` — `_freeTitleAttempts = 20`, and the last attempt's `DuplicateNameException` becomes the filing's failure, which already holds and retries.
- **R17** (L, PLAUSIBLE; A1a) `lib/database/daos/content_chunk_dao.dart:91-125` vs `lib/pages/optimized_note_editor_page.dart:354-355` — `loadContentForNotes` pre-seeds every id with `''` and removes only the *buffer* for a body whose chunks fail to decompress, so an **unreadable** body arrives as `remoteContent == ''`, not null, and the page's "an unreadable body gives nothing to compare or to keep" guard never fires: on a dirty page it files an **empty** conflict copy and `adoptStoredContent('')` makes the empty text the baseline. Fix: distinguish unreadable from empty in the DAO's map, or treat `''` with `contentLength > 0` as unreadable in the page. Fix session: A6. → A6: **deferred** — `lib/database/daos/content_chunk_dao.dart:91-125`: distinguish unreadable from empty in `loadContentForNotes`' map (or treat `''` with `contentLength > 0` as unreadable in the page). No H or M fix of this session opens that file, so D4 A leaves it; it is the only A1a id not built.
- **R18** (L, PLAUSIBLE; A1a) `lib/pages/optimized_note_editor_page.dart:2922` + `:2878` — `_currentNoteMetadata` uses the plain `flush()`, which the gate can hold while a copy is unfiled, so a move or share acts on the row's **older** stored body with no notice. Intended (M4) but silent. Fix: surface the hold, or refuse the move/share while a filing is unfiled. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:2955-2983` — `_currentNoteMetadata` waits for the remote chain and refuses while a filing is unfiled, raising that filing's own notice; the `noteNotFound` snackbar moved inside so its two callers do not stack a second message. No new string. Residuals R110 and R127, both fixed in this session.
- **R19** (L, PLAUSIBLE; A1a) `lib/pages/optimized_note_editor_page.dart:2930-2947` — `_openFolder` never sets `_isExiting`, so a remote delete arriving while `AppNavigator.popToFolder` runs can still reach `_leaveRemotelyDeleted` and fire a second `Navigator.pop`. Fix: set and clear `_isExiting` around `_openFolder` as the `PopScope` does. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:2987-3012` — `_isExiting` is set and cleared around `_openFolder` exactly as the `PopScope` handler does.
- **R20** (L, CONFIRMED; A1a) `lib/pages/optimized_note_editor_page.dart:1498` + `lib/services/app_navigator.dart:123-125` — the H2 doc comment contrasts `Navigator.of(context).pop()` with `AppNavigator.pop(context)`, but the latter *is* `Navigator.pop(context)`; the `ModalRoute.isCurrent` guard is the whole fix, and the comment misleads a later reader into thinking the call site matters. Fix: one line of comment. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:1504-1513` — one comment: any pop takes the top route, `AppNavigator.pop` *is* `Navigator.pop`, and `_isCurrentRoute` is the whole fix.

**A1b (counters and vocabularies) — 0 H, 5 M, 10 L.** No high: for an
unbound database the counters and the vocabularies are inert, and the
delta path the S3c H1 and S4a L8 fixes built holds under a probe.
**Q1 — unbound: inert, with one sanctioned visible change.** The 300 ms
debounce (`counter_service.dart:57`) and the tap coalescing are
unchanged; the flush's shape changed from N `upsertValue` transactions in
a `Future.wait` to one `_db.transaction` with a `getValue` + `upsertValue`
per key (fewer transactions, one extra read per key, all-or-nothing), and
the number written from the in-memory absolute to `stored + delta` —
identical for an unbound database on every traced path, and it *fixes* a
pre-diff loss (the old flush skipped a note write when
`_noteValuesCache[nid]?[cid]` was null, losing the tap when the cache had
been evicted). Background and exit still flush on `paused` / `inactive` /
`detached`, still unawaited (R33). Pinned counters untouched;
`noteId == ''` survives `_flushDirty`'s fold into `(id, '')`,
`counterValueRowKey`'s `'$counterId|$noteId'` and
`CounterValuesBinding._keyOf`'s split at the first `|`. Zero extra
rebuilds per tap (`changes` fires only from `reload()` and `importData`,
and both loaded states are `Equatable` over every field, so an identical
refresh paints nothing). **The one visible change:** the +15 lines of
`counter_per_note_state.dart` turn `CounterPerNoteError.message` into a
`CounterPerNoteFailure` enum worded through `l10n.counterNotFound` /
`l10n.counterLoadError` — a hard-coded English "Counter not found" and a
raw `e.toString()` become localized copy. That is the S3c **F13** fix, all
three ARBs carry both keys and `untranslated.txt` is `{}`, so the gate
holds — but §4's "the review ships no visible change" is not literally
true of the sync commits themselves, and A9's device pass should look at
that one string.
**Q2 — `changes`: two listeners, no per-tap cost, one stream that
outlives nothing.** `CounterBloc` (app-level at `main.dart:781`, never
closed) and `CounterPerNoteBloc` (per page, closed by its provider); both
cancel before `super.close()`. A tap fires nothing; a pull fires one
event per changed `counters`/`counter_values` page and
`CounterPerNoteBloc._onRefreshed` does a `flush()` plus a full
`_loadEntries` per event with no transformer — bounded by the page count,
paint suppressed by the equal-state guard. The controller is per instance
and never closed → R22.
**Q3 — the delta path is sound and the phase record's §8 window is
stale.** A tap during a flush folds over the written value; a flush that
throws merges the snapshot back idempotently across repeated failures
(probe: one `+1` tap, three failed flushes then a good one → stored 4,
not 6). `afterPage` runs after the page transaction commits
(`sync_puller.dart:105-108`) and drift serialises the flush against the
page, so the window is two selects plus one transaction — milliseconds,
as recorded. **But nothing is lost in it** (probe: merged 8 + a tap in
the window → memory 4 before the reload, 9 after, stored 9), so §8's
accepted item is now a *display* window only → R34. The holes that
remain are R21 and R26; the one real loss in that window is R24.
**Q4 — read paths: every live read still filters.**
`counter_dao.dart` restates `_live` on `getAllCounters`, `getValue`,
`getValuesForNote`, `getAllValues`, `getValuesForCounter` and
`getValuesForCounterOrdered`; the unfiltered selects are write/merge
paths by design (`_upsertValue`'s parent lookup *must* see the tombstone
to drop the write). Each of the four new `…IncludingDeleted` methods has
exactly one caller, all the push's `loadByKeys` (`counters_binding:25`,
`counter_values_binding:27`, `vocabularies_binding:22`,
`vocabulary_items_binding:22`) — nothing in the UI, the service or the
backup reaches them. `upsertValue` semantics unchanged (read-then-write,
no-op on an unchanged live row, dropped under a tombstoned parent,
resurrection clearing `isDeleted`/`deletedAt` and resetting
`position`/`isPinned`/`ownerId` only then). `exportData`'s new `liveIds`
filter is a no-op unbound, and backup format 7's shape and — after a
`flush()` — its content are unchanged.
**Q5 — vocabularies: the page's listener is right, the duplicate is
cosmetic.** The listener is subscribed after the `mounted` guard,
cancelled in `dispose`, and re-resolves `getInstance()` per event rather
than holding the instance — which works only because that controller *is*
`static` (the S4a L12 fix, and the contrast that makes R22 a finding);
the `_reresolve` → `_create` → `_changes.add` path terminates in one
redundant `setState`. Two live items of one term leave the UI stable (the
list is keyed by vocabulary id, `parseTerms` folds them on save, a delete
removes the vocabulary) bar the term being offered twice in the
suggestion bar (R35). The loss channel is the editor, not the list → R23.
**Not a finding, as briefed:** `CounterService.importData` never applying
`noteIdMap`.
The lead re-read R21, R22, R24 and the Q1 string change against the code
before writing them. **Two lead defaults, both one edit to flip:** R21 is
filed **M**, not H, because the tap is only *gone* on a conjunction (a
write fails, no further tap follows, no explicit `flush()` runs, the
process dies) — what is certain is a UI that disagrees with the table for
the page's life; the owner raises it by editing the severity. R27 and R32
sit in `app_sync_apply_hooks.dart` and §3.5, so §0.6's by-file rule sends
them to **A7** rather than to A6 with the rest of this session.

- **R21** (M, CONFIRMED; A1b) `lib/services/counter_service.dart:220-233` — a flush that fails keeps the delta but arms nothing to write it: the S4a L8 catch restores `pending` into `_dirtyGlobalValues`/`_dirtyNoteValues` and never calls `_scheduleDirtyFlush()`, while `flush()` (`:237-240`) has already cancelled the timer. Input: one tap, one transient write failure (a locked or full database, or the engine's `beforePage` flush throwing), then no further tap. Result: the UI shows the tap as taken while the table holds the old number and nothing is scheduled — only the next tap or the next explicit `flush()` (the fire-and-forget lifecycle call at `lib/main.dart:666`) writes it, and a process death first loses the tap. Probe in a `git archive HEAD` snapshot: `P2 stored after 900 ms with no further tap: 3 (memory 4)` / `P2 stored after an explicit flush: 4`. The existing test (`test/services/counter_service_test.dart:289`) hides it by ending with an explicit `flush()`. Fix: `_scheduleDirtyFlush();` as the last line of the catch. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:270` (`_scheduleDirtyFlush()` last in the catch), test `a flush that failed arms the next one itself, with no further tap and no explicit flush (A1b review R21)`, verified failing pre-fix (`Expected: <4> / Actual: <3>`). Residuals: R26's new abort branch then discarded the tap outright (R107, H) and armed nothing (R108) — both fixed in this session.
- **R22** (M, CONFIRMED; A1b) `lib/services/counter_service.dart:64` (+ `:95-98`) — `CounterService._changes` is a **per-instance** broadcast controller and `reset()` drops `_instance` without closing it, where `VocabularyService` fixed exactly this with a `static` one (`lib/services/vocabulary_service.dart:73-76`, "Shared by every instance, so a subscription outlives the singleton a database switch replaces (S4a review L12)"). The blocs take the service from DI (`lib/core/di/injection.dart:92`, `:258`; `lib/pages/counter_per_note_page.dart:29`) while the hooks take `CounterService.getInstance` (`lib/services/sync/app_sync_apply_hooks.dart:66`), so after a `DatabaseLifecycle` switch those are two objects: the engine reloads the new instance, the app-level `CounterBloc` (`lib/main.dart:781`, never closed) stays subscribed to the old controller — merged counters never reach the page, and the subscription pins the old service and its closed `_db` alive. Probe: `P1 counter listener on the old instance fired: 0` versus `P1b vocabulary listener fired after a switch: 1`. Latent today because a database switch demands a restart (`lib/pages/database_settings_page.dart:787-820`); S4b's in-place switch and `AppDatabase.deleteAllData` meet it. Fix: make `_changes` `static final` as in `VocabularyService`, and have both blocs re-resolve `CounterService.getInstance()` per event. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:69` (`_changes` is `static final`, `VocabularyService`'s wording), `:87` (a new singleton fires `changes`), `:96` (`instanceOrNull`), and `lib/bloc/counter/counter_bloc.dart:22,30,57-60` + `lib/bloc/counter_per_note/counter_per_note_bloc.dart:20,31,53-56` re-resolve the singleton per event; new test `test/bloc/counter_bloc_database_switch_test.dart` "after a database switch the bloc shows the new database and follows its service", verified failing pre-fix. `lib/core/di/injection.dart` untouched — the DI site already hands in the singleton. Residual: the static stream is shared with every `forTesting` instance (R124, fixed).
- **R23** (M, PLAUSIBLE; A1b) `lib/pages/vocabulary_editor_page.dart:57-62` → `:88-104` → `lib/database/daos/vocabulary_dao.dart:180-183` — editing a vocabulary tombstones a term a pull merged meanwhile, on every device. `initState` snapshots `initial.terms` and the save hands the whole list to `saveItems`, whose trailing loop tombstones every existing row not in it under one stamp. Input: bound device, a vocabulary open for editing, a pull merges a term the other device added, the user saves. Result: the merged term is tombstoned and the tombstone is pushed — the term is gone everywhere. The vocabularies page beneath re-reads on `changes` (`lib/pages/vocabularies_page.dart:55`); the editor above it does not listen at all. Fix: subscribe the editor to `VocabularyService.changes` and re-read `initial`, or have `saveItems` refuse to tombstone a row whose `hlcTimestamp` is newer than the snapshot it was handed. Fix session: A6. → A6: fixed `lib/database/daos/vocabulary_dao.dart:113-125,192-199` + `lib/services/vocabulary_service.dart:147-166` + `lib/pages/vocabulary_editor_page.dart:100-110`, tests `a term merged after the snapshot survives the save`, `a term the user removed is still tombstoned`, `a merged duplicate of a listed term still collapses`. **Deviation:** the DAO guard is keyed on the caller's **term snapshot**, not an `hlcTimestamp` — `saveItems` is handed only `List<String> terms` and neither `Vocabulary` nor `VocabularyItem` carries a stamp, so "newer than the snapshot" had no reference inside the DAO, and the newest kept row would have refused to delete the most recently added term. `saveItems({..., List<String>? snapshot})` keeps a live row whose term is in neither list and tombstones everything else as before; `null` = replace outright, which every existing caller and test does unchanged. No stamping change, no new stamp minted. Residual: a remote **rename** now leaves a live duplicate pair instead of the local rename winning — R116, recorded not coded.
- **R24** (M, PLAUSIBLE; A1b) `lib/services/counter_service.dart:334-344` — `resetGlobal`'s early return reads stale memory across a merge, so a Reset in the pull window is silently lost. `if ((_globalValues[counterId] ?? counter.startValue) == counter.startValue) return;` is answered from memory, which between a `counter_values` page committing and `afterPage`'s `reload()` still holds the pre-merge number. Input: device A sits at the `startValue`, device B pushes 8, A taps Reset inside that window. Result: the guard short-circuits, nothing is recorded as pending, and the reload puts 8 back — the only loss left in a window the delta path otherwise covers (Q3). Fix: drop the memory guard and always `_recordAbsolute`; the DAO's own no-op check (`counter_dao.dart:188`) already suppresses a redundant write. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:377` (the memory guard dropped), test `a Reset while memory still shows the start value survives the merge (A1b review R24)`, verified failing pre-fix (`Expected: <3> / Actual: <8>`). Residual: the id's premise ("the DAO's own no-op check already suppresses a redundant write") has a hole when there is no value row at all, which for an **unbound** user meant a new `counter_values` row and an outbox entry where there had been nothing — R117/R119, fixed in this session.
- **R25** (M, PLAUSIBLE; A1b) `lib/services/counter_service.dart:532-537` — `importData` is the one wholesale writer still off the `_serial` queue the diff introduced for exactly this: it clears the dirty maps and cancels the timer synchronously, but a `_flushDirty` that already copied `pending` (`:190-197`) and is awaiting its transaction still writes those keys, after `deleteAll()` and the restore's inserts. Input: a tap, the 300 ms timer fires, a backup restore's `importData` lands inside that write's window. Result: a value row the backup did not carry is resurrected, or a restored counter gets the pre-restore count stamped over it with a fresh HLC. Fix: wrap `importData`'s body in `_serialized(...)`. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:576` — the body is `_importData`, `importData` is `await _serialized(() => _importData(data))`; test `an import waits for a flush already in flight (A1b review R25)`, verified failing pre-fix. Re-entrancy checked: the only caller is `backup_service.dart:514`, outside any `_serialized` body.
- **R26** (L, PLAUSIBLE; A1b) `lib/services/counter_service.dart:220-233` — the catch's comment asserts "The transaction rolled back, so nothing in `[pending]` was written", which drift's `CouldNotRollBackException` and a post-commit I/O failure both break: the writes are durable and the restored delta is applied a second time on the next flush, double-counting the tap. §3.5's own S3d rule already singles out `CouldNotRollBackException` as "the savepoint is gone". Fix: on `CouldNotRollBackException` (or any `SqliteException` with `resultCode != 19`) discard the snapshot and `reload()` instead of restoring it. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:247` — on an aborting failure the snapshot is discarded and the table re-read; `reload()`'s body split into `_reloadLocked()` because `reload()` re-enters `_serialized`. Test `a flush whose writes outlived its rollback is not applied twice (A1b review R26)`, verified failing pre-fix with the exact double count. **The predicate was wrong as first built** — copied from `sync_puller.dart:352` as "every `SqliteException` but 19", which made a clean `SQLITE_BUSY` rollback throw the tap away: R107 (H) replaced it with an allow-list, R108 armed the retry.
- **R27** (L, PLAUSIBLE; A1b) `lib/services/sync/app_sync_apply_hooks.dart:76-78` — `beforePage`'s counter flush failure is swallowed by `_guard` and the page merges anyway. No value is lost (R21's restore plus `afterPage`'s reload re-apply the delta), but the local row merges un-pushed and so loses an HLC race it would have won. Fix: none required; name the consequence in §3.5's Counters paragraph. Fix session: A7. → A7: fixed in the record, as the id asks — phase record §3.5's Counters paragraph now names the consequence: a `flush()` that fails is swallowed and the page merges anyway; no value is lost (the restore plus `afterPage`'s reload re-apply the delta) but the local row merges un-pushed and so loses an HLC race it would have won. No code change.
- **R28** (L, PLAUSIBLE; A1b) `lib/services/counter_service.dart:205-206` — `_flushDirty` drops a pending change whose counter left `_counterIndex` (`if (counter == null) continue;`) after `pending` was already cleared at `:196-197`, so the key vanishes from the maps and from `written` with no trace. Defensive today — every path that removes a counter from the index also clears its dirty entries (`:297-298`, `:116-124`, `:535-536`) — but a future path that rebuilds `_counterIndex` without touching the dirty maps loses taps silently. Fix: `debugPrint` the dropped key. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:229` — `debugPrint` of the dropped key. No test: the branch is unreachable from any current path and the fix is the log line itself.
- **R29** (L, PLAUSIBLE; A1b) `lib/bloc/counter/counter_bloc.dart:289-296` + `lib/bloc/counter_per_note/counter_per_note_bloc.dart:294` — both refresh handlers build a fresh loaded state with no `lastError`, and those events are now fired from `CounterService.changes`, so an arriving pull can clear a mutation error before the user reads it. Fix: carry `lastError: current.lastError` through the refresh. Fix session: A6. → A6: fixed `lib/bloc/counter/counter_bloc.dart:316` and `lib/bloc/counter_per_note/counter_per_note_bloc.dart:81,301,327` (`_loadEntries` takes an optional `lastError`, the refresh passes the current state's). **No test, and not reachable:** `lastError` is dead in `lib/` — nothing writes it and no page reads it, so a bloc test cannot set it up. Either a mutation handler is missing its `copyWith(lastError: …)` or the field should go; left for the owner.
- **R30** (L, PLAUSIBLE; A1b) `lib/bloc/counter/counter_bloc.dart:23-25` + `lib/bloc/counter_per_note/counter_per_note_bloc.dart:27-29` — the `changes` listener is wired above the `on<…>` registrations; safe only because a broadcast stream delivers on a later microtask, and `Bloc.add` with no handler registered is a `StateError`. Fix: move the `listen` below the last `on<…>`. Fix session: A6. → A6: fixed `lib/bloc/counter/counter_bloc.dart:48` and `lib/bloc/counter_per_note/counter_per_note_bloc.dart:48` — the `listen` moved below the last `on<…>`. No test: the pre-fix order was safe by microtask timing, so no input distinguishes them.
- **R31** (L, CONFIRMED; A1b) `test/pages/counter_per_note_page_test.dart`, `test/services/counter_service_test.dart:289` — the test gaps behind this session's ids: no counter twin of `test/pages/vocabularies_page_test.dart`'s "after a database switch the page shows the new database's lists and follows its service" (R22 is untested); the flush-failure case ends with an explicit `flush()` and so masks R21 (a case that waits past the 300 ms debounce with no further tap would catch it); nothing pins `importData` against an in-flight flush (R25); nothing covers two live vocabulary items of one term through the list, the pills, an edit and a delete (the phase record §8 accepted duplicate). Fix: the four cases. Fix session: A6. → A6: fixed, all four cases — the R22 database-switch twin (`test/bloc/counter_bloc_database_switch_test.dart`), the R21 debounce-only flush failure and the R25 import-against-flush case in `test/services/counter_service_test.dart`, and "a term two live rows hold reads as one through the list, the suggestions, an edit and a delete" in `test/pages/vocabularies_page_test.dart` (the pills are covered at the facade they render from).
- **R32** (L, PLAUSIBLE; A1b) `lib/services/sync/app_sync_apply_hooks.dart:153-155` vs phase record §3.5 — §3.5 lists `VocabularyService.reload()` among the hooks that run "after a page that changed rows", but the code reloads once per run on `SyncInvalidation.vocabularies`, so an open vocabularies page waits for the whole 17-table run. Either is defensible; the record and the code should agree. Fix: one clause in §3.5, or move the reload to `afterPage` beside the counters. Fix session: A7. → A7: fixed in the record — phase record §3.5 now says vocabularies are the exception to "after a page", reloading **once per run** on the `vocabularies` invalidation class, so an open vocabularies page waits for the whole 17-table run. Moving the reload to `afterPage` was the other option and was not taken: it costs one reload per page for a surface that is rarely open.
- **R33** (L, PLAUSIBLE; A1b) `lib/services/counter_service.dart:134-138` + `lib/main.dart:662-668` — `_serialized` always goes through `_serial.then(...)`, so `_flushDirty` no longer begins synchronously inside `didChangeAppLifecycleState` and the call there is fire-and-forget: on `paused` the flush now starts one microtask later. Negligible, and it is the only timing change an unbound user has. Fix: none; recorded so §4's Q1 claim stays honest. Fix session: A6. → A6: no fix required, as the id says; recorded so §4's Q1 claim stays honest. The `_serialized` microtask is still the only timing change an unbound user has.
- **R34** (L, CONFIRMED; A1b) phase record §8, the S2a accepted item "a tap between the counters flush and the reload of one pulled page can be lost" — no longer true on either the global or the per-note path, so the record sends a later session chasing a closed hole. The delta path keeps the tap (probe: merged 8 plus a tap inside the window → memory 4 before the reload, 9 after, stored 9; pinned by `test/services/counter_service_test.dart:200-287`); what remains is a **display** window of a few milliseconds, and the one real loss in it is R24. Fix: reword that §8 bullet to the display window and cite R24. Fix session: A6. → A6: fixed — the phase record §8 bullet now reads as the display window it is, cites R24 as the one real loss in it, and names the probe and the test that pin the tap.
- **R35** (L, PLAUSIBLE; A1b) `lib/constants/vocabularies.dart:86-103` — `updateCache` flattens `suggestibleItems` with no folded dedup, so the phase record §8 accepted merge-created duplicate term is offered **twice** in the suggestion bar until the vocabulary is next saved. No crash (the bar builds no keyed children per term) and `saveItems` collapses it on the next edit. Fix (optional): dedupe on `foldedTerm` per vocabulary in `updateCache`. Fix session: A6. → A6: fixed `lib/constants/vocabularies.dart:86-100` — `updateCache` dedupes on `foldedTerm` per vocabulary; test `a term two rows hold is offered once`. Checked: no legitimate term is lost — `VocabularyService.parseTerms:112` already dedupes on `normalizeForSearch`, so a user cannot create two folded-equal terms in one vocabulary, and the `folded` set is per vocabulary, so two vocabularies sharing a term both still offer it.

**A1c (the app around the engine) — 0 H, 2 M, 6 L.** No high: an unbound
database is inert end to end under a probe driving the real engine over a
real in-memory database — no gateway call, no write, no timer, no status
emit, signed in and signed out alike. The two mediums are a
singleton-registration race the engine guards against and its two
neighbours do not (R36) and the `demo-anta` branch the S5b review already
asked to be deleted (R37, recorded at the record's own severity). The
lead re-read R36, R37 and R40 against the code before writing them.
**Defaults taken, the owner asleep:** D7 **A** — the S5b M1 item enters
the ledger here with the record's own fix text (R37, A8); D4 **A** — the
fix sessions build both mediums and the lows whose file they already
touch.
**Q1 — unbound: inert, and what the status stream first says.** Probed in
a `git archive HEAD` snapshot with the real engine, no binding, a user
set: `gateway.calls: []`, `readSpaceCalls: 0`, `pushes: 0`, timers
pending `[]`, writes `(0)`, statuses `(0)`, `engine.current ==
SyncStatus.empty`. Signed out, including an `authStateChanges` emission of
`null`, is identical bar the gate and one extra `_emit` (19 SELECTs
instead of 10). **The first value of the status stream is no value at
all:** `SyncStatusService.read` short-circuits on `binding == null` before
it looks at the user, returns exactly `SyncStatus.empty`, and `_emit`'s
`next == _current` dedupe suppresses the add — a reader sees
`engine.current`, nothing more. On a real install the outbox is not empty
(v43 queues every local write whether or not a space is bound), so the
first value becomes `SyncStatus(pendingCount: N, pause: none, binding:
null)` and nothing else (probed after one local note: `pause=none
activity=idle pending=1 binding=null lastPull=null lastPush=null
failure=null`). No timer is armed at launch — `watchQueued()` is
`tableUpdates(...)`, which does not seed on subscribe
(`sync_outbox_dao.dart:34`); one is armed 30 s after any local write, and
firing it costs 10 SELECTs, no write, no gateway call. The one write at
launch is pre-diff readiness behaviour, not this diff:
`seedClockFromStore` → `persistClock()` writes `last_hlc` once on a
database that has none (`database.dart:312-316`), read-only from the
second launch. `watchSpace` is reached only under `_attachSignal` (a
non-null binding), `readSpace` only in `_regainsAccess` behind `_pause ==
noAccess`, and `listSpaces` has no call site in `lib/` at all.
**Q2 — `getInstance()` on reset and on a switch: the engine holds, its
two neighbours do not.** Two concurrent `SyncEngine.getInstance()` calls
separated by 0–6 microtasks always return one engine, registered, with
nothing started beside it; the `raced` and `generation` checks
(`sync_engine.dart:288,296`) are taken before the engine and the bridge
are constructed, so no bridge or subscription is orphaned. The switch
itself is pinned green by `sync_engine_switch_test.dart`: the new
database's engine is built and started, the old one reads `isStarted ==
false`, one reset mid-build restarts the build, two make it throw and
register nothing. `reset()` nulls `_instance`/`_bridge` synchronously and
`stop()` sets `_stopped` before `notifyDatabaseSwitching` returns, so the
old engine halts at its next `_checkHalt` before `_closeOpened` closes the
database; the bridge's `AppLifecycleListener` is disposed by its stream's
`onCancel`. The hole is R36 — the same guard missing from
`SyncBindingService` and `SyncStatusService`. **Not verified:** a switch
landing *mid-run* (the switch suite runs `NoOpAuthService`, so the gate
always skips `signedOut` and no run is ever in flight).
**Q3 — `main.dart`.** Without `google-services.json` the init sits inside
the pre-existing try/catch, `Firebase.apps` stays empty, DI's `canSync` is
false → `NoOpAuthService`, no `SyncGateway` registered,
`_syncEngineEnabled` false, no engine, `SyncBloc` gets `engine: null` and
the Sharing page reads `SyncUnavailable`. With the config present the
build takes the single `DefaultFirebaseOptions.currentPlatform` call. The
dead branch is R37. Worth knowing for the next snapshot probe:
`lib/firebase_options.dart` is gitignored (`.gitignore:51`), so a
`git archive HEAD` snapshot cannot analyze `lib/`.
**Q4 — `SyncBindingService.bind`: the rollback contract holds.** One
`_db.transaction`; `setSyncBinding` writes the four keys into
`user_settings` through the same database
(`settings_service.dart:2263-2273`), so drift nests it and a rollback
really unbinds — pinned at three interception points (the first backfill
`UPDATE`, the merge flag, the floor) with every "nothing bound" assertion
(`sync_binding_service_test.dart:303-350`, green). The floor is written
only when absent (`:243`); the refusals while bound and while suspended
are pinned (`:263`, `:291`); `unbind` clears the pull state, the flag, the
quota mark and both run times (`:353`). The gaps are R38 (both guards
outside the transaction) and R39 (their English messages).
**Q5 — `SyncBloc`, and the Sharing page is untouched.** Signed out on an
unbound database is `SyncSignedOut(status: SyncStatus.empty)` with `pause:
none`; the mismatch state needs a binding and so is unreachable today but
is covered against a bound fixture (`sync_status_service_test.dart:49`,
`sync_bloc_test.dart:556,578`). `RefreshSyncStatus` goes through
`_readStatus`'s `.timeout(statusTimeout)` (3 s, `sync_bloc.dart:282-284`),
covered by "a stalled reader times out to the empty status".
`git diff --stat 25a5c94 HEAD -- lib/pages` lists only
`counter_per_note_page.dart`, `optimized_note_editor_page.dart` and
`vocabularies_page.dart`: `sync_settings_page.dart` is unchanged across
the whole range and reads only the account out of `SyncState`, so no
status field is rendered anywhere yet — S4b-2's absence is a pending item,
not a finding. The soft spot is R40.
**Q6 — folders: an unbound database never emits `remote`.**
`announceMerged` re-reads each id tombstones-included, drops the cached
copy and both parent caches first, then emits `deleted`/`created`/
`updated` with `remote: true` plus a second `moved` carrying
`sourceParentId` from the pre-merge row, for a live row only; the
tombstone branch of `FolderDao.mergeFolder` deliberately does not write
`parentId`, so a remotely-moved-then-deleted folder is announced under the
parent the local browser still shows it in and the old list does refresh.
The browser's refresh on `moved` is wired —
`OptimizedFolderBloc._onExternalChange` matches `change.sourceParentId ==
_currentParentId` (`optimized_folder_bloc.dart:48-52`) and
`folderChangesForParent` forwards to both sides. `afterPage` runs after
the page transaction committed (`sync_puller.dart:232` vs `:303`), so no
event escapes a rollback, and `position` is on the wire
(`tables/folders_binding.dart`, encode and decode), so
`update(folders).replace(remote)` does not clobber §5's ordering.
`announceMerged` and `nearestLiveFolderId` have exactly one caller each in
`lib/` (`app_sync_apply_hooks.dart:103,116,181`), reachable only from a
pull, which the gate refuses while unbound. **Not verified:** neither has
a unit test of its own — only the hooks' coverage
(`app_sync_apply_hooks_test.dart`, against the real `FolderRepository`).
**What could not be checked at all:** anything needing a device or
Firebase — the real `FirestoreSyncGateway.configure`, `FirebaseAuth`
`authStateChanges` at launch, and the `google-services.json`-absent build;
and the whole 10,486-test suite (`dart analyze lib` clean, the seven named
suites green at +100).

- **R36** (M, CONFIRMED; A1c) `lib/services/sync/sync_binding_service.dart:34-40` + `lib/services/sync/sync_status_service.dart:25-31` — a `getInstance()` suspended across a database switch registers a singleton the reset can never drop, and every later caller — the engine built for the *new* database included — gets a service bound to the **closed** old one. `SyncEngine._build` captures `DatabaseLifecycle.generation` before its awaits and starts over when it moved (`sync_engine.dart:288,296`); these two take the same awaits with no such guard, so when `notifyDatabaseSwitching` clears `_resetHandlers` (`database_lifecycle.dart:79-82`) while they are suspended, `_register`'s `registerResetHandler(reset)` lands in the emptied list and the reset meant to drop the instance has already run. `_build`'s retry is no help: it re-calls the same `getInstance()`, which now answers with the stale instance. Input: a switch from database A to B while a `SyncBloc` is resolving its status reader or the engine — the Sharing page open under the Settings database page. Probe in a `git archive HEAD` snapshot, `getInstance()` started and the switch landing k microtasks later: `gap 0..3: the instance survived the reset = true` / `gap 4: … = false`. Today the consequence is noise (A is unbound, so `read()` answers null or throws into `_reevaluate`'s catch); once S4b-2 binds a space, the engine whose `_db` is B reads A's binding and pushes **B's rows into A's space**, and `_checkHalt` compares against the same wrong binding and never notices — which is why this is filed now and not left to S4b-2. Fix: give both `getInstance()`s the engine's guard — capture `DatabaseLifecycle.generation` before the awaits and start over if it moved (or register the handler before the first await). Fix session: A7. → A7: fixed `lib/services/sync/sync_binding_service.dart:37-61` + `sync_status_service.dart:28-47` — both `getInstance()`s capture `DatabaseLifecycle.generation` before their awaits and start over if it moved, the engine's own guard line for line. **No pre-fix failing test:** the symptom needs two real databases and a switch landing inside the build's awaits, and in the suite `AppDatabase.getInstance()` / `SettingsService.getInstance()` resolve in microtasks, so the build always completes first; a synthetic `notifyDatabaseSwitching()` mid-build leaves both the old and the new code registering over the same database, with nothing to assert on. All 355 sync tests including `sync_engine_switch_test.dart`'s reset-mid-build group stay green.
- **R37** (M, CONFIRMED; A1c) `lib/main.dart:236-253` + `lib/core/qa/qa_mode.dart:1,53-64` — S5b **M1**, still open: the `demo-anta` branch and `QaMode.emulatorFirebaseOptions()` are dead on Android (the google-services plugin has already created the native default app, so `Firebase.initializeApp(options: …)` returns it and the `projectId` mismatch only `debugPrint`s) and, where Dart creates the default app itself (iOS, no tracked plist), would run the pass under `demo-anta` — the opposite of what the record settled; the branch's own doc comments say the opposite of the record. `git diff 25a5c94 HEAD -- lib/main.dart` is exactly this branch. No user build is affected: `QaMode.useFirebaseEmulator` is a `const` false, so it is shaken out (the reviewer graded it L for that reason; recorded at the record's M because the doc comments contradict the record and the iOS path would reintroduce the mismatch). Fix (the record's): delete the branch and `QaMode.emulatorFirebaseOptions`/`firebaseEmulatorProject`, initialise with `DefaultFirebaseOptions.currentPlatform` on every path, drop the `firebase_core` import from `lib/core/qa` (S5b L8). Fix session: A8.
- **R38** (L, PLAUSIBLE; A1c) `lib/services/sync/sync_binding_service.dart:113-124` — `bind`'s two refusals (`await read() != null`, `SyncSuspension.isSuspended`) are checked *before* `await _db.transaction`, so two concurrent binds both pass the "not bound" check and both bodies run: the second overwrites the first binding's four keys, backfills `owner_id` again and `requeueAll`s a second time, and the loser's `if (await bindFloor() == null)` guard sees the winner's floor. Input: a double tap on the picker's confirm, or "create space" racing a picked space — unreachable until S4b-2 ships the picker, which is why it is an L. Fix: move both guards inside `_db.transaction(...)`, before the first write. Fix session: A7. → A7: fixed `lib/services/sync/sync_binding_service.dart:135` — both refusals moved inside `_db.transaction`, before the first write. Test `two binds started together: the second is refused, not applied over the first`, verified failing pre-fix (`Expected: an object with length of <1> / Actual: WhereTypeIterable<StateError>:[]`).
- **R39** (L, PLAUSIBLE; A1c) `lib/services/sync/sync_binding_service.dart:114-122` — the two bind refusals are hard-coded English `StateError` messages (`'Cannot bind while this database is bound: stop syncing first.'`), where record §3.6 says a refused bind shows "a visible reason". Nothing surfaces them yet, so the three-ARB rule is not breached by this diff (all three ARBs changed together, `untranslated.txt` is `{}`); recorded so the surfacing step maps both refusals to `AppLocalizations` keys instead of printing the exception text. Fix: two ARB keys when S4b-2 surfaces them. Fix session: A7 (or `→ deferred: S4b-2` if the fix session would rather land it with the picker). → A7: **deferred: S4b-2**, the branch the id itself offers. Nothing surfaces either refusal today, so the three-ARB rule is not breached; the two keys land with the picker that first shows them.
- **R40** (L, PLAUSIBLE; A1c) `lib/bloc/sync/sync_bloc.dart:212-243` (read at `:157-171`) — a `SyncBloc` that outlives a database switch keeps following the engine `SyncEngine.reset()` dropped, and lays the **old** space's `lastPullAt`/`lastPushAt`/`pause`/`parkedCount` over the new database's fresh read. `_followEngine()` runs only from `_onLoad` (`:74`) and `_onSignIn` (`:85`), so nothing re-resolves the engine on a refresh, and the dropped engine's status stream is deliberately left open (S3c F9) — `RefreshSyncStatus` repeats the stale overlay every time. Input: the Sharing page left mounted under the Settings database page while the user switches databases. Invisible today because `sync_settings_page.dart` reads only the account out of `SyncState` (no `status.` access in the file) and the test at `test/bloc/sync_bloc_test.dart:622` pins only the load-after-switch case. Fix: call `_followEngine()` from `_onRefresh` too — it is already idempotent through `identical(engine, _followedEngine)`. Fix session: A6. → A6: fixed `lib/bloc/sync/sync_bloc.dart:136-140` (`_followEngine()` from `_onRefresh` too), test `a refresh after a database switch follows the new engine, not the old (A1c review R40)`, verified failing pre-fix. **Only half closed as first built** — the follow was fire-and-forget and the very next line still read the old engine's status, so the triggering refresh still carried the stale overlay: R112 awaits the follow and strengthens the test.
- **R41** (L, CONFIRMED; A1c) `test/services/sync/sync_engine_lifecycle_test.dart:746` — nothing pins the contract §4 makes binding. The only unbound coverage is `expect((await a().sync()).skipped, SyncRunSkip.unbound)`; no test asserts that `start()` on an unbound database makes **zero** gateway calls, issues **zero** non-SELECT statements, arms **no** timer and emits **no** status — the four things Q1 proved by probe, and the four a later fix session could quietly break. Fix: land the probe as a test — `final pair = await SyncPair.open(bind: false); pair.a.statements.reset(); await pair.a.engine.start(); await pair.a.settle();` then `expect(pair.gateway.calls, isEmpty); expect(pair.gateway.readSpaceCalls, 0); expect(pair.a.scheduler.pending, isEmpty); expect([for (final c in pair.a.statements.captured) if (!c.isSelect) c.sql], isEmpty); expect(pair.a.engine.current, SyncStatus.empty);` — once with `user` set, once with `a.user = null` plus `a.auth.add(null)`. Fix session: A7. → A7: fixed `test/services/sync/sync_engine_lifecycle_test.dart:813` — the A1c probe landed as two cases, `an unbound database is inert end to end, signed in` and `… signed out`, each asserting zero gateway calls, zero `readSpace` calls, no pending timer, no non-SELECT statement, `SyncStatus.empty` and an empty status stream after `start()`.
- **R42** (L, CONFIRMED; A1c) `lib/models/folder_change.dart:16-18`, written at `lib/repositories/folder_repository.dart:563,580` — `FolderChange.remote` has no reader: `grep -rn "\.remote\b" lib/pages lib/bloc lib/services` yields exactly one, `optimized_note_editor_page.dart:1153`, which is `NoteChange.remote`. Cheap symmetry with notes and harmless to keep; recorded so nobody reads the folder flag as load-bearing. Fix: none required, or one `///` line saying it is for a future reader. Fix session: A6. → A6: fixed — one `///` on `lib/models/folder_change.dart:16-21` saying the flag is symmetry with `NoteChange.remote`, kept for the first folder surface that needs it, and not load-bearing.
- **R43** (L, PLAUSIBLE; A1c) `lib/repositories/folder_repository.dart:68-79` — `nearestLiveFolderId` walks the ancestor chain one `SELECT … WHERE id IN (?)` at a time, and `fileConflictCopy` calls it while the pulled page's write transaction is open (`app_sync_apply_hooks.dart:181`), so a copy under a ten-deep chain of tombstoned ancestors costs ten round trips with the transaction held. Correct as written (the `seen` set guards a cycle; returning `folderId` for an unknown row matches its documented intent) — recorded only because it sits on the pull's write path. Fix: one recursive CTE. Fix session: A6. → A6: **deferred** — `lib/repositories/folder_repository.dart:68-79`: one recursive CTE for `nearestLiveFolderId`, which today costs one `SELECT` per ancestor with the pulled page's write transaction held. No H or M fix of this session opens that file, so D4 A leaves it; correct as written, only slow.

**A2 (the engine core) — 1 H, 2 M, 15 L.** The engine's own shape holds:
the run loop is a strict single flight, the ack arithmetic loses nothing,
the bisection terminates, and the two risk-register paths are pinned by
real two-device tests. The H sits at the seam between the gateway and the
puller, where each file assumes the other advances the cursor. The lead
re-read R44 and R45 against the code before writing them.
**Q1 — a drain can never precede the pull under the floor.** `drain` is
called from one place (`sync_engine.dart:592`) behind three sound guards:
`:577` kills a background drain outright, `:578` promotes a `stale` run to
a full pull whenever `bind_merge_pending` is set, and `:591` drains nothing
after a pull cut by a leave. Every trigger funnels through `_run`, and
`_request` (`:512-517`) only ever *raises* the mode over the ordered
`drain < stale < full`, so a coalesced drain+full is a full run. The flag
is read at `:576`, after `_gate`'s binding read, and `bind` writes the
binding and the flag in one transaction over an uncached SELECT, so the two
reads cannot disagree in the dangerous direction. One transaction and one
`persistClock` per page hold (`sync_puller.dart:232-300`, pinned at
`sync_engine_test.dart:671`).
**Q2 — a replayed page is idempotent.** `resumed` is set only before a
table's first `pullPage` and cleared right after (`sync_puller.dart:166-175`),
so no page can re-overlap itself; a replay hits `remoteHlc == localHlc` →
`MergeResult.unchanged`, with no write, no outbox touch and no loser. The
conflict copy needs `localHadPendingPush`, which is the return of the
`ackThrough` that just deleted the entry — so the copy is filed exactly
once, not once per replay (`note_dao.dart:978-990`). Pinned end to end at
`sync_engine_test.dart:462` (green this session).
**Q3 — the ack boundary and the bisection.** `_send` acks at
`queued.envelope.hlc` — the stamp read at load time — and `ackThrough` is a
compare-and-delete at `hlc <= stamp` (`sync_outbox_dao.dart:53-63`), so a
row edited between load and ack stays queued; a vanished row's entry is
retired at `entry.hlc` the same way, so a concurrent re-insert survives.
`_isolate` halves and parks at length 1, never re-sending a list, and the
8 MiB cap is a pre-split that always carries at least one row. **A single
oversized row parks and does not loop**: by size in `_prepare`
(`maxDocumentBytes`), or through `invalidData` → `_isolate` → `_park`;
`eligible` then excludes it by `(table,key) → stamp`, so every iteration of
the drain makes progress (pinned, `sync_engine_failures_test.dart:217,633,655`).
**Q4 — S5 M3 is real and is fixed.** `_abortsTransaction`
(`sync_puller.dart:352-359`) unwraps `DriftRemoteException.remoteCause` in a
`while` loop before testing `CouldNotRollBackException || (SqliteException
&& resultCode != 19)`, so a transaction-aborting SQLite error fails the page
whole while any other exception parks the envelope — and this is the rare
place tested *on a background-isolate database*:
`sync_engine_failures_test.dart:572-613` runs the disk-full and
refused-statement probes `for (final background in [false, true])`. Noted,
not filed: after SQLITE_FULL aborts a page the pull continues to the next
table against the same full disk, so every later table faults too — all
recorded, the run reports `unknown`, nothing commits.
**Q5 — concurrency.** N triggers give one run (`_request` folds into one
`_RunRequest`; `_pump` sets `_pumping` synchronously; `_loop:528-542` drains
`_queued` with no suspension point before the `break`), and a trigger during
a run re-runs exactly once (pinned, `sync_engine_lifecycle_test.dart:303`).
`SyncSuspension` is checked before push, pull and bind (`:642`, `:680`,
`:691`, the last re-checked after the await the binding read spans).
**A suspension beginning mid-run**: the granularity is the page and the
batch — one that starts after `_apply`'s `_checkHalt` lets the page
transaction commit, one that starts after `_send`'s lets `pushBatch` and the
ack land. Inside the record's contract (and the restore unbinds anyway), so
nothing is filed; the honest answer is that the in-flight page finishes.
**Q6 — `pauseOver` and the exits.** The precedence is two-tier
(`:979-992`): the reader's `signedOut`/`accountMismatch` first, because no
account or the wrong one makes a stored pause stale, then the engine's
`noAccess`/`appOutdated`/`quotaExhausted`; `sync_status_service.read` only
ever produces the two account pauses, so the tiers cannot collide (pinned,
`sync_engine_lifecycle_test.dart:731`). Exits: `quotaExhausted` by
`_reached` on the first call of any run, with `_quotaHeld` lifted by the
hourly retry, a resume or "Sync now" and never set by `start()`;
recheckable `noAccess` by `_regainsAccess`'s one `readSpace` or any sign-in;
`noAccess` with `recheckable: false` by sign-in or relaunch *by design*; the
account pauses recomputed on every `_emit`; `suspended` by the next signal,
snapshot or resume, with the signal deliberately kept so the newer `touched`
still picks the right tables. Nothing can stick **within one space** — but
the pause is engine-instance state that survives `stop()`/`start()` and an
unbind/rebind (R45), and `appOutdated` has no in-session exit at all
(`:646` returns the skip before any recheck; `:851` clears only `noAccess`).
**Q7 — H1 and H2 both CONFIRMED end to end**, by running the two
`sync_pair` tests by name rather than by probe. H2
(`sync_engine_test.dart:440`): a folder merged onto B at
`000000000001:0000:B` — below everything A's cursor passed — is requeued,
pushed and still pulled by A, because the arrival cursor is built from
`pushedAt` + document id (`firestore_sync_gateway.dart:158-166`), never from
the HLC. H1 (`:483`): A's stale envelope pushed straight over B's newer row
is repaired inside **one** run — `requeueRow` fires in the page transaction
(`crdt_merge.dart:57`) and the drain is after the pull — asserting
`MergeResult.keptLocal`, `repair.pushedRows == 1` and `expectConverged()`.
Residual, matching §6: the repair waits for a later run if that key is
parked at the same stamp or its table is in `skipTables`; it never diverges
permanently.
**Q8 — the scheduler.** "30 s after the last outbox write" is observed
through drift, not a clock: `watchQueued()` is a `tableUpdates` stream
limited to `UpdateKind.insert`, which `CrdtWrite` declares
(`crdt_write.dart:219`), so a queued or raised entry fires it while the
engine's own `ackThrough` deletes do not; `_armDebounce` cancels and
re-arms, so under continuous typing the debounce never matures and the
first push is the leave or a 30 s pause (the record's wording, so nothing
filed). **An hour in the background**: `onAppBackgrounded` cancels the
debounce and both retries, detaches the signal and awaits one drain-only
run; `_scheduleBackoff` and `_scheduleSignalRetry` then return early on
`!_foreground`, so the only timer that can still fire is a fresh debounce
from a later outbox write, which runs a drain-only pass (and Doze freezes
even that). The backlog coalesces to one outbox entry per row however many
edits, the drain takes `maxBatch` at a time, and a drain killed mid-page
loses nothing because an entry is retired only after `pushBatch` returned.
`onAppResumed` resets both back-offs, lifts the quota hold and runs a full
pull.
**Not verified:** R44's reachability on real Firestore (`FakeSyncGateway`
never skips a document, and the reviewer may not add the switch), R45's
trigger (it needs S4b-2's bind/unbind flow, so the carry-over is latent and
was proved by reading all seven `_pause =` sites), the three Firestore-only
behaviours of §3.3 (the 10 s overlap against real `serverTimestamp()` skew,
`runTransaction` offline, `shouldForwardSnapshot` — A8's), and the whole
10,486-test suite. `crdt_merge.dart`, the bindings and the hooks were read
only as far as Q2 and Q4 needed; their defects are A3a/A3b/A4's and none was
filed here. No snapshot was needed and none was made: every question that
would have taken a probe was answerable by running an existing suite
read-only.

- **R44** (H, PLAUSIBLE; A2) `lib/services/sync/sync_puller.dart:178` — `if (page.envelopes.isEmpty) break;` leaves a table's pull **without storing `page.next`** (the cursor is persisted only inside `_apply`'s page transaction, `:232-300`), so a page the gateway answered non-empty but whose envelopes were all skipped pins that table's cursor for good: every later run re-reads the same window and no row beyond it ever reaches this device. The two files contradict each other — `firestore_sync_gateway.dart:174` skips a document `envelopeOf` refuses with the comment "skipped like a parked envelope, so one cannot pin the pull at this cursor", and advances `next` over it at `:160-163`, which the puller's `break` then discards. Input: one full page (`limit` = 499 documents) in one table where every document is skipped — a newer build writing a different document shape, or rows whose `hlc`/`deviceId`/`version`/`op`/`ownerId`/`data` do not type-check. Fix: when `envelopes` is empty but `page.next != cursor`, store `next` (a bare `syncDao.setValue`) and continue while `hasMore`, instead of breaking. Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:189` — a page whose envelopes are all skipped stores `next` and continues while `hasMore`, instead of breaking. Test `a page with a cursor and hasMore but no envelope advances the table past it` (with a new `FakeSyncGateway.unreadable` switch), verified failing pre-fix (`Expected: <1> / Actual: <0>` — the row past the skipped page never arrived and the cursor stayed null). Residual R137: on a `resumed` page the stored `next` could move the cursor backwards; fixed in the same session.
- **R45** (M, PLAUSIBLE; A2) `lib/services/sync/sync_engine.dart:405-417` — `start()` restores `_pause` from the stored quota mark but resets no other run state, and neither `stop()` nor a binding change clears it: `_pause`, `_quotaHeld`, `_accessRecheckable`, `_backoffStep`, `_signalBackoffStep`, `_lastFailure`, `_downloadedRows`, `_puller.parked` and `_pusher.parked` all survive a `stop()`/`start()` pair and an unbind followed by a bind to a **different** space. Input: the space is deleted or written by a newer schema → `_loseAccess(noAccess)` / `_loseAccess(appOutdated)`; the user unbinds and binds a healthy space (S4b-2's flow, which stops and starts the engine). What goes wrong: `_gate:643-648` keeps refusing — `appOutdated` has no in-session exit at all (`:646` returns the skip before any recheck; `:851` clears only `noAccess`), so sync is dead until the process restarts; for `quotaExhausted` the shape is worse, because `unbind()` deletes `quota_paused_at` (`sync_binding_service.dart:172`) while `_quotaHeld` stays `true` in memory, so runs skip as `paused` until the hourly retry or a resume. Same class as the S3d **M4** fix for `_foreground`, one field wider. Fix: reset the pause, the quota hold, both back-off steps, the failure, `_downloadedRows` and both parked sets at the top of `start()`, before the stored quota mark is read. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:424` — `start()` clears the pause, the quota hold, `_accessRecheckable`, both back-off steps, `_lastFailure`, `_failureFromSignal`, `_downloadedRows` and both parked sets before the stored quota mark is read. Test `a stop and a start clear the pause, the quota hold, the back-off and the parked sets` (R59's twin), verified failing pre-fix (`Expected: SyncPause:<SyncPause.none> / Actual: SyncPause:<SyncPause.quotaExhausted>`).
- **R46** (M, PLAUSIBLE; A2) `lib/services/sync/sync_pusher.dart:118-130` — `_prepare` catches a `loadByKeys` fault **per table group, not per row**, and parks every entry of that table in the batch at its current stamp (`for (final entry in group) _park(entry, error);`) — up to `maxBatch` rows, for the whole session, with only a `debugPrint` to show for it. Input: `_bindingFor(table)` returns null for an outbox entry whose table has no `SyncTableBinding`, raising `ArgumentError.value(table, 'table')` at `:122`, which `_isEnvelopeFault` grades as an envelope fault; or any `InvalidDataException`/`TypeError` out of a binding's load. What goes wrong: up to 499 healthy rows of that table stop pushing for the session, and again every session since the cause is deterministic; `parkedCount` rises but nothing says the whole table is stalled. Fix: hoist the `binding == null` check out of the fault path and fail the run (it is a programming error, not a document), and bisect the group on a load fault the way `_isolate` bisects a refused batch. Fix session: A7. → A7: fixed `lib/services/sync/sync_pusher.dart:135,177` — a missing binding fails the run as the programming error it is, and a load fault is bisected through the new `_loadGroup` instead of parking the whole table. Tests `a load fault is bisected to its own rows…` (pre-fix `Expected: <1> / Actual: <4>` parked) and `an entry naming a table no binding covers fails the run rather than parking the table` (pre-fix `Expected: SyncGatewayFailure:<SyncGatewayFailure.unknown> / Actual: <null>`). Residual R134: the run-ending throw left the entry queued and so failed every later run; fixed in the same session by parking that one entry after the report.
- **R47** (L, PLAUSIBLE; A2) `lib/services/sync/sync_puller.dart:303` — `await _e._hooks.afterPage(...)` runs unguarded after the page has already committed, so a throwing cache hook turns a fully applied page into a table fault: `pull:93-104` records the table in `failedTables`, the run reports `unknown`, the back-off grows and the drain skips that table. `notifyRun:141-145` was given the opposite rule by the S3d **L17** fix ("a throwing hook must not fail a run whose rows all landed"); `afterPage` and `beforePage:224` never got it. Input: any `AppSyncApplyHooks` hook throwing — a counter reload over a closed database, a storage change listener. Under `bind_merge_pending` a deterministic throw keeps `complete == false` forever, so the floor rule and the skip never lift. Fix: wrap `afterPage` in the same `try`/`_warn` as `notifyRun`, and leave `beforePage` throwing (it precedes the page, so failing there is correct). Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:332` — `afterPage` wrapped in the same `try`/`_warn` as `notifyRun`; `beforePage` deliberately still throws, because it precedes the page. Test `a throwing afterPage fails neither the page nor the run, while a throwing beforePage still faults the table` (R61's twin), verified failing pre-fix (`Expected: null / Actual: SyncGatewayFailure:<SyncGatewayFailure.unknown>`).
- **R48** (L, PLAUSIBLE; A2) `lib/services/sync/sync_puller.dart:259` — `parked.remove((envelope.table, envelope.rowKey))` mutates in-memory state **inside** the page transaction, so it survives a rollback: if a later envelope on the same page aborts the transaction or a conflict copy throws, the key leaves `_puller.parked` while its remote version was not applied, breaking the S3d **H2** invariant that pull-parked keys stay out of the drain for the session. Masked today because the same page also puts its table in `skipTables` for that run. Fix: collect the un-parked keys in a local list and apply them to `parked` after the transaction commits, beside `touched.add` at `:301`. Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:252` — the un-parked keys are collected in a local list and applied after the transaction commits. No test: the id itself records that the case is masked today by `skipTables`; the existing parked-key suites stay green.
- **R49** (L, PLAUSIBLE; A2) `lib/services/sync/sync_engine.dart:528-542` — `_loop` has a `finally` but no `catch`, so a throw escaping `_run` leaves `request.done` uncompleted forever: `syncNow()`'s future never resolves (the Sharing page spins for the session) and the throw surfaces as an uncaught async error through `unawaited(_loop())`. `_run`'s own catch-all covers today's paths — the S3b **M4** fix put `_gate` inside it, pinned at `sync_engine_failures_test.dart:204` — but the handler bodies themselves (`await _failed(...)` in the catch at `:624`, `_emit()` in the finally) sit outside any net. Fix: wrap the `await _run(...)` in `_loop` so a throw completes the request with an `unknown`-failure report. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:576` — the `await _run(...)` in `_loop` is wrapped so a throw past `_run`'s own handlers completes the request with an `unknown`-failure report. No test: no reachable seam throws there today (`_emit` is serialized and catches, `_failed`'s store is already guarded).
- **R50** (L, PLAUSIBLE; A2) `lib/services/sync/sync_pusher.dart:113-118` — `_prepare` regroups the batch `byTable`, discarding the `(hlc, table, rowKey)` order `SyncOutboxDao.pending` produces "so a push that stops part-way has sent a prefix of history rather than a random sample". After `_byBytes` splits or `_isolate` bisects, the acked set is a prefix by *table group*, not by stamp, so a receiver can see a child row land while its parent's push is still queued. Harmless today (`sync_tables.dart:21` records that nothing in SQLite enforces the order and the parent arrives on a later drain), but it contradicts the DAO's stated contract. Fix: build the envelopes grouped (one query per table) and emit `batch` back in the entries' original order. Fix session: A7. → A7: fixed `lib/services/sync/sync_pusher.dart:167` — the envelopes are built grouped (one query per table) and emitted back in the entries' original `(hlc, table, rowKey)` order. Test `a batch goes out in the queue's order, not table by table`, red pre-fix on the grouped order.
- **R51** (L, PLAUSIBLE; A2) `lib/services/sync/sync_pusher.dart:97-102` — `_nextEntries` re-reads the queue from the top with a doubling limit on every iteration of the drain's `while (true)`, so with many ineligible keys each batch costs O(queue) reads and the drain is O(n²). Input: the initial merge after a bind, where `requeueAll` has queued every row of every table and one table faults into `skipTables`. Fix: give `pending` an `after (hlc, table, rowKey)` keyset argument and page forward instead of re-reading from the top. Fix session: A7. → A7: fixed `lib/services/sync/sync_pusher.dart:95` + `SyncOutboxDao.pending({after})` with a new `SyncOutboxKey` — the drain pages forward by keyset instead of re-reading the queue from the top. Test `pending resumes after an entry already read`.
- **R52** (L, PLAUSIBLE; A2) `lib/services/sync/sync_puller.dart:249-253` — `queued ??= { for (final entry in await db.syncOutboxDao.pending()) ... }` loads the **entire** outbox into memory, unlimited, on the first park of a page under the floor, then filters it to one table; during the initial merge that is every row of every synced table. Fix: add a `pendingForTable(String table)` query, or pass a `limit` plus the page's keys. Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:273` + `SyncOutboxDao.pendingForTable` (`sync_outbox_dao.dart:52`) — the park under the floor reads one table instead of the whole outbox. Test `pendingForTable reads one table, oldest change first`.
- **R53** (L, PLAUSIBLE; A2) `lib/services/sync/sync_engine.dart:678-692` — `_checkHalt`'s doc says "Cheap enough for every page: one settings read", but `_binding.read()` is `SettingsService.getSyncBinding`, which issues three or four uncached `UserSettingsDao.getValue` SELECTs (`settings_service.dart:2237-2250`), and `_checkHalt` runs before every page *and* every push batch — on the app's background-isolate database that is three to four port round trips per page. Fix: correct the count in the doc, or add a one-shot read of the four keys in one SELECT. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:738` — the doc now states the real cost (three or four uncached `UserSettingsDao.getValue` SELECTs per page and per push batch), the id's second option. The one-SELECT read was not built: it would change `SettingsService.getSyncBinding`, which S4b-2 also reads.
- **R54** (L, PLAUSIBLE; A2) `lib/services/sync/sync_pusher.dart:288-295` — the pusher's `_park` logs every reason at `debugPrint`, where the puller's (`sync_puller.dart:328-338`) follows the S3b **L16** rule and raises an `ArgumentError` to `_warn` as "probably a bug". The push side's most likely `ArgumentError` is R46's missing binding — exactly the programming error L16 exists to surface. Fix: mirror the puller's three-way log in the pusher's `_park`. Fix session: A7. → A7: fixed `lib/services/sync/sync_pusher.dart:338` — `_park` mirrors the puller's three-way log, with the push's own expected kinds (a `String` reason and a `SyncGatewayException` refusal) kept at `debugPrint` and the unexpected `ArgumentError` raised to `_warn`.
- **R55** (L, PLAUSIBLE; A2) `lib/services/sync/sync_puller.dart:187` — `_downloadedRows` is reset only when the initial pull *completes* (`:126`), so each cut or faulted attempt adds its pages to the previous attempt's count and the bind progress reports more rows than the space holds (overlap rows twice). Fix: zero `_downloadedRows` at the start of a run where `initial` is true. Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:70` — `_downloadedRows` is zeroed at the start of an `initial` run, so a cut attempt no longer adds its pages to the previous one's count. No test: a cut initial attempt needs a mid-pull leave and is not cheap to drive.
- **R56** (L, PLAUSIBLE; A2) `lib/services/sync/sync_engine.dart:577` — the initial-merge refusal of a drain-only run returns a bare `report()` with `skipped == null` and `failure == null`, indistinguishable from a successful no-op, while `onAppBackgrounded`'s own doc promises the caller can tell ("Completes when that drain has run **or was skipped** — skipped while the initial merge is pending"). Fix: return `report(skipped: ...)` with a `SyncRunSkip` value. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:75,627` — a drain-only run refused by the pending initial merge returns `SyncRunSkip.initialMergePending` rather than a bare report. Residual R142: the new value had no reader; closed in the same session by having `onAppBackgrounded` return its report and asserting it.
- **R57** (L, PLAUSIBLE; A2) `lib/services/sync/sync_engine.dart:736-740` — `_reached` clears `_pause == quotaExhausted` only when a run actually reaches the space, but `onAppResumed`/`syncNow` clear `_quotaHeld` without clearing `_pause`, so a run that makes zero gateway calls (a `stale` run with no stale table and an empty outbox) leaves the status showing a quota pause while sync is in fact unblocked. Cosmetic; cleared by the next full run. Fix: clear `_pause` alongside `_quotaHeld`, or derive the quota pause from `_quotaHeld`. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:500` — a new `_liftQuotaHold()` clears `_pause` alongside `_quotaHeld`, used by `syncNow` and `onAppResumed` (the two the id names; the quota retry timer runs a full run immediately after lifting, so it needed none). No test: it needs a run that makes zero gateway calls while a quota pause shows.
- **R58** (L, PLAUSIBLE; A2) `test/services/sync/sync_engine_failures_test.dart` — nothing at the engine level pins the record's rule "`ackThrough` each entry at the HLC the row had when read (an entry bumped by an edit during the push stays queued)". The DAO's compare-and-delete is pinned (`test/database/sync_outbox_test.dart:784,795`), but no test lands an edit between `_prepare` and `pushBatch`, so a regression that acked at `entry.hlc` or at the stamp read after the push would stay green and silently drop an edit. Fix: a `sync_pair` test with a gateway whose `pushBatch` edits the row before returning, asserting the entry survived and the next drain converges. Fix session: A7. → A7: fixed `test/services/sync/sync_engine_failures_test.dart` — test `an edit landing during the push keeps its entry queued, and the next drain sends it`, on a new `FakeSyncGateway.onPushBatch` seam that edits the row before returning. The same drain re-reads the raised entry and converges in one run, so the case pins `pushedRows == 2` and the space holding `Edited`; an ack at the wrong stamp gives 1 and `First`.
- **R59** (L, PLAUSIBLE; A2) `test/services/sync/sync_engine_lifecycle_test.dart:575` — the stop/start group covers subscriptions and `_foreground` (S3d **M4**) but nothing pins that a `stop()`/`start()` pair, or an unbind followed by a bind to another space, clears the pause, the quota hold, the back-off steps and the parked sets. Pairs with R45. Fix session: A7. → A7: fixed — R45's test above, `a stop and a start clear the pause, the quota hold, the back-off and the parked sets`.
- **R60** (L, PLAUSIBLE; A2) `test/services/sync/sync_engine_test.dart:702` — "hasMore, then an empty page" is pinned, but not the inverse: a page the gateway answered with `next` and `hasMore: true` yet zero envelopes. Pairs with R44 and needs a `FakeSyncGateway` switch that drops envelopes while keeping the cursor. Fix session: A7. → A7: fixed — R44's test above, `a page with a cursor and hasMore but no envelope advances the table past it`, with the new `FakeSyncGateway.unreadable` switch.
- **R61** (L, PLAUSIBLE; A2) `test/services/sync/sync_engine_lifecycle_test.dart:624` — "a throwing afterRun neither masks a halt nor fails a run" has no `afterPage` or `beforePage` twin. Pairs with R47. Fix session: A7. → A7: fixed — R47's test above, `a throwing afterPage fails neither the page nor the run, while a throwing beforePage still faults the table`.

**A3a (the wire and the merge: core and the browser tables) — 2 H, 2 M, 10
L.** Every column of the six browser tables is accounted for — the matrix
below is the record of that, and no column was left unclassified. The wire
itself is sound: Drift stores a `DateTimeColumn` as unix seconds under the
project's default options, so a row read back already carries zero
milliseconds and the `WireFields.fieldMs` ×1000/÷1000 round trip is exact
in both directions with no rounding (the readiness repair trap does not
bite here). `WireFields`' four strictness properties hold and are pinned
for all six tables by `expectStrict` (`sync_codec_test.dart:94-132`);
`mergeRemoteRow`'s five paths each match §3.4 and `db.hlc.update` sits
after the if/else so it fires on all five; `ackThrough` and `requeueRow`
mint no stamp (`sync_outbox_dao.dart:53-63` compare-and-deletes, `:107-124`
is an `INSERT … SELECT … hlc_timestamp FROM <table>`). The two highs are
both outside the codec: the backup restore drops columns the merge
converges (R62), and a remote move can close a `parent_id` cycle that
takes its folders and their notes out of the browser for good (R63). The
lead re-read R62, R63 and R72 against the code before writing them, and
corrected R62's scope (see the id).
**Q4 — notes hold.** Chunk replacement is atomic (`mergeNoteDocument`
wraps everything in a transaction at `note_dao.dart:960`, the puller nests
another per envelope, so a throw parks the envelope and leaves no half
body). A merged note **is** searchable: `_removeFromFtsIndex` runs before
`update(notes).replace`, while the content table still holds the indexed
text (the `content=notes` requirement at `note_dao.dart:366-370`), and only
when `!local.isDeleted`, which honours the "removing one it never had
would corrupt `notes_fts`" invariant at `:1158`. The loser rule's four
conditions are all present and correct at `:978-988` — live local,
unpushed, **strictly** newer by stamp, above the bind floor — plus the
text-differs check. A tombstone does not orphan the chunks: it soft-deletes
them under the remote stamp (`:993-996`, S2a F5) and does not throw.
**Q6 — counters hold.** `noteId == ''` survives exactly: encode writes
`'noteId': ''`, decode takes it from the row key and `expectSame`s it, and
it is never `null` (pinned, `sync_codec_test.dart:417-432`). A value whose
counter is tombstoned is stored as received and hidden by `CounterService`
(pinned, `counter_merge_test.dart`), and the backup already filters values
to live counters (S2a F6). `owner_id` itself survives the backup round trip
for all six tables; the columns that do not are R62.
**`content_chunks`** has no binding (`travelsWithParent: true`) and is
rebuilt from the note's `content` by `ContentChunkDao.replaceChunks`. Its
`ownerId` has no writer anywhere in the tree, so it is NULL on every
install — which matches its own doc ("here for parity with `notes` only")
and nothing reads it (`ownedRowsWhere` is used only by the calendar's
`tombstoneAll`, and `requeueAll` skips `travelsWithParent` tables). Not a
finding.
**No §7 decision came into question; the defaults stand.** Two lead
defaults, both reversible by editing a `Fix session:` field: **(a)** R62
and R71 go to **A6** rather than A7 — their fix is in the import pipeline
and the browser's sort, not in the wire; **(b)** R62's `position` claim was
dropped on the lead's re-read: `importFolder`'s own doc
(`folder_dao.dart:187-191`) says position is deliberately re-appended "so
the folder shows up at the end and doesn't fight existing ordering", and
`importNote` takes no position at all, so positions are by design on
import and the fix must not change them.

- **R62** (H, CONFIRMED; A3a) `lib/services/backup_service.dart:399-412` (folders) and `:414-432` (notes) — the backup restore drops the synced columns the merge converges: `created_at`, `updated_at` and, for folders, `note_sort_order` and `subfolder_sort_order`. The export carries all of them (`:68-69`, `:78-88`), and `FolderDao.importFolder` (`folder_dao.dart:191`) and `NoteDao.importNote` (`note_dao.dart:226`) exist precisely to preserve them — but `importFromJson` calls `createFolder` (`folder_dao.dart:143`) and `createNote` (`note_dao.dart:162`) instead, which stamp `DateTime.now()` and take no sort orders; the two `importX` methods are reached only by the folder-archive path (`folder_storage_service.dart:192`). Input: device A sets a folder's `noteSortOrder`, device B merges it (the wire carries it, `folders_binding.dart:48-49`), the owner exports and restores — the sort preference and both dates are gone. Breaks "positions, sort preferences" on both must-not-change lists and the gate rule "`createX` stamps now, `importX` preserves". Pre-existing, not introduced by the eleven `sync:` commits, but Q7 is this question and the wire is now the only place these columns travel. Fix: route `importFromJson`'s two loops through `importFolder` / `importNote` with the archived dates and sort orders. **Not** `position`: `importFolder`'s doc says it is re-appended on purpose and `importNote` takes none — leave both alone. Fix session: A6. → A6: fixed `lib/services/backup_service.dart:402` (folders) and `:426` (notes) — both loops route through `FolderDao.importFolder` / `NoteDao.importNote` with the archived `createdAt`, `updatedAt` and the two folder sort orders; new `_archivedDate` helper at `:697`. `position` untouched, both `importX` still append (pinned by R123). New test `test/services/backup_service_dates_and_sort_order_round_trip_test.dart` — "a restored folder and note keep their archived dates and sort orders", **verified failing pre-fix** (`Expected: DateTime:<2024-03-04 05:06:07.000> / Actual: DateTime:<2026-10-27 18:52:20.000>`) — and "an archive that carries no dates or sort orders still restores". **Deviation:** `importFolder` (`folder_dao.dart:197`) and `importNote` (`note_dao.dart:228`) both gained `ownerId`, which `createFolder`/`createNote` carry — routing the loops through them unchanged would have dropped `owner_id` on every restored row, a new H; `folder_dao.dart` also gained an optional `updatedAt` (null → now) so the folder-archive path keeps its semantics. Older archives: a missing or unparsable `createdAt`/`updatedAt` falls back to the restore's own time, a missing sort order to `Value.absent()`; the export is unchanged and the format stays 7.
- **R63** (H, PLAUSIBLE; A3a) `lib/database/daos/folder_dao.dart:752-786` (`mergeFolder`) — a remote move can close a `parent_id` cycle, and the cycle's folders plus every note under them leave the browser for good. `mergeFolder` writes `parentId` verbatim; the descendant check runs on the local path only (`moveFolder`, `:288-291`). Input: device A moves folder X under Y while device B moves Y under X; each passes its own check, and after both merges every device holds `X.parent = Y`, `Y.parent = X`. The outcome is a lost subtree, not a hang: the root list is `parentId IS NULL` (`:35-36`, `watchFoldersByParent` `:790-800`) so neither X nor Y nor any descendant appears at the root, while the recursive CTEs terminate on `depth < maxFolderDepth` (`:552`, `:709`) and `getAncestors` breaks on its `visited` set (`folder_storage_service.dart:368`) so nothing spins. The subtree is then reachable only through search or a restored navigation stack, and nothing repairs it. A backup/restore makes it permanent: `_foldersParentsFirst` (`backup_service.dart:694-720`) stops the walk at the cycle, so the first-placed member keeps its archived parent id, which the id remap turns into a dangling parent — the doc comment at `backup_service.dart:691` ("a cycle no export could produce") is now stale, because a merge can produce one. Fix: in `mergeFolder`, after the write, walk the remote's parent chain with one CTE bounded by `maxFolderDepth`; if it reaches the row itself, store `parent_id = NULL` and `requeueRow` so the space converges on the break. Probe: seed `X`, `Y`; `mergeFolder(X, parentId: 'Y')` then `mergeFolder(Y, parentId: 'X')` at newer stamps; assert `getFoldersByParent(null)` contains neither. Fix session: A7. → A7: fixed `lib/database/daos/folder_dao.dart:808,841` — `mergeFolder` calls a new `_repairMergedParent`, which walks the remote's parent chain with one CTE bounded by `maxFolderDepth` and cuts a closed cycle to the root, stamped locally and queued. Test `the parent a merge leaves behind a remote move that closes a cycle is cut to the root`, verified failing pre-fix (`Expected: null / Actual: '6a9936c3-…'`, 3 of 5 cases red). Two residuals the fix review found, both fixed in the same session: the repair ran during the bind's initial merge and pushed a flattening move (R130), and it minted **below** the remote move it repairs now that R65 moved the clock advance to the page (R131).
- **R64** (M, PLAUSIBLE; A3a) `lib/database/daos/folder_dao.dart:752` — a live child folder under a remotely-tombstoned parent is reachable from nowhere, and §8 covers only the note case. Input: device A deletes folder P (the local cascade tombstones and queues each descendant, readiness R3) while device B creates child C under P at a newer stamp; the merge never cascades (§3.4 (4)), so B keeps C live with `parent_id = P` while P is a tombstone. C never appears at the root (`parentId IS NULL`) and never under P (filtered out of every live list), so C and its notes are findable only by search. §8 accepts "a live note whose folder arrived as a tombstone shows that folder's id as its name"; a live *folder* under a tombstoned parent is not recorded and is worse — nothing shows it at all. Fix: when a live row's parent is locally tombstoned, re-parent to `FolderRepository.nearestLiveFolderId(parentId)` (`folder_repository.dart:68`) and `requeueRow`. Fix session: A7. → A7: fixed `lib/database/daos/folder_dao.dart:841` — a live row whose parent is locally tombstoned takes `nearestLiveFolderId` and is requeued; a local repair, never a cascade. Test `a live row under a tombstoned parent takes the nearest live ancestor`, verified failing pre-fix (`Expected: '16cbf5cb-…' / Actual: '5ac703a8-…'`).
- **R65** (M, PLAUSIBLE; A3a) `lib/database/crdt/crdt_merge.dart:58` — the clock advance is not transactional, so a local write can out-stamp a remote row this device never merged. `db.hlc.update(...)` mutates the in-memory `HybridLogicalClock`, while the puller runs a whole page inside one `db.transaction` (`sync_puller.dart:232`) and deliberately rolls the page back when a conflict copy fails (`:210-213`). Input: a page carrying a remote note at T2 rolls back; the user edits that note before the next run; the edit mints T3 > T2 (the clock is already at T2) and pushes. The remote row at T2 then loses to T3 on every device without ever having been merged here, so the other device's text is replaced with no conflict copy — the one outcome §3.9 exists to prevent. Narrow: the page is retried on the next run, so the window is between the rollback and the retry. Fix: return the remote stamp from `mergeRemoteRow` and let the puller call `db.hlc.update` once after the page commits, or re-seed from `syncOutboxDao.maxHlc()` when a page rolls back. Fix session: A7. → A7: fixed `lib/database/crdt/crdt_merge.dart:81` + `lib/services/sync/sync_puller.dart:296,339` — the advance is out of `mergeRemoteRow` and re-homed as `CrdtMerge.advanceClock`, which the puller calls once with the page's highest merged stamp **after** the page transaction commits. Test `a rolled-back page leaves the clock where it was, and the retry moves it`, verified failing pre-fix (`Expected: '01a16cec7c09:0000:A' / Actual: '01a16cec7c0a:0000:A'`). The fix review checked every caller: `mergeRemote` has exactly one in `lib/` (the puller); the restore and the bind go through `CrdtWrite`, so none lost the advance. Two residuals, both fixed in the same session: `persistClock()` had moved outside the transaction with it (R132), and `mergeChunk` still advances in its own (R145, documented — it has no caller). Phase record §3.4 (1) now states the per-page rule.
- **R66** (L, PLAUSIBLE; A3a) `lib/services/sync/tables/counters_binding.dart:50` (+ `:95-98`), `folders_binding.dart:50`, `notes_binding.dart:56` — encode normalises a value this build does not know instead of passing it through: `_scopeOf(row.scope)` rewrites an unrecognised `scope` to `'global'`, and `ItemLabel.fromStorage(row.label).storageName` rewrites an unrecognised `label` int to `'none'` (`item_label.dart:58-62`). The S2b block states the opposite rule for the alert bindings ("so a mode this build does not know crosses unchanged"). Latent today: §3.5's `schema >= stored` rule pauses an older device before it can push. Fix: encode the stored value verbatim when this build does not recognise it, keeping the lenient read on decode. Fix session: A7. → A7: **partially fixed** `lib/services/sync/tables/counters_binding.dart:53` — a `scope` string this build does not recognise is encoded as stored. Test `counters a scope this build does not know crosses verbatim`. The **`label` half is declined**: the wire carries the label's *name* for backup parity while the column stores an index, so an index this build cannot name has no verbatim form, and crossing the index instead would be a v43 wire change. Residual R135: the comment claimed more than the change delivers (decode still normalises); corrected in the same session.
- **R67** (L, PLAUSIBLE; A3a) `lib/database/daos/folder_dao.dart:767-776`, `note_dao.dart:1001-1011`, `counter_dao.dart:516-529`, `vocabulary_dao.dart:356-369` and `:396-409` — the tombstone branches never write `updated_at`, so the deleting device holds `updated_at = <delete time>` (`note_dao.dart:428`) while every merging device keeps `<last edit time>`. A tombstone carries no `data`, so the column is not on the wire and the two never converge unless the row resurrects. Invisible today — nothing shows a tombstone's `updated_at` — and §3.4 (4) lists only `is_deleted`, `deleted_at` and the stamps, so this is a silent divergence rather than a contract breach. Fix: write `updatedAt: Value(remote.deletedAt)` in the five tombstone branches (never `remote.updatedAt` — for a data-less tombstone that decodes to epoch 0), or say in §3.4 that `updated_at` is undefined on a tombstone. Fix session: A7. → A7: **partially fixed** `folder_dao.dart:789`, `note_dao.dart:1011` and both `vocabulary_dao.dart` branches — `updatedAt: CrdtMerge.tombstoneUpdatedAt(remote.deletedAt)`, never `remote.updatedAt`. Test `a merged tombstone dates updated_at at the delete` (pre-fix `Expected: 2026-01-04 / Actual: 2026-10-27`). **`counter_dao.dart` is excluded**: `counters` and `counter_values` have no `updated_at` column at all, so there is nothing to write and adding one would be a migration — `declined: needs v44, owner`, if the owner ever wants the column.
- **R68** (L, PLAUSIBLE; A3a) `lib/services/sync/sync_table_binding.dart:111-116` — a tombstone's `deleted_at` is reconstructed from the HLC wall time, which the forward-only seed honours however far ahead it is (`hlc.dart:87-94`), so a stamp minted by a device whose clock ran ahead gives every merging device a `deleted_at` in the future where the deleting device stored `DateTime.now()`. Fix: nothing, unless a surface starts showing a tombstone's `deleted_at` — then carry `deletedAtMs` inside the tombstone's `data` (`firestore.rules:205`'s `hasOnly` list already allows a `data` map, so no rules change). Fix session: A7. → A7: **no change needed** — the id's own fix is "nothing, unless a surface starts showing a tombstone's `deleted_at`", and `grep deletedAt lib/pages lib/widgets lib/bloc` returns nothing. Recorded for the day one does.
- **R69** (L, PLAUSIBLE; A3a) `lib/database/crdt/crdt_merge.dart:58` — the remote stamp is parsed only after the row is written. The rules validate it by size alone (`firestore.rules:207`), so a document whose `hlc` is not `wall:counter:node` hex does the insert or the overwrite first and then throws from `HlcTimestamp.parse`. The DAO transaction rolls back and `sync_puller.dart:246-255` parks the envelope, so nothing is half-written — but the write is paid for nothing and the park message is a bare `FormatException: Invalid HLC timestamp` with no table or row key. Fix: parse `remoteHlc` on the first line of `mergeRemoteRow` and raise a `FormatException` naming `table.actualTableName` and `rowKey`. Fix session: A7. → A7: fixed `lib/database/crdt/crdt_merge.dart:46-56` — the remote stamp is parsed on the first lines, before any write, and the `FormatException` now reads `<table>: "<rowKey>" carries <reason>`. Covered by the merge-contract suite, which drives every branch through the parse.
- **R70** (L, PLAUSIBLE; A3a) `lib/services/sync/tables/notes_binding.dart:53,70` + `lib/database/daos/note_dao.dart:1019-1029` — `preview` crosses, is strictly required, and is then discarded: `_withBody` recomputes it from the body, so a live document missing `preview` parks for a column the merge never reads. Consistent with §3.4 (8) ("every v43 column stays strict"), hence L. Fix: read it as `f.nullable<String>(JsonKeys.preview) ?? ''`, keeping it in `encode` for backup-format parity. Fix session: A7. → A7: fixed `lib/services/sync/tables/notes_binding.dart:72` — `preview` is read leniently and still encoded, for backup-format parity. Test `notes a live envelope without a preview still decodes`. It is the first lenient v43 column; phase record §3.4 (8) now names it as the exception to "every v43 column stays strict".
- **R71** (L, PLAUSIBLE; A3a) `lib/database/daos/folder_dao.dart:155-170` and `note_dao.dart:178-194` — concurrent creates in one folder give two rows the same `position`: both compute `maxPos + 1` locally, `position` travels (`folders_binding.dart:45`, `notes_binding.dart:58`) and the merge stores it verbatim. §8 accepts the *title* collision of exactly this scenario; the position collision is not recorded, and a drag on one device renumbers rows the other renumbers differently, so the order flaps until someone reorders the folder. Fix: record it in §8 beside the title collision, or break position ties by `hlc_timestamp` in the browser's sort. Fix session: A6. → A6: fixed — the phase record §8 bullet now records the position collision beside the accepted title collision, and says the fix, if it is ever wanted, is an `hlc_timestamp` tiebreaker in the browser's sort, never a merge-side renumber.
- **R72** (L, CONFIRMED; A3a) `test/database/crdt_write_guard_test.dart:122-156` — the outbox fence does not see `db.syncOutboxDao.<method>`, so the must-not-change rule it pins ("the outbox written only inside `CrdtWrite`") is not enforced for `ackThrough`, `requeueRow` or `clear`. The patterns are `\bsyncOutbox\b`, `SyncOutboxCompanion`, `$SyncOutboxTable` and `sync_outbox` (case-insensitive); `syncOutboxDao` matches none — `\bsyncOutbox\b` needs a non-word character after `syncOutbox` and finds `D`, and the camel-case identifier has no underscore for `sync_outbox`. So `crdt_merge.dart:50,55`, `sync_puller.dart:320` and `sync_pusher.dart:135,270` all mutate the queue while absent from the rights map (`:26-40` lists none of the three), and `flutter test test/database/crdt_write_guard_test.dart` is green at +4. A future slice could call `syncOutboxDao.clear()` — which drops the whole queue — from anywhere and no gate would notice. Fix: add `RegExp(r'\bsyncOutboxDao\b')` to `names` and give `crdt_merge.dart`, `sync_puller.dart` and `sync_pusher.dart` a new `_May.outboxRetire` right that allows the retire/re-seed methods and forbids row inserts. Fix session: A7. → A7: fixed `test/database/crdt_write_guard_test.dart` — `\bsyncOutboxDao\b` added to `names`, and a new `_May.outboxRetire` right granted to the seven files that call the DAO (R72 named three; `sync_engine`, `sync_binding_service`, `sync_status_service` and `backup_service` already call it and would otherwise have gone red). The right allows only the retire, re-seed and read methods; the table, the companion and the raw name stay banned, so a row insert from those files is still impossible. Residual R138: the regex's alias alternative let an allow-listed file call anything through a local; closed in the same session.
- **R73** (L, CONFIRMED; A3a) `test/services/sync/sync_codec_test.dart` — nothing pins the lenient decode of an unknown key, the forward-compatibility property §3.4 (8) depends on (a strict decode here bricks every old install the day a column is added). `WireFields` reads only named keys, so an extra key is ignored, but the 48-case suite has no extra-key case (its only forward-compat case is "a live day row whose dayMs names another day is refused", `:998`). Fix: one case per binding family — `expect(binding.decode(carrying({...live, 'futureColumn': 1})), binding.decode(carrying(live)))`. Fix session: A7. → A7: fixed `test/services/sync/sync_codec_test.dart` — an unknown-key equality in `expectStrict` (the nine browser sites) and a `a key this build does not know is ignored` case in `calendarTable` (the eleven calendar tables).
- **R74** (L, CONFIRMED; A3a) `test/database/support/merge_contract.dart:272-302` — the `keptLocal` and `unchanged` branches are never checked for the clock advance that §3.4 and the `mergeRemoteRow` doc both promise for "every branch". The three clock cases cover `inserted`, `applied`, and "a merge moves the clock only through the remote stamp" (which asserts the clock does *not* move for an older remote). The code satisfies the contract because `crdt_merge.dart:58` sits after the if/else — a refactor that moved `hlc.update` into the branches would still pass. Fix: one case that re-merges the seeded row's own stamp (`MergeResult.unchanged`) and asserts `expectClockAt` on that stamp. Fix session: A7. → A7: fixed `test/database/support/merge_contract.dart` — **built wider than the id asks.** R65 removes the advance from the merge, so the per-branch property is now pinned in the negative for all four branches plus the floor branch ("no branch moves the clock"), and the advance itself is pinned in `sync_engine_test.dart`. A refactor that moved an advance back into a branch is caught either way.
- **R75** (L, CONFIRMED; A3a) `test/services/sync/sync_tables_test.dart:73` — the registry test pins the counter-value key only for a per-note value (`'c1|note-1'`), never for the global `'c1|'`. That test is the one place `rowKeyOf` is compared against `rowKeySql` *through SQLite* (`counter_id || '|' || note_id`), which is where an empty `note_id` is most likely to drift from the Dart helper, and the global convention is on both must-not-change lists. The behaviour is covered by the codec suite (`sync_codec_test.dart:417-432`, `:460-476`); the SQL-vs-Dart comparison is not. Fix: run the per-binding case for both `'c1|note-1'` and `'c1|'`. Fix session: A7. → A7: fixed `test/services/sync/sync_tables_test.dart:68` — the per-binding SQL-vs-Dart case runs over both `'c1|note-1'` and the global `'c1|'`.

**The A3a column matrix.** `env` = carried on the `SyncEnvelope`, not in
`data`. Every `*Ms` key is `millisecondsSinceEpoch` on encode and
`DateTime.fromMillisecondsSinceEpoch` on decode (`WireFields.fieldMs`,
`sync_table_binding.dart:172`); the project declares no
`DriftDatabaseOptions`, so every `DateTimeColumn` is unix seconds and the
round trip is exact. `deletedAt` is never on the wire for any table — it is
derived from the HLC wall time (deliberate; R68). The env group is
`hlc`, `deviceId`, `version`, `isDeleted` (as `op`) and `ownerId` for every
table that has a binding.

| table | travels in `data` | derived on decode, not on the wire | deliberately local |
| --- | --- | --- | --- |
| `folders` | `id`, `name` (tombstone default = `rowKey`), `parentId`, `position`, `label` (as a name; R66), `createdAtMs`, `updatedAtMs`, `noteSortOrder`, `subfolderSortOrder` | — | — |
| `notes` | `id`, `folderId`, `title`, `preview` (then overwritten; R70), `position`, `label`, `createdAtMs`, `updatedAtMs`, the body as `content` (chunks joined, D14) | `contentLength`, `chunkCount`, `isCompressed` — the same derivation as `NoteStorageService.createNote:155` | — |
| `content_chunks` | nothing — `travelsWithParent`, rebuilt by `replaceChunks` | `id`, `noteId`, `chunkIndex`, `content`, `isCompressed`; the CRDT fields from the winning note | `ownerId` (no writer anywhere; parity only) |
| `counters` | `id`, `name`, `startValue`, `step`, `scope` (normalised; R66), `position`, `isPinned`, `createdAtMs` (the ISO `createdAt` removed, S2a F7) | — | — |
| `counter_values` | `counterId`, `noteId` (`''` = global), `value`, `position`, `isPinned` | `counterId` and `noteId` are also re-read from the row key and `expectSame`d | — |
| `vocabularies` | `id`, `name`, `isEnabled` (tombstone default `true`), `sortOrder`, `createdAtMs`, `updatedAtMs` | — | the nested `items` of `exportData` (items are their own rows) |
| `vocabulary_items` | `id`, `vocabularyId` (added over the backup's nesting), `term`, `sortOrder`, `createdAtMs`, `updatedAtMs` | — | — |

`counters` and `counter_values` have no `updatedAt` column, so none is
missing. `_keyOf` splits the counter-value key at the first `|` and the
reconstruction is identically the key, so the document id always
reproduces and no `dayKeyOf`-style re-check is needed.

**A3b (the wire and the merge: the eleven calendar tables and the hooks) — 1
H, 2 M, 8 L.** Every column of the eleven calendar tables is accounted for —
the matrix at the end of this block is the record of that, and no column was
left unclassified. The wire itself holds: each binding's map **equals** its
service's real `exportData` entry, pinned per table by
`expect(envelope.data, await exported())` (`sync_codec_test.dart:627`, green
for all eleven), and the event row's whole shape travels both ways —
recurrence (`ruleKind` + `rulePayload`), until (`endDateMs`), count
(`countOccurrences`), style (`countStyle`), `retroactive`, `priority`,
`allDay`, `startMinute` / `durationMinutes`, description scope
(`perOccurrenceDescriptions` + `description`) and the presence fields
(`tracksPresence`, `assumeAbsent`, `assumeAbsentFromMs`, `showInDayRail`).
The alert bindings pass `mode` and `sound` as raw columns, so a mode this
build does not know crosses unchanged — the rule A3a's R66 found broken for
`scope` and `label` is kept here. The lead re-read R76, R78 and R84 against
the code before writing them.
**Q2 — the day keys reproduce byte for byte.** `dayRowKey`
(`crdt_write.dart:46`) is the event id, a `|`, and
`day.millisecondsSinceEpoch ~/ 1000 * 1000`; `dayKeyOf`
(`sync_table_binding.dart:189-205`) splits at the **last** `|` and refuses
unless `dayRowKey` reproduces the key exactly, so only canonical digits pass
(`sync_codec_test.dart:1042` refuses a leading zero, a leading `+` and an
off-by-one ms). The SQL twin `event_id || '|' || (day * 1000)`
(`synced_tables.dart:30`) agrees because there is no `DriftDatabaseOptions`
anywhere in the tree, so a `DateTimeColumn` is unix seconds — which matters
because `requeueRow` matches rows by that SQL expression. **DST does not
bite**: days are normalised through the epoch by three identical
`_dateOnlyUtc` helpers, never `midnight.add(Duration)`, and the codec test
pins the EU spring-forward day `DateTime.utc(2026, 3, 29)` for all three day
tables (`:795-796`). The one gap is R79.
**Q3 — an orphan child row is stored verbatim and shown by nothing.** The
three day DAOs' own docs say so ("stored even under an event tombstoned
here, the parent's tombstone being its own row") and `_byKey` never filters
tombstones, so an absent parent is simply an insert. Every reader is keyed by
a listed event — `EventSkips.isSkipped/daysFor`,
`EventPresence.isMissed/marksFor`,
`OccurrenceDescriptions.overrideFor/overridesFor`, consumed by
`DayBarsResolver`, `CellTintResolver`, the day rail, the agenda and the day
panel — and no facade has an aggregate reader, so an orphan is inert on every
surface. It resolves itself when the parent arrives (pull order makes that the
same run) and persists for good when the parent was tombstoned here (R77,
R83).
**Q5 — alerts travel, registrations do not, and the digest semantics are
readiness D11 A.** `calendar_event_alerts` and `calendar_category_alerts`
travel; `alert_registrations` is absent from `syncedTables`
(`synced_tables.dart:48-66`) and rebuilt once per run by `_appReconcileAlerts`
→ `reconcileAll(AlertReconcileReason.sync)`, so a ring on both devices is
intended. **The record states no semantics for digests**; the reading the code
implements is D11 A again — `event_digests` carries no delivery state
(`event_digests_table.dart:23-44`; `EventDigest` has no `lastFiredAt`),
delivery lives only in the device-local registrations, so each device
delivers its own copy on its own cadence and the second device does not
re-deliver the first's. Same-device replay after a pull is safe too:
`DigestPlanner._fires` yields only instants strictly after `now`
(`digest_planner.dart:158-173`), so `reconcileAll(sync)` cannot re-fire
today's digest. The code matches; the record is silent — lead default (b).
**Q6 — the loaded calendar survives the reload.** Order is categories →
templates → events → occurrences → presence → skips → alerts → digests →
filter presets → overview views, each on its own guard, then
`notifyExternalChange()` (`app_sync_apply_hooks.dart:219-233`) — §3.5's
order, parents before children. `CalendarBloc._onExternalChange` names only
`allEvents`, `filters`, `membershipRevision` and `occurrenceRevision` in its
`copyWith`, so `focusedDay`, `selectedDay`, the mode (`format`) and
`selectionSource` survive, and the panel's stored mode, filters and
drill-down are its own `_load()`, which the reload does not re-run — the
slice-6a "picked since init" flags are untouched. `presenceRevision` is not
bumped, but `sameGridInputs` (`calendar_state.dart:117-124`) includes
`membershipRevision`, which is, so a merged presence mark does repaint — not
a finding. A run cut by a leave is covered: the engine calls
`notifyRun(pulled.touched)` after the drain (`sync_engine.dart:597`). **A
sub-sheet open during the reload does not crash**: the calendar sheets read
through the bloc and there is no unguarded `firstWhere` on an event id
anywhere in `lib/widgets/` or `lib/pages/`, so a sheet over a remotely
tombstoned event loses the row rather than throwing; the event editor open
over one resurrects it on save, deliberately
(`calendar_event_dao.dart:52-56`), with R77's consequence for its day rows.
**Q8 — nothing cascades on merge; confirmed.** `tombstoneEventCascade`
(`calendar_event_dao.dart:110-119`) and `tombstoneAll` (`:137-172`) cascade
locally under one shared stamp and queue every row they touch, while
`mergeRemoteEvent` (`:277-317`) touches the event row alone and the ten other
merges each touch one row — verified across the whole diff of the eleven DAOs,
with the eleven merge suites green (162 tests).
**No §7 decision came into question; the defaults stand.** Two lead
defaults, both reversible by editing the id: **(a)** R77 takes the
*record* option, not the code one — the merge does **not** learn to
re-tombstone a live child under a newer parent tombstone, because §3.4 (4)
("no cascade on a remote write") is on the phase record's §5 must-not-change
list; A7 writes the half-resurrection into §3.4 as stated behaviour instead.
**(b)** the digest semantics of Q5 are recorded, not coded: one sentence in
§3.4 or §3.5 saying digests follow readiness D11 A, assigned to A7 alongside
R77's sentence.

- **R76** (H, PLAUSIBLE; A3b) `lib/services/category_service.dart:86` (`_create` → `_seedBuiltIns`) with `lib/database/daos/calendar_category_dao.dart:63-102` (`seedMissing`, which queues every row it writes through `enqueueWrittenIn`) — the built-in category seed can overwrite the space's customised built-ins. `bind_floor` is **the clock at bind** (`sync_binding_service.dart:80-85`, lead-verified: "every stamp this device has minted is at or below it and every later one is above it"), so a seed that runs *after* the bind sits above the floor and the floor rule does not cover it. Input: a second device binds and `CategoryService.getInstance()` takes its first touch of the session before the space's `calendar_categories` row for a built-in has landed — the user opens the calendar in the seconds after tapping bind, the launch-restore stack reopens the calendar while `bind_merge_pending` is still set, or the initial run is **cut** mid-`calendar_categories` and `_appReloadCalendar` does the first touch itself (`app_sync_apply_hooks.dart:221`). `seedMissing` then inserts the default `gym`, `cardio`, … at a stamp above the floor and queues them; the space's older custom row loses, `mergeRemoteRow` returns `keptLocal` and `requeueRow` pushes the default — the other device's renamed, recoloured, re-iconed, re-ordered or archived built-in is overwritten in the space and then on that device too, with nothing to repair it (`name`, `colorValue`, `iconKey`, `sortOrder`, `isHidden` all lost). A live local row is safe: `DoUpdate(where: (old) => old.isDeleted)` writes nothing and the stamp-matched enqueue then queues nothing, as the DAO's own doc says — the defect needs the row to be **absent**. Fix: skip `_seedBuiltIns()` while `sync_metadata['bind_merge_pending']` is set and run it once from the hooks after the initial merge clears; the flag is never set for an unbound database, so §4's "no behaviour change for an unbound database" holds. Probe (snapshot only): in `calendar_categories_merge_test.dart`'s harness seed `gym` with a custom name at `h1`, write `bind_floor = h1`, build `CategoryService.forTesting(db)` (seeds at `h2 > h1`), then `mergeRemoteCategory(remote('gym', custom), floor: 'h1')` and assert the stored name — today it is the default and an outbox entry exists. Fix session: A7. → A7: fixed `lib/services/category_service.dart:146,188` — `_seedBuiltIns` stands back while `sync_metadata['bind_merge_pending']` is set and runs once from the hooks after the initial merge clears. Test `the seed against a space the first touch during a bind leaves the space its built-ins`, verified failing pre-fix (`Expected: 'Beast mode' / Actual: 'Gym'`). **The unbound guard is verified**: `bind_merge_pending` is written only in `SyncBindingService.bind` and deleted in `unbind` and `sync_puller.dart:130`, never set for an unbound database, and the test `a database that never syncs seeds on the first touch` pins that.
- **R77** (M, CONFIRMED; A3b — upgraded from PLAUSIBLE by A5's probe A5-9c: a `tombstoneAll` of `[e1]` on A against a later edit on B leaves `A: [e1:Later on B:false]` and `B: [e1:Later on B:false]`, the event resurrected on both devices) `lib/database/daos/calendar_event_dao.dart:110-119` (`tombstoneEventCascade`) and `:137-172` (`tombstoneAll`) against the deliberately cascade-free `mergeRemoteEvent` `:277-317` and its ten twins — a delete and a concurrent edit resurrect an event without its history. Input: device A taps "Delete all events" (or deletes one event) at stamp S; device B edits that event, or one of its day rows, above S, before either pulls. Per-row LWW resolves each of the five rows on its own: an edit to the **event** brings the event back on both devices while its presence marks, per-day descriptions, skips and alerts stay tombstoned everywhere — the event returns silently emptied and will never ring again; an edit to a **day row** leaves that row live under a tombstoned parent, the Q3 orphan, which nothing shows and every backup still carries (R83). The mechanism is intended — §3.4 (4) says "**no cascade** on a remote write: every descendant has its own envelope" and §5 names `tombstoneAll` must-not-change — but the half-resurrection is nowhere written down, and readiness D13 A promises only "the dialog copy stays true". Fix (lead default (a)): A7 states the outcome in §3.4 in one sentence; **not** a merge-side re-tombstone of a live child under a newer parent tombstone, which would break §3.4 (4) on the phase record's own must-not-change list. The owner flips this by writing the code option here. Fix session: A7. → A7: fixed **in the record, as lead default (a)** — phase record §3.4 (4) now states the half-resurrection as accepted behaviour: per-row LWW brings the edited row back while its descendants stay tombstoned everywhere, so an edited event returns without its presence marks, descriptions, skips or alerts and will never ring again, and an edited day row stays live under a tombstoned parent. No merge-side re-tombstone, which §3.4 (4) and phase record §5 forbid. The one case that *is* repaired is a live child **folder** under a tombstoned parent (R64), because nothing shows it at all.
- **R78** (M, PLAUSIBLE; A3b) `lib/services/sync/app_sync_apply_hooks.dart:236-239` (`_appReloadAlerts`) against `:219-233` (`_appReloadCalendar`, which ends with `CalendarEventService.notifyExternalChange()`) — an alerts-only pull reloads the caches but never reaches the open screen. The branch is live, lead-verified: `SyncPuller.notifyRun` (`sync_puller.dart:136-140`) adds `alerts` whenever `calendar` moved but never the reverse, so a `touched` of `{alerts}` alone takes the `else if` at `:144`. Input: the other device adds an alert to an event that already exists here, flips a category alert or edits a digest, while the calendar page or the Alerts hub is open. The two services reload and `EventAlerts._revision` bumps, but nothing dispatches `ExternalCalendarChange`, `CalendarBloc` emits nothing, and **no surface reads `EventAlerts.revision`** (lead-verified: the only hit in `lib/` is the `///` at `lib/constants/event_alerts.dart:95` promising a badge page would, "the way the calendar rebuilds on `EventSkips.revision`"). So the open page keeps the old badges and the hub the old rows while `_appReconcileAlerts` has already armed the new alert — the phone rings for something the screen does not show, until an unrelated event forces an emit. §3.5 describes one reload path that always ends in `notifyExternalChange()`, so this also deviates from the record. Fix: call `CalendarEventService.notifyExternalChange()` at the end of `_appReloadAlerts` too. Fix session: A7. → A7: fixed `lib/services/sync/app_sync_apply_hooks.dart:269` — `_appReloadAlerts` ends with `CalendarEventService.notifyExternalChange()`, as `_appReloadCalendar` does. Test `an alerts-only pull tells the open calendar too, through the real reload (R78, R85)`, verified failing pre-fix (`Expected: <1> / Actual: <0>`).
- **R79** (L, PLAUSIBLE; A3b) `lib/services/sync/sync_table_binding.dart:189-205` (`dayKeyOf`) with `event_skip_dao.dart:293`, `event_absence_dao.dart:320`, `event_occurrence_dao.dart:290` — `dayKeyOf` accepts any whole second, and the merge is the only writer that does not normalise `day` to UTC midnight. Every other writer goes through `_dateOnlyUtc`, including the backup import (`event_skip_service.dart:216-220`, helper `:256-262`); the three merges write `day` straight from the key. Input: an envelope keyed `e1|<any whole second>` that is not a day boundary. A second primary-key row for the same calendar day appears; the facades are keyed by the normalised day (`Map<DateTime, PresenceStatus>`, `Map<DateTime, String>`), so one row wins and *which* depends on row order — a presence mark or a day description that flips between pulls. Not reachable from today's builds, since every local writer normalises, hence L. Fix: in `dayKeyOf`, require `ms % Duration.millisecondsPerDay == 0`, not only the whole-second round trip. Same family on the push side: `encode` writes `'dayMs': row.day.millisecondsSinceEpoch` untruncated (`calendar_event_skips_binding.dart:44` and the two twins) while `rowKeyOf` truncates with `~/ 1000 * 1000`, so a row carrying sub-second ms would push an envelope the receiver parks on `expectSame('dayMs', …)` — unreachable while Drift stores seconds, but the key and the field should come from one expression. Fix session: A7. → A7: fixed `lib/services/sync/sync_table_binding.dart:213` (a day key must be a UTC midnight) and `lib/database/crdt/crdt_write.dart:51` + the three day bindings (`dayMs`, so the key and the field come from one expression). Test `row keys dayKeyOf refuses a key dayRowKey could not have written`. Residual R133: the tightening could park a legacy non-midnight row forever; closed in the same session by normalising on the way out, in `encode` only. The lead probed a copy of the owner's export — `calendar_event_skips` 0 rows, `calendar_event_absences` 91 / **0** not at midnight, `calendar_event_occurrences` 5 / **0** — so the path is latent and no migration is needed.
- **R80** (L, PLAUSIBLE; A3b) `lib/services/category_service.dart:103` (`reload()` is `_load()` only) — a built-in category tombstone survives the whole session. The resurrection lives in `seedMissing`'s `DoUpdate(where: (old) => old.isDeleted)` (`calendar_category_dao.dart:85-91`), which `reload()` never calls. Input: a tombstone for a built-in id merges — locally the delete is refused (`calendar_category_dao.dart:228`: `existing.isBuiltIn || _builtInIds.contains(id)`) but §3.4 says built-ins "merge like any row", and the DAO's own doc already names a merge as a source. The built-in vanishes from the pickers and the filter surfaces for the rest of the session and events carrying it fall through to `other`'s colour; the next launch resurrects and re-pushes it. Worse on a device that had no row: the merge's insert path stores the tombstone's decoded defaults (`name: ''`, `colorValue: 0`, `iconKey: ''`) and the launch resurrection sets only `isBuiltIn`/`isDeleted`/the stamps, leaving a nameless, black built-in. Fix: have the hooks reload categories through a path that reseeds (`_appReloadCalendar` calling a `CategoryService.reloadWithSeed()`); refusing a built-in tombstone in `mergeRemoteCategory` instead would contradict §3.4 and is not the fix. Also under Q4, not findings: `isHidden` travels both ways (`calendar_categories_binding.dart:47` / `:66`) and is the archive flag, not the transient render filter; a custom category's `colorValue` and `iconKey` travel as non-nullable fields with tombstone defaults `0` and `''`; `isBuiltIn` travels as received, and while the backup import repairs a wrong `false` for a built-in id (`category_service.dart:449-452`) `decode` does not — not producible by today's builds. Fix session: A7. → A7: fixed `lib/services/category_service.dart:114` — **deviation:** `reload()` itself now seeds rather than a new `reloadWithSeed()`, because the hooks are another run's file and `_appReloadCalendar` already calls `reload()`. Test `a reload resurrects a built-in a merge tombstoned`, verified failing pre-fix (`Expected: false / Actual: <true>`). The fix review confirmed the unbound case: `reload()` has exactly one caller in `lib/`, the hooks, so a database that never syncs never reaches the extra seed, and `seedMissing`'s `DoUpdate(where: old.isDeleted)` plus the stamp-matched enqueue means a live row writes nothing and queues nothing.
- **R81** (L, PLAUSIBLE; A3b) `lib/database/daos/calendar_event_dao.dart:299-310` and the ten identical companions — the tombstone branch never writes `updated_at`, on all eleven tables, against the local delete at `:179-189` which does write `updatedAt: Value(now)`. Echoes A3a's R67 and takes the same fix; recorded separately because the eleven calendar DAOs are A7's file set. Materially milder here than in the browser: every calendar read filters tombstones and every `exportData` excludes them, so nothing user-visible diverges. Fix: `updatedAt: Value(remote.deletedAt!)` on the eleven tombstone branches — never `remote.updatedAt`, which decodes to epoch 0 for a data-less tombstone. Fix session: A7 (with R67). → A7: fixed — the eleven calendar DAO tombstone branches take `CrdtMerge.tombstoneUpdatedAt(remote.deletedAt)` with R67. Test `calendar_events_merge_test.dart` `a merged tombstone dates updated_at at the delete`, and R141 then moved the assertion into `merge_contract.dart` so all thirteen tables are held to it.
- **R82** (L, PLAUSIBLE; A3b) `lib/services/sync/sync_tables.dart:25-42` — the pull order puts `calendar_events` (index 2) before `notes` (index 12), while an event's `noteId` points at a note, so the `///` promise "a parent before its children" has an exception the comment does not name. Input: inside one run, a merged event's `noteId` names a note that has not arrived; the user taps "open linked note" mid-run. Transient — `afterRun` refreshes once everything landed. Fix: no code change; note the exception in the ordering comment. Fix session: A7. → A7: fixed `lib/services/sync/sync_tables.dart:25` — the ordering comment names the `calendar_events` (index 2) before `notes` (index 12) exception and why it is transient. Comment only, as the id asks.
- **R83** (L, PLAUSIBLE; A3b) `lib/services/event_skip_service.dart:180-193`, `event_presence_service.dart:183-196`, `event_occurrence_service.dart:188-201` — the three day tables' `exportData` reads `_dao.getActive()` unfiltered, so it does not filter to live events. Echoes the S2a review's F6 for counters. Input: an orphan day row created by R77 reaches the backup and is restored (normalised, inert). Dead weight in the archive rather than a visible defect. Fix: filter to live event ids the way `CounterService.exportData` now does, or state in the record that the calendar deliberately does not. Fix session: A7 (`→ deferred` is fine under D4 A if A7 touches none of the three services). → A7: **deferred under D4 A** — the fix sits in `event_skip_service.dart`, `event_presence_service.dart` and `event_occurrence_service.dart`, and no H or M fix of this session opened any of the three. The id's own text allows it. Intended fix when it lands: filter `exportData` to live event ids the way `CounterService.exportData` now does, or state in the record that the calendar deliberately does not.
- **R84** (L, CONFIRMED; A3b) `test/services/sync/sync_codec_test.dart:608-678` — the eleven calendar tables are not held to the fourth `WireFields` strictness property. The shared `calendarTable` helper takes no `idKey` and pins three properties (required key missing → refused, required key mistyped → refused, empty `data` → refused); `expectStrict` (`:92-132`), which pins the fourth through `idKey`, is called at nine sites and all nine are browser tables (`:207`, `:291`, `:301`, `:368`, `:374`, `:451`, `:452`, `:527`, `:594` — lead-verified by grep). So `expectSame('id', …)` in eight bindings and `expectSame('eventId'/'dayMs', …)` in the three day bindings are unpinned, and the S2b review's F3 class of defect — a row stored under a key other than its envelope's — could come back unnoticed; the `row keys` group (`:1023-1105`) covers malformed *keys*, not disagreeing *data*. Fix: give `calendarTable` an `idKey` parameter and add the mismatch expectation, or route the eleven through `expectStrict`. Fix session: A7. → A7: fixed `test/services/sync/sync_codec_test.dart` — `calendarTable` takes a `mismatched` argument and adds `a live envelope naming another row is refused`; the three day tables pass both `eventId` and `dayMs`, so all eleven calendar tables are now held to the fourth `WireFields` strictness property.
- **R85** (L, CONFIRMED; A3b) `test/services/sync/app_sync_apply_hooks_test.dart:46-56` — `_appReloadCalendar` and `_appReloadAlerts` are never exercised: the test replaces every target with a recorder, so it proves only the dispatch order (`['calendar', 'reconcile']`, `['alerts', 'reconcile']`). The ten-service order inside `_appReloadCalendar` and the missing `notifyExternalChange()` in `_appReloadAlerts` are untested, which is why R78 survived the slice review. Fix: one test driving the real statics against in-memory services, or at minimum one asserting that the alerts path signals. Fix session: A7 (with R78). → A7: fixed `test/services/sync/app_sync_apply_hooks_test.dart` — R78's test drives the real `_appReloadAlerts` static against in-memory services instead of a recorder; the recorders stay for the dispatch-order cases.
- **R86** (L, PLAUSIBLE; A3b) `lib/services/sync/app_sync_apply_hooks.dart:225` — `calendar_events` is read twice after every calendar pull: the hook calls `CalendarEventService.reload()`, then `:232`'s signal makes `CalendarBloc._resolveAndReload` call `service.reload()` again (its `if (!resolved.freshlyLoaded) await service.reload();`). One extra `getAll()` per pull that moved calendar rows. Quality only. Fix: let the bloc skip the reload when the signal came from the hooks, or drop the hook's own `events` entry. Fix session: A7. → A7: **declined.** Both branches the id names regress. Dropping the hook's `events` reload: `AlertScheduler.reconcileAll` reads `CalendarEventService.getInstance()` (`alert_scheduler.dart:1049`) in the same `afterRun`, and with no calendar bloc mounted nothing else reloads the cache, so alerts would be armed off a stale event list. Letting the bloc skip on the signal: `backup_service.dart:366` fires the same signal **without** a prior reload, so a restore would paint a half-stale store. A safe fix needs a "store already fresh" flag on `notifyExternalChange` + `CalendarBloc._onExternalChange` — new public signalling API, for a Low the id itself marks "quality only".

**The A3b column matrix.** `env` = carried on the `SyncEnvelope`, not in
`data`: `hlcTimestamp`, `deviceId`, `version`, `op` → `isDeleted`,
`deletedAt` (from the stamp's wall time) and `ownerId`, on all eleven. `(K)` =
the column is also read back from the row key and `expectSame`d on decode.
Nothing is unaccounted for.

| table | travels in `data` | from the row key | deliberately local |
| --- | --- | --- | --- |
| `calendar_events` | `id` (K), `title`, `category`, `startDateMs`, `allDay`, `iconKey`, `ruleKind`, `rulePayload`, `endDateMs`, `startMinute`, `durationMinutes`, `description`, `noteId`, `colorValue`, `tintIcon`, `priority`, `retroactive`, `countOccurrences`, `countStyle`, `tracksPresence`, `perOccurrenceDescriptions`, `showInDayRail`, `assumeAbsent`, `assumeAbsentFromMs`, `removeAfterAlert`, `categoryAlerts`, `createdAtMs`, `updatedAtMs` (28) | `id` | — |
| `calendar_categories` | `id` (K), `name`, `colorValue`, `iconKey`, `sortOrder`, `isBuiltIn`, `isHidden`, `createdAtMs`, `updatedAtMs` | `id` | — |
| `calendar_event_templates` | `id` (K), `name`, `category`, `sortOrder`, `ruleKind`, `rulePayload`, `startMinute`, `durationMinutes`, `description`, `iconKey`, `colorValue`, `tintIcon`, `priority`, `retroactive`, `countOccurrences`, `countStyle`, `tracksPresence`, `assumeAbsent`, `perOccurrenceDescriptions`, `createdAtMs`, `updatedAtMs` (21) | `id` | — |
| `calendar_event_occurrences` | `eventId` (K), `dayMs` (K), `description`, `createdAtMs`, `updatedAtMs` | `eventId` + `day`, read back through `dayKeyOf`; the `data` copies are only `expectSame`d | — |
| `calendar_event_absences` | `eventId` (K), `dayMs` (K), `status`, `createdAtMs`, `updatedAtMs` | the same | — |
| `calendar_event_skips` | `eventId` (K), `dayMs` (K), `createdAtMs`, `updatedAtMs` | the same | — |
| `calendar_event_alerts` | `id` (K), `eventId`, `mode`, `offsetMinutes`, `daysBefore`, `dayMinute`, `sound`, `enabled`, `createdAtMs`, `updatedAtMs` — raw columns under `EventAlertKeys`, so an unknown `mode` or `sound` crosses unchanged | `id` | — |
| `calendar_category_alerts` | `id` (K), `categoryId`, `mode`, `offsetMinutes`, `daysBefore`, `dayMinute`, `sound`, `enabled`, `createdAtMs`, `updatedAtMs` | `id` | — |
| `event_digests` | `id` (K), `name`, `payload` (verbatim blob), `enabled`, `sortOrder`, `createdAtMs`, `updatedAtMs` | `id` | no delivery state exists on the row — delivery is the device-local registrations (Q5) |
| `calendar_filter_presets` | `id` (K), `name`, `filters` (verbatim blob), `sortOrder`, `createdAtMs`, `updatedAtMs` | `id` | — |
| `overview_views` | `id` (K), `name`, `payload` (verbatim blob), `sortOrder`, `createdAtMs`, `updatedAtMs` | `id` | — |

`alert_registrations` is local by contract: the table is absent from
`syncedTables` (`synced_tables.dart:48-66`) and the record says so twice
(§3.4 (4) "device-local `alert_registrations` follow through
`reconcileAll(sync)`, not here"; readiness D11's refinement that
`alert_registrations` stays a hard delete). `public_holidays` and
`user_settings` are likewise not in `syncedTables` — settings travel through
`SettingsService` (§5), not a synced table. `updatedAt` travels on every live
row of all eleven and on no tombstone (R81).

- **R87** (M, CONFIRMED; A4) `lib/services/sync/firestore_sync_gateway.dart:193-219` — `createSpace` reports failure after the commit landed, and the drawn id dies with the call. Input: the bind picker (S4b-2) calls `createSpace`; the commit lands on the server but the reply is lost, or the server read-back at `:209` pushes the pair past `_guard`'s single 60 s budget. `_writeOnly` throwing maps to `offline`/`unknown` and the whole call fails, yet the space exists at the id drawn at `:196`, which the caller never learns; a retry draws a fresh id and creates a **second** space, the first orphaned in `listSpaces` and indistinguishable by name. The code comment at `:194` states the behaviour as intended, and the record prescribed the fix (S5b L4) — it was never built; the only `get` is the `createdAt` read-back *after* a success. Fix: on any failure of `_writeOnly`, do one `doc.get(Source.server)` of the drawn id with its own short timeout and return the space if it is there before rethrowing. Fix session: A8.
- **R88** (M, CONFIRMED; A4) `lib/services/sync/sync_engine.dart:658-667` — `_regainsAccess` lifts `noAccess` on a space whose schema is above ours (S5b L6, never built). Input: a device on schema 43 is paused `noAccess` (a transient pull denial, or a watch snapshot that said `exists: false`); another device has since pushed under schema 44; the user resumes the app or taps "Sync now". The method tests only `readSpace(...) == null`, the space reads fine, the pause lifts to `none`, and the run burns a full pull and a push the rules deny on `schema >= stored` before `_diagnose` finally sets `appOutdated` — repeated on every resume, because the lift is unconditional. Fix: after the read, `if (info.schema > _schema) { _pause = SyncPause.appOutdated; return false; }`. Fix session: A7 (engine file; the finding is A4's). → A7: fixed `lib/services/sync/sync_engine.dart:721` — `_regainsAccess` reads the space and refuses to lift when `info.schema > _schema`, setting `appOutdated`. Test `a space at a newer schema does not lift a noAccess pause`, verified failing pre-fix (`Expected: SyncRunSkip:<SyncRunSkip.noAccess> / Actual: <null>` — the pause lifted and the run burned a pull and a denied push). Noted, not changed: `_gate` tests `noAccess` before `appOutdated`, so the *same* run still reports `noAccess` and the next one names `appOutdated`; that is the fix the id prescribes.
- **R89** (M, CONFIRMED; A4) `tool/firebase/emulators.cmd:7`, `emulators.sh:7`, `rules_probe.ps1:20`, `test/firestore/rules_test.dart:17`, `dart_test.yaml:16` — the emulator tooling still runs as `demo-anta`, contradicting §3.8 as amended by S5b (S5b M2). Input: S6 starts the suite with `tool\firebase\emulators.cmd` and installs a QA build with `ANTA_QA_FIREBASE_EMULATOR=10.0.2.2`. On Android the native default app comes from the google-services plugin, so the app's project id is `alexs-note-tracking-app` while the emulator was started `--project demo-anta`; the app's Firestore and Auth traffic lands in a second project namespace, and §3.8/S5 review H2 records that whether the suite's rules load for that second id is unverified — so the device pass proves nothing about the rules. §3.8 also names a `-Project` parameter on the probe that does not exist (its `param()` block carries four ports and a timeout). The A4 probe run therefore judged the rules under `demo-anta`, not under the id the app will use. Fix: give each of the three tools a project argument defaulting to `alexs-note-tracking-app` (`-Project` on the probe, `%1`/`$1` on the wrappers) and raise `_project`/`_origin` in `rules_test.dart` to the same default. Fix session: A8. (The `demo-anta` branch inside `lib/` is R37, A1c's — not duplicated here.)
- **R90** (M, CONFIRMED; A4) `firestore.rules:191-197` vs `lib/services/sync/sync_tables.dart` — nothing pins the rules' `syncedTable()` list to `syncTables`. Input: a future slice adds an 18th binding without touching `firestore.rules`. The two lists match today (all 17 compared), but no test compares them and the rules are not deployed, so the drift is invisible until the day they are — at which point every push of the new table is denied, `_diagnose` sees a readable space at an equal schema, the bisect parks 20 rows and raises `_AccessLost(noAccess, recheckable: false)`, a hard pause until relaunch. `grep -rn "syncedTable" test/` returns only Drift column references; no test reads `firestore.rules` at all (lead-verified). Fix: a test that parses the `table in [...]` list out of `firestore.rules` and asserts set-equality with `[for (final b in syncTables) b.table]`. Fix session: A8.
- **R91** (M, CONFIRMED; A4) `test/firestore/rules_test.dart` (untouched by the sync diff), `dart_test.yaml:19-20` — `test/firestore` covers no Phase 02 rule and is skipped by default. `flutter test test/firestore` reports `All tests skipped.` and exit 0 (run in A4). The file is the Phase 01 pairs/invites suite; it holds not one case for `users/{owner}/spaces`. The only Phase 02 rules coverage is `tool/firebase/rules_probe.ps1`, which is outside the gate, is invoked by no wrapper or CI step, and is PowerShell with `taskkill.exe` and `Start-Process -NoNewWindow` — it cannot run on the `darwin` machine, and there is no `.sh` counterpart beside `emulators.sh`. Fix: port the probe's 20 cases into `rules_test.dart` under the existing `firestore-rules` tag (the unsigned-JWT + REST shape it already uses), and record that the probe is a Windows convenience, not the coverage. Fix session: A8.
- **R92** (L, CONFIRMED; A4) `lib/services/sync/firestore_sync_gateway.dart:132`, `:377-385` — a cursor the gateway cannot parse wedges that table's pull forever. Input: the `pull_cursor_<table>` row in `sync_metadata` holds a value `FirestoreSyncWire` did not write (a hand-edited or corrupted database, a future gateway swap). `decodeCursor` throws `FormatException` inside `_guard`, which has no branch for it, so it falls to `catch (error)` → `SyncGatewayFailure.unknown` → `_scheduleBackoff()`; the cursor is never cleared, every run of that table fails identically, forever, with no self-heal and no distinct status. (`bind`/`unbind` both call `_deletePullState()`, so the normal rebind path is clean — `sync_binding_service.dart:144,171`.) Fix: catch `FormatException` in `pullPage` and fall through to `after: null`, a full re-read the merge makes idempotent, rather than failing the run. Fix session: A8.
- **R93** (L, CONFIRMED; A4) `lib/services/sync/firestore_sync_gateway.dart:18`, `lib/services/firebase_auth_service.dart:33` — the emulator ports are compile-time constants (S5b M3, open as code). Input: a QA run on a machine where a stray `firebase emulators:start` (the six the S1 run left behind) holds 8080/9099. A guest's `10.0.2.2` is the host's loopback, so the app silently talks to an emulator of unknown project and unknown rules and the pass is meaningless, with no way to point it elsewhere short of a rebuild; the record parks the mitigation on an S6 procedure, leaving no code artefact against recurrence. Fix: read the two ports from `ANTA_QA_FIREBASE_FIRESTORE_PORT` / `ANTA_QA_FIREBASE_AUTH_PORT` defines, defaulting to 8080/9099. Fix session: A8.
- **R94** (L, CONFIRMED; A4) `firebase.firestore.json` (tracked), `dart_test.yaml:16-17`, `test/firestore/rules_test.dart:15,206-210` — the Phase 01 emulator config was never swept (S5b L10, half-built: §3.8 now names `firebase.emulators.json`, the files were not changed). Input: anyone following the instructions in `dart_test.yaml` or the suite's own `fail()` message. Two near-identical emulator configs are tracked — `firebase.emulators.json` (auth 9099, firestore 8080, UI 4000, `singleProjectMode`) and `firebase.firestore.json` (firestore 8080 only) — both naming `firestore.rules` and `firestore.indexes.json`, so they must be kept in step by hand, and every surviving instruction in the tree still names the retired one. Fix: delete `firebase.firestore.json` and point `dart_test.yaml` and the suite's doc comment and `fail()` message at `firebase.emulators.json`. Fix session: A8.
- **R95** (L, CONFIRMED; A4) `test/support/fake_sync_gateway.dart:205-224` vs `firestore.rules:180` — the fake does not model the rules' space-name constraint. Input: S4b-2's picker lets a user name a space `''` or paste 120 characters, and its sheet test runs against `FakeSyncGateway`. `validSpace()` requires `d.name.size() > 0 && d.name.size() <= 100`; the fake stores any string, so the test passes, production answers `permission-denied`, and the engine has no path for "the create was refused for its shape" — the picker shows a generic failure. §3.3's gateway contract never states the cap; it lives only in the S1 rules block. Fix: make the fake throw `permissionDenied` for a name outside 1..100, and state the cap in §3.3. Fix session: A8.
- **R96** (L, PLAUSIBLE; A4) `firestore.indexes.json:12` (`"fieldOverrides": []`), `lib/services/sync/tables/notes_binding.dart:52` — every synced field is auto-indexed twice, a note's whole body included. Input: a Spark-plan account syncing a database of long notes; `_Pusher.maxDocumentBytes` admits 900 KB of `data` JSON per row. Firestore maintains single-field indexes for every field and every subfield of a map by default, ascending and descending, so a 900 KB `data.content` costs roughly 1.8 MiB of index entries on top of the document — dead weight, since the only fields any query touches are `pushedAt` and `__name__`. On Spark's 1 GiB storage ceiling that is roughly a tripling of the footprint; it fails no write (the per-document ceilings are 8 MiB of index entries and 40,000 entries, both far off), it is purely cost. Fix: a `fieldOverrides` entry per synced collection group exempting `data` from single-field indexing, deployed alongside the rules. Fix session: A8. Needs a real project to measure — the emulator enforces neither indexes nor quotas.
- **R97** (L, PLAUSIBLE; A4) `lib/services/sync/firestore_sync_gateway.dart:93-102`, `:116`, `lib/services/sync/sync_pusher.dart:53-68`, `sync_engine.dart:755-769` — the space document takes one write per batch, over Firestore's per-document write rate. Input: the initial upload of a large database — `_Pusher.drain` loops until the outbox is empty, so 10,000 rows are 21 back-to-back transactions each merging the same space document, against a sustained single-document rate of about 1/s. With `maxAttempts: 1` the SDK does not retry a contention `ABORTED`, so the whole 499-row batch fails at once, maps to `unknown` and goes to the back-off — safe, but a first sync can crawl; and if the backend answers `resource-exhausted` instead, the engine escalates to a **one-hour** `quotaExhausted` pause for what was a one-second throttle, clearable early only by `syncNow()` or `onAppResumed()`. Fix: either raise `maxAttempts` for the push transaction so the SDK absorbs contention (gateway), or require two consecutive `resource-exhausted` answers before the hour-long pause (engine). Fix session: A8 — see lead default (e). Needs a real project to measure.

**The A4 contract read, and what came out clean.** The rules match the
gateway field for field: `FirestoreSyncWire.documentOf`
(`firestore_sync_gateway.dart:413-426`) writes exactly the eight keys
`validEnvelope()` allows in the types it requires, `op` is only
`upsert|tombstone`, `ownerId` is asserted `== space.ownerUid` before the
write (`:70-78`) and `isOwner()` makes `uid() == owner`;
`pushedAt`/`createdAt`/`touched.*`/`lastWriteAt` are all
`FieldValue.serverTimestamp()` → `request.time`; the size caps hold with
room (`hlc` 54 ≤ 80, `deviceId`/`createdBy` 36 ≤ 64); the space merge is
`set(merge: true)` with every timestamp a sentinel, so the mask is
`['lastWriter', 'schema']` and `createdAt` is untouched; the 17 names in
`syncedTable()` equal the 17 `SyncTableBinding.table` values with
`content_chunks` absent; and `git diff 25a5c94 HEAD -- firestore.rules`
removes only comment lines — every `pairs`/`invites` rule body is
byte-identical.

**S5b L9 is settled: `maxBatch` 499 is safe.** The current quotas page
carries no per-commit or per-transaction write-count row at all; what it
carries is 500 *field transformations per document* per commit, a 10 MiB
request and a 1 MiB document. The worst case is 499 row documents with one
transform each plus one space document with at most 18 transforms (17
`touched` keys + `lastWriteAt`) — nowhere near the per-document 500 — and
the binding limit is the 10 MiB request, which `_Pusher.maxBatchBytes`
(8 MiB) already cuts; the rules make no `get()`/`exists()` call, so the
20-access ceiling is never approached. The `maxBatch` doc comment's "the
space document takes the 500th write" is now a stale rationale, not a
constraint.

**`pullPage` needs no composite index and none is missing.** Both order
clauses are ascending and the second is `__name__`, which Firestore
appends with the direction of the last sorted field, so the automatic
single-field ascending index on `pushedAt` serves the query with or
without the `>=` range; `firestore.indexes.json` correctly carries only
the Phase 01 `pairs` index, and the plain-string `startAfter` component is
right for a collection (non-group) query with no `/` possible in a row
key. One precision point the cursor rests on:
`Timestamp.microsecondsSinceEpoch` truncates nanoseconds, harmless only
because Firestore itself truncates timestamps to the microsecond toward
the start of time — a nanosecond-precise backend would make `startAfter`
sort before every document of the page and spin `_pullTable`'s
`while (true)` forever.

**`watchSpace`: S5 H1's fix is complete.** `shouldForwardSnapshot`
(`:405-408`) drops cache and pending-write snapshots, and
`includeMetadataChanges: true` is what makes the server's first answer
arrive when it equals the cache; offline the stream is silent (no error,
no `exists: false`), `_signalOf` stays null, `_staleTables` falls back to
every table and the pause stays `none`; an error detaches and
`_scheduleSignalRetry`s, and the Firestore listener's later `onDone` is a
no-op because `_detachSignal` already cleared the subscription
(`sync_engine.dart:878-899`); re-subscription after `noAccess` lifts runs
`_recheckAccess` → `_gate` → `_regainsAccess` → `_attachSignal` (`:574`,
`:838`). **The error map** is as the record says, with
`failed-precondition` — what a missing index raises — falling to `unknown`
→ back-off: an endless silent retry, tolerable only because no index is
required, which is what makes R90's class of change the one that would
make it bite.

**The 60 s timeout runs toward re-push, never toward a premature ack**
(S5b L5 stands as a recorded risk, not a new id): `ackThrough` is reached
only after `pushBatch` returns normally (`sync_pusher.dart:261-275`), so
no batch the device believes failed is ever acked; a commit that lands
after the gateway gave up is re-pushed with the same `hlc` and a new
`pushedAt`, idempotent in content, the §3.4 repair covering the
stale-overwrite window. The plugin's `runTransaction(timeout: 30s)`
default is not a commit bound on Android (`TransactionStreamHandler.onListen`
applies it to `semaphore.tryAcquire`), so the gateway's 60 s `_guard` is
the only one. **The QA seam's persistence-off ordering is right**:
`FirestoreSyncGateway.configure` runs at `lib/core/di/injection.dart:159`
before `FirestorePairingGateway` is registered and before any
`FirebaseFirestore.instance` use, and `Settings.copyWith` is
`host ?? this.host` / `sslEnabled ?? this.sslEnabled`, so
`const Settings(persistenceEnabled: false)` does not clobber the emulator
host.

**The probe ran unattended.** `powershell -ExecutionPolicy Bypass -File
tool\firebase\rules_probe.ps1` → 20 judged cases all PASS, one INFO (a row
written alone under a missing space is allowed — the rules never check the
parent exists; the gateway always writes the space document in the same
batch), `0 case(s) failed`, **exit code 0**. `flutter test test/firestore`
→ `All tests skipped`, exit 0 (R91). Read-only in the tree:
`dart analyze lib` clean, `flutter test test/services/sync test/core/qa` →
283 passed. **The six S5b carry-overs** (question 10): M1 open = R37
(A1c's, not duplicated); M2 open = R89; M3 open = R93; L4 open = R87; L6
open = R88; L10 half-built = R94.

**A4's lettered defaults.** (a) S5b L9 is answered from the current public
quotas page rather than left open for an S6 one-drain device check — the
page no longer carries a per-commit write row at all, which is a stronger
answer than one successful drain. (b) The stale tracked
`firebase.firestore.json` is its own id (R94) rather than folded into L10,
because L10's record text is already satisfied and an A8 session working
from ledger lines alone would otherwise never touch the file. (c) R90 and
R91 are scored **M** rather than L despite being test-only: the rules are
the one surface with no local safety net and are not deployed, so drift
there is silent until it is live for every install at once. (d) R88 is
assigned to **A7** by §0.6's file rule (`sync_engine.dart`), though the
finding came out of an A4 gateway question — A7 runs before A8, so the
engine stays one session's to edit. (e) R97 is assigned to **A8** even
though the engine-side variant of its fix touches `sync_engine.dart`: A8
runs last, so either variant is safe there, and the gateway-side
`maxAttempts` change is the one the id is written around.

A4 found no H. Three claims rest on reading alone and are marked
PLAUSIBLE: the Spark index-storage cost (R96) and the per-document write
rate (R97) need a real project, not the emulator, which enforces neither;
and R89's core consequence — whether the emulator's rules load for a
second project id under `singleProjectMode` — is the device check S6 owes
and cannot be settled from this machine without a built QA APK.

**A5 (the scenarios across every module) — 1 H, 3 M, 5 L.** One Opus
`reviewer` (D3 A), sixteen probe cases in a `git archive HEAD` snapshot
mapped `subst T:` (`a5_probe_test.dart` 11 cases, `a5_probe2_test.dart` 5,
all green), the snapshot and the mapping removed and `git status --porcelain
lib test` empty afterwards. The engine's checkpoints hold: a suspension, a
sign-out, an account change, a `stop()`, a schema skew and a background leave
each halt a run at the page or batch boundary with the outbox intact, and
`owner_id` is never touched. What broke is at the seams no slice owned.

**Scenario by scenario.** (1) *Same note dirty on A and B* — driven for the
engine half: a conflict copy created inside the page transaction is pushed,
merged back as a plain insert and **never re-forked** over four rounds
(`copies filed: 1`, both devices end with the same two notes). The editor half
is not drivable (`sync_pair` has no widget tree) and is where R99 sits. The
documented residual stands: when A's edit was already pushed and B's newer one
arrives, no copy is filed and A's text is gone — plain LWW, which §3.9 covers
only while the editor is dirty. (2) *Database switch mid-pull* — driven for
the engine (`SyncRunSkip.stopped`, `folders=0`, every later `syncNow()` also
`stopped`): no row of the old database can land in the new one and the old
engine is dead. The leak runs the other way — R100, R101, R104, R105.
(3) *Backup restore mid-drain* — driven: a suspension raised while the batch
is being prepared gives `SyncRunSkip.suspended`, `pushes=0`, the space empty,
`pending=1`; the unbind-before-the-wipes and floor-after sequence at
`backup_service.dart:346-369` is correct by reading, and `_apply`'s last
suspension check has no await before `db.transaction`, so a pull cannot
interleave into a restore. The residual is a batch already handed to
`pushBatch` (R102). (4) *Sign-out, sign-in as another account* — driven:
`signedOut` then `accountMismatch`, `pushes=0`, space empty,
`owners=[<folder>:null]`, `pending=1`. Nothing goes under the wrong uid. Worth
writing down rather than filing: while the second account is signed in the
database keeps queueing its writes, and they go to the first account's space
when it returns — D5 as designed, recorded nowhere. (5) *Backgrounded
mid-transaction* — driven: the page merged whole and moved its cursor, the pull
stopped before the next one, and the leave's drain ran as a second run in mode
`drain` that pulled nothing and minted no stamp. No finding. (6) *Quota pause →
hourly retry → resume* — driven at the engine: no row pushed twice,
`ackThrough` right across the pause, a "Sync now" lifts the hold by design.
Forcing the quota answer onto `pushBatch` specifically was not possible
(`FakeSyncGateway.failNextWith` fires on the next call of any kind and the
start-up pull consumed it); `sync_engine_failures_test.dart:172,192` covers the
stored mark. No finding. (7) *Schema skew* — driven: `appOutdated`, outbox
intact. The stuck half is already **R45**. (8) *Clock* — driven, and the one H:
see R98. A device an hour ahead is handled, `maxDrift` being one hour, and its
stamps simply win. (9) *Delete against an edit* — driven four ways: a remote
delete beating an **unpushed** local edit does file a copy, so the tombstone
branch of `mergeNoteDocument:977-990` is sound; over an **already pushed** edit
it is plain LWW with no copy; and `tombstoneAll` against a later edit on B
resurrects the event on both devices, which is **R77** — now CONFIRMED.
(10) *Taps on both devices during a pull* — driven: two taps, two kept, both
devices converged, **no loss at all**. Third confirmation that the phase
record §8's accepted counter loss is stale (**R34**). (11) *Conflict copy in a
page that rolls back* — covered by `sync_engine_test.dart:333` and
`NoteRepository.createMergedCopy:700-718`: the copy reaches no `afterPage`, the
row is gone, nothing is cached or emitted. Sound.

**What the lead re-read.** R98's mechanism against the code:
`crdt_merge.dart:58` is `db.hlc.update(HlcTimestamp.parse(remoteHlc))` while
`overwrite` writes the remote stamp itself, and `hlc.dart:174-182` `_guard`
returns the *held* value only to the clock — so the clamp never reaches the
row. R100's premise: `resetDependencies()` (`injection.dart:310`) has no caller
anywhere in `lib/`, and `sync_engine.dart:335` is the only
`registerSwitchedHandler` in the app.

**A5's lettered defaults.** (a) R98 is filed although phase record §8 defers
"the held far-future remote" as left-as-found — the cross-module consequence,
one row permanently un-editable on every device, is not what §8 describes; the
owner strikes it to `—` if §8 is read as covering it. (b) R99 is **M**, not H:
no text is lost, a duplicate note is persisted and pushed. (c) R100 and R101
are two ids, not one — a wedged pull and a silent no-op have different fixes
and A6 may build one and defer the other. (d) R77, R45, R34, R88, R3, R5 and
R7 were **not** re-filed; A5's probes move R77's mark to CONFIRMED and confirm
R34 again, which the lead has done in place. (e) R98 names no single fix:
every option changes merge semantics or the HLC encoding, both on §4's
must-not-change list, so the id states the choice and leaves it to the owner —
the fix session takes it only with the owner's letter.

- **R98** (H, CONFIRMED; A5) `lib/database/crdt/crdt_merge.dart:58` with `lib/database/crdt/hlc.dart:174-182` — a remote stamp too far ahead is clamped for the **clock** but written **verbatim** onto the row, so every later local edit of that row mints below the row's own `hlc_timestamp`, loses the next merge, has its outbox entry retired by `ackThrough`, and is gone on every device with no park, no copy and no notice. Input: any device with a wrong system clock pushes a row at a wall time above `wall + maxDrift`; another device merges it (`clampedRemotes` ticks); the user then edits that row locally and syncs. Probe `A5-8b` in a snapshot: after the rename and three round trips, `A5-8b A: From the future / 01b8dac5b400:0000:C`, `A5-8b B: From the future / 01b8dac5b400:0000:C`, `outbox A=0 B=0 clampedA=1 clampedB=2` — "Renamed on A" is gone on both devices and nothing is queued to recover it; probe `A5-8` shows the mechanism (`row after the pull: … 01b8dac5b400:0000:C`, `after a local rename: … 01a16d236a85:0001:A`). The row is un-editable across the whole space until a device's wall clock passes the remote's. Fix: **needs the owner** (see default (e)) — store the clamped stamp when the remote is held (diverges from "stamps verbatim", §3.4), or let a local write that would mint below the row's own stamp raise the clock just past it; the cheap half alone is to surface `clampedRemotes > 0` where a user can see it. Fix session: A7. → A7: **deferred: owner.** A5's lead default (e) says this id names no single fix — every option changes merge semantics or the HLC encoding, both on §4's must-not-change list — and "the fix session takes it only with the owner's letter". No letter was left, so nothing was built. The three options stand as the id states them: store the clamped stamp when the remote is held, let a local write that would mint below the row's own stamp raise the clock just past it, or surface `clampedRemotes > 0` where a user can see it (the cheap half, and the only one that is not a semantics change — but §4 also says this review ships no visible change, so it is not a free pick either).
- **R99** (M, PLAUSIBLE; A5) `lib/pages/optimized_note_editor_page.dart:1350` against `lib/database/daos/note_dao.dart:977-990` and `lib/services/sync/app_sync_apply_hooks.dart:175` — one conflict on an open dirty note files **two** copies where record §3.9 and D3 promise one. The engine's loser rule fires exactly when the editor's does: `mergeNoteDocument` reports a loser when `localHadPendingPush && remote newer && above the floor && the texts differ`, and a dirty editor whose last autosave has not drained yet (the push debounce is 30 s, the autosave fires in seconds) satisfies all four — so `fileConflictCopy` writes copy #1 holding the **stored local text**, then the same page's `afterPage` calls `announceMerged`, `_adoptRemoteUpdate` takes the dirty branch and writes copy #2 holding the **arriving remote text**, and the next autosave puts the live text back on the note. Input: note N open and dirty on A, A's last autosave queued but not drained, B's newer body arrives in a pull. Result on both devices: N plus the wanted copy plus a copy of A's intermediate autosave, all pushed. No suite can see it: `test/widgets/optimized_note_editor_page_test.dart:3842` drives `mergeNoteDocument` directly and discards its `MergeOutcome`, and `sync_engine_test.dart` has no editor. Fix: suppress one — `_adoptRemoteUpdate` skips filing when the announced page already filed a copy for this note, or the hook skips the loser when the note is the open one. Fix session: A6. → A6: **declined (the editor branch) → deferred: A7.** The id offered two branches. The editor branch — `_adoptRemoteUpdate` skips filing when the page already filed a copy — **loses data**: the engine's copy holds the editor's *stored* body (`loserContent`, an intermediate autosave) while the editor's copy holds the **arriving remote** body, so suppressing the editor's filing leaves the remote text nowhere, overwritten by the live local text on the next autosave and pushed. The reviewer confirmed that reading and named the sound branch: **the hook skips the loser when the merged note is the one an editor holds dirty**, which leaves the row on the live local text and exactly one copy holding the arriving remote body — D3. That lands in `lib/services/sync/app_sync_apply_hooks.dart:175` (or the loser rule at `note_dao.dart:977-990`), which §0.6's by-file rule already sends to **A7**, and it needs the hook to learn the open note id — a new seam, not a small fix. Nothing of R99 is half-applied; the editor is untouched for it. R125 notes that R106's test deliberately asserts no copy *count* until A7 lands this. → A7: fixed `lib/services/sync/app_sync_apply_hooks.dart:200` + a new `lib/services/sync/open_note_registry.dart` + `lib/pages/optimized_note_editor_page.dart:326,1129,1920` — the hook stands back and the editor files the one copy, A6's sound branch. Test `one conflict on an open dirty note leaves exactly one copy: the engine stands back and the editor files the arriving text (A5 review R106, R99)`, verified failing pre-fix (`Expected: null / Actual: '40d79b8e-…' — the editor files this one`), plus `files nothing for a note an open editor holds unsaved` and `a copy is still filed for a note no editor holds` at the hook level. The seam is a static registry in `DrawerHostRegistry`'s shape, registered in `initState` and dropped in `dispose`; an unbound database never reaches it. **Residual R129, an H the fix review caught:** the hook asked at merge time and the page answered a different question at announcement time, so three branches — a pending title-only edit (§3.9 M6), a save landing in the window, a page going clean — dropped the losing body with no copy at all, worse than the double copy. Fixed in the same session by making the registry a **claim**, latched on the body being unsaved. Phase record §3.9 now carries the rule.
- **R100** (M, PLAUSIBLE; A5) `lib/services/sync/app_sync_apply_hooks.dart:63-65` with `lib/services/sync/sync_engine.dart:343-352` and `lib/core/di/injection.dart:64,66,80` — after a mid-session database switch a conflict copy on the **new** database throws and wedges the notes pull for good. `NoteRepository`, `FolderRepository` and `NoteStorageService` are plain `getIt.registerSingleton`s holding the `AppDatabase` opened at launch; nothing re-registers them (`resetDependencies()` has no caller in `lib/` — lead-verified — and `registerSwitchedHandler` is the engine's alone), while `AppDatabase._open` closes the previous database before `notifyDatabaseSwitched` fires `_rebuildAfterSwitch`. `fileConflictCopy` is deliberately unguarded, so `nearestLiveFolderId` / `noteTitleExistsInFolder` / `createMergedCopy` on the closed database throw out of the page transaction: the page rolls back, the cursor does not move, the next run meets the same envelope, and every run answers `failure = unknown` → back-off while the losing text is never filed. Input: the user picks another database on the Settings database page and dismisses the restart dialog, the new database is bound, and a pull brings a note conflict. Fix: re-register the three repository singletons from the switched handler, or put them on the `DatabaseLifecycle` reset contract. Fix session: A6. → A6: fixed `lib/core/di/injection.dart:61-110` + `lib/repositories/note_repository.dart:56-66` + `lib/repositories/folder_repository.dart:44-54`, test `test/services/sync/app_sync_apply_hooks_database_switch_test.dart` "files a conflict copy in the switched-to database", verified failing pre-fix (`Bad state: … connection was closed!` out of `noteTitleExistsInFolder`). **Seam:** `DatabaseLifecycle.registerSwitchedHandler` — already the engine's seam, so no new pattern — registered from `registerRepositorySingletons()`, calling a new `rebindDatabaseTo` that re-points `_db` and drops the caches. The instances are **not** replaced in `get_it`: `NoteStorageService`, `FolderStorageService`, `FolderSearchService`, `MixedReorderService`, `ImportExportService`, every mounted page and the hooks hold them and listen on their change streams, so a replacement would have left all of them on the closed database — R101 again. `NoteStorageService` needed no change (it holds no handle), and `app_sync_apply_hooks.dart` was not touched (A7 owns it). Residuals: nothing sequenced the rebind before the engine's own handler and its failure was swallowed — R113, fixed in this session by having the notice carry the database; and live `watch*` subscriptions are still bound to the closed handle — R114, deferred to A7.
- **R101** (M, PLAUSIBLE; A5) `lib/services/sync/app_sync_apply_hooks.dart:101-131,136-141` — the quiet half of R100: on a switched database every `announceMerged` / `invalidateAll` runs against the closed previous database, throws, and is swallowed by `_guard`, so merged notes and folders reach no browser list, no search index and no open editor, while the caches that *are* cleared belong to a database nobody reads. Input: as R100, with any merged row — no conflict needed. Record §3.5's "merged notes and folders reach the UI through the storage services' change events" and §3.9's open-editor rule both stop holding after a switch, silently: the rows are in the database but nothing on screen moves until a relaunch. Fix: as R100. Fix session: A6. → A6: fixed by the same change, test "announces a note merged into the switched-to database", verified failing pre-fix (`[AppSyncApplyHooks] note changes failed: … connection was closed!`, nothing announced). See R100 for the seam and the two residuals; R114 is the half this fix does not reach.
- **R102** (L, PLAUSIBLE; A5) `lib/services/backup_service.dart:346-352` with `lib/services/sync/sync_pusher.dart:259-266` — a batch already handed to `pushBatch` lands in the space after the restore began. `importFromJson` raises `SyncSuspension` and proceeds; it neither stops the engine nor awaits a run in flight, and the pusher's last `_checkHalt` is **before** the network call, not after it. Input: a drain whose `pushBatch` is in flight on a slow uplink when the user taps "Restore backup". Rows of the pre-restore database reach the space after the unbind, and the floor then makes the restored rows lose to them at the next bind — consistent with D15, not with D9's "can never interleave". Probe A5-3 confirms the checkpoint before the call does hold (`pushes=0`, `pending=1`); the residual needs a gateway seam that can suspend inside `pushBatch`, which `FakeSyncGateway` lacks. Fix: have the restore quiesce the engine singleton before the wipes, or re-check the suspension after `pushBatch` and treat the batch as unacknowledged. Fix session: A7. → A7: fixed `lib/services/sync/sync_pusher.dart:315` — the suspension is re-checked after `pushBatch` and the batch is treated as unacknowledged when a restore began inside the call, through a new `FakeSyncGateway.onPushBatch` seam. Test `a restore beginning during the push leaves the batch unacknowledged`, verified failing pre-fix (`Expected: <1> / Actual: <0>` outbox count).
- **R103** (L, CONFIRMED; A5) `test/services/sync/support/sync_pair.dart:214-241` — `SyncPair.snapshot` encodes each row through its binding and a tombstone encodes as `hlc tombstone null`, so **the convergence suite is blind to any divergence in a tombstoned row's columns**. Probe A5-9b: after `tombstoneAll` on A against an edit on B, `A: [e1:Leg day:true, e2:Leg day:true]` vs `B: [e1:From B:true, e2:Leg day:true]`, and `expectConverged()` passed. Harmless while nothing above the DAO reads a tombstone, but it is why R77's resurrection had to be probed by hand and why a merge writing the wrong columns on a delete would pass the gate. Fix: put the raw `hlc_timestamp`/`is_deleted`/`version` of every row into the snapshot string, or add a helper that compares tombstoned rows column by column. Fix session: A7. → A7: fixed `test/services/sync/support/sync_pair.dart:220,246` — a tombstone's snapshot string carries the stored row's columns instead of `hlc tombstone null`, with a new tail assertion in `a note deleted on A is tombstoned on B, its chunks too`. `ownerId`, `deviceId`, `version`, `deletedAt`, `updatedAt` and a note's `contentLength`/`chunkCount`/`isCompressed` stay **excluded**: with them in, two existing convergence cases went red on a by-design §3.4 (4) difference. The fix review (R141) called that out as leaving the suite blind to exactly the columns R67/R81 changed, so the `updated_at == deleted_at` assertion moved into `merge_contract.dart` instead, where all thirteen tables are held to it.
- **R104** (L, PLAUSIBLE; A5) `lib/services/sync/app_sync_apply_hooks.dart:183,266` — `fileConflictCopy` reaches a database singleton from **inside** a pulled page's transaction: `_strings()` → `SettingsService.getInstance()` → `AppDatabase.getInstance()` when the settings singleton was reset. Input: `DatabaseLifecycle.notifyDatabaseSwitching()` nulls `SettingsService._instance` while a page transaction is open and the page then files a copy. The memoised `_opening` returns the *new* database rather than reopening, so the copy's title is localised from the new database's settings while the write goes into the old one's transaction — wrong-but-harmless today, and a layering breach that bites the moment the memo changes. Fix: resolve the strings before the page transaction opens and pass them into the hook, or cache the locale per run. Fix session: A7. → A7: fixed `lib/services/sync/app_sync_apply_hooks.dart:91` — the copy's strings are resolved in `beforePage`, before the page transaction opens, and read from there. Test `resolves the copy's language before the page, never from inside its transaction (R104)`. Residual R139: the `??` fallback and `beforePage`'s `_guard` put the read back inside the transaction on a failed resolve; closed in the same session.
- **R105** (L, CONFIRMED; A5) `lib/services/sync/sync_engine.dart:367-374` — `SyncEngine.reset()` drops the singleton and calls `stop()`, never `dispose()`, so the old engine's `_statusController` is never closed: every database switch leaks a broadcast controller and its `_emits` chain, and a late `_emit()` on the dropped engine still calls `_statusService.read()` against the closing database (caught and logged at `:1008`). `dispose()` at `:456` is the only closer and nothing in `lib/` calls it; `SyncBloc._followEngine`'s doc relies on the stream staying open. Fix: `reset()` calls `dispose()` and `SyncBloc` treats `onDone` as the signal to re-resolve — or keep the behaviour and say in `reset()`'s doc why the controller outlives the engine. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:378` as the record's **second** option — `reset()`'s doc says why the controller outlives the engine. The first option (`dispose()` plus `SyncBloc` treating `onDone` as the re-resolve signal) touches `lib/bloc/sync/sync_bloc.dart`, and closing the controller without that change would leave the bloc following a done stream. The leak stands, documented.
- **R106** (L, CONFIRMED; A5) `test/services/sync/sync_engine_test.dart`, `test/widgets/optimized_note_editor_page_test.dart:3827-3857` — no suite wires the engine's hooks to the editor, so R99's double copy and R100/R101's stale-GetIt path cannot be caught. `sync_engine_test.dart` uses `RecordingSyncApplyHooks`, whose `fileConflictCopy` returns null unless a test hand-writes a note, so `AppSyncApplyHooks.fileConflictCopy` — the production conflict path and the one unguarded hook in the engine — is exercised nowhere (grep for `AppSyncApplyHooks(` in `test/` finds only `counters:`-only constructions), and `mergeFromElsewhere` discards `MergeOutcome.loser`. Fix: one engine test passing a real `AppSyncApplyHooks` with in-memory repositories that asserts the copy lands with D3's title, and one editor test whose merge files the engine's loser before announcing. Fix session: A6. → A6: fixed, both halves. Engine: `test/services/sync/sync_engine_test.dart` "the production hook files the copy with D3's title, beside the note it came from, and the engine announces and queues it" — a real `AppSyncApplyHooks` over in-memory `NoteRepository`/`FolderRepository`/`NoteStorageService`, asserting the D3 title, the loser's folder, the losing body, `MergeResult.inserted` on `afterPage` and the copy in the space. Editor: `test/widgets/optimized_note_editor_page_test.dart` "the engine's own hooks file the losing stored text inside the page, before the announcement reaches a dirty editor (A5 review R106)", on the earlier run's `announceMerge` / `autosaveUntilSaved` helpers with `mergeFromElsewhere(announce: false)`. It deliberately asserts no copy **count** — that is R99's question, A7's — see R125.

**What A5 could not check.** Anything needing a widget tree beside a live
engine — R99's composition, R100/R101 end to end, and the editor branch of
scenarios 1, 2 and 11 — because `sync_pair.dart` has no `WidgetTester` and
`optimized_note_editor_page_test.dart` has no engine; a real
`DatabaseLifecycle` switch (it needs `path_provider` and `DatabaseManager`,
and `SyncPair`'s engines are detached from the singleton); a restore through
`BackupService`, so scenario 3 was driven through the suspension flag only; a
quota answer landing specifically on `pushBatch`; and R102's residual. The
whole `flutter test` suite was deliberately not run — one at a time, and this
machine is shared with the other overnight sessions. Nothing was checked on a
device.

**A6 (fix pass I) — 33 of the 40 ids built, 22 new ids R107–R128.** The
session ran three `implementer` groups by file (editor → counters and the
backup restore → vocabularies, the database switch and the test holes), then
one medium-effort `reviewer` over the whole diff, then a fourth implementer
on what that review found, then the gate. D4 A was applied as written: every
H and M, plus the lows sitting in a file an H/M fix already opened. **Two
lows deferred for that reason** — R17 (`content_chunk_dao.dart`) and R43
(`folder_repository.dart`) — and **R99 declined and re-routed to A7**. Four
record-only ids (R33, R34, R42, R71) were written by the lead rather than
built. Gate: `dart analyze lib test test_driver` clean, `flutter test`
**10,553 passed, 10 skipped, 1 failed** — the one failure the documented
Windows-only `test/qa/host_devices_test.dart` `MacosDevice locate` case —
no ARB, `untranslated.txt` `{}`, no golden and no PNG in `git status`, no
schema change and no migration.

**What the review of the fixes caught.** Four of the 33 fixes took something
away, and one of those was an H: R26's abort predicate, copied from
`sync_puller.dart:352` as "every `SqliteException` but 19", made a clean
`SQLITE_BUSY` rollback **discard** the counter tap where the pre-fix code had
restored it — strictly worse than the hole R21 was closing. The lesson for A7
and A8: a predicate is safe only together with the response it drives
(`sync_puller` rethrows and re-pulls the page; the counter flush throws the
delta away), so a predicate lifted between modules has to be re-read against
its new consequence. The other three were R40 half-closed (R112), R100/R101
unsequenced (R113) and R2's refusal spending the retry ladder R10 had just
protected (R115).

**Five lead defaults, each one edit to flip.** **(a) Scope.** D4 A was read
as "a low is built when an H or M fix of this session already opens its
file"; R17 and R43 fall outside that line and are deferred rather than
built — the owner flips by striking the sentence and naming them for A7.
**(b) R62 is built even though it changes what an unbound user's restore
produces**, because the gate rule "`createX` stamps now, `importX`
preserves" and the "positions, sort preferences" line of both must-not-change
lists make the *current* behaviour the regression; the export and format 7
are untouched, so no archive stops opening either way. **(c) R9 is closed as
documentation**: the undo reset on a title-dirty merge and the silent title
LWW both still stand (R118) — the owner flips by writing the splice back in.
**(d) R99's decline is recorded as "branch 1 refused, branch 2 is the fix"**,
not as "R99 has no cheap fix"; A7 owns it. **(e) R107's allow-list** is
`CouldNotRollBackException` plus `SQLITE_IOERR`, `SQLITE_CORRUPT` and
`SQLITE_FULL` — the owner widens or narrows it by editing that list.

- **R107** (H, CONFIRMED; A6) `lib/services/counter_service.dart:788-790` and the branch at `:247-255` — R26's `_abortsTransaction` returned true for **every** `SqliteException` whose result code is not 19, which includes `SQLITE_BUSY` (5), `SQLITE_LOCKED` (6) and `SQLITE_READONLY` (8); those roll the transaction back cleanly and nothing was written, but the new branch then discarded `pending` and reloaded, so the tap was gone. Input: unbound user, one tap, the 300 ms flush lands while the database is locked by another connection or sits on a read-only volume. Result: the UI showed the tap, the table never got it, nothing retried — worse than the pre-session behaviour. The predicate came from `sync_puller.dart:352`, where it is safe only because the response is `rethrow` → the page is re-pulled. Fix: an allow-list of codes that really abort. Fix session: A6. → A6: fixed `lib/services/counter_service.dart:797-826` — `CouldNotRollBackException` plus the SQLite primary codes `SQLITE_IOERR` (10), `SQLITE_CORRUPT` (11) and `SQLITE_FULL` (13); `SqliteException.resultCode` is already the primary code, so an extended `778` reads as `10`. Test `a flush a locked database refused keeps the tap for the next one (A6 review R107)`, verified failing pre-fix (`Expected: <4> / Actual: <3>`). `sync_puller.dart` untouched — see R128 for the line that belongs in the record there.
- **R113** (M, PLAUSIBLE; A6) `lib/core/di/injection.dart:75-98` — three things about R100/R101's switched handler. **Ordering:** `notifyDatabaseSwitched()` fires at `database.dart:202` before `_open` returns, and the rebind then went through `AppDatabase.getInstance()` → `DatabaseManager.getInstance()` (an await) → `.then(rebindRepositoriesTo)`, while the engine's own handler started from the same notice — nothing sequenced them, and the rebind won only because the engine's chain is longer (a metadata read plus the network). If a run ever resolved from cache, a pull would touch `NoteRepository` on the closed database and R100 would return. **Swallowed failure:** `onError` was a `debugPrint`, so a rejected `getInstance()` left both repositories on the closed database silently. **`deleteAllData()`** (`database.dart:219-247`) fires `notifyDatabaseSwitching` and never `notifyDatabaseSwitched`, so nothing re-points after it — not a regression, but the new handler made the gap read as covered. Fix: have the notice carry the handle so the rebind is synchronous. Fix session: A6. → A6: fixed — `DatabaseSwitchedHandler = void Function(AppDatabase)` (`lib/database/database_lifecycle.dart:4-6,104-131`), `notifyDatabaseSwitched(db)` (`lib/database/database.dart:202`), `_rebindRepositoriesAfterSwitch(AppDatabase database)` synchronous with no `unawaited` and no swallowed `onError` (`lib/core/di/injection.dart:83-92`), `SyncEngine._rebuildAfterSwitch(AppDatabase _)` (`sync_engine.dart:343`), and the `deleteAllData` gap is one `///` line in the handler's doc. Test: `test/database/database_instance_test.dart` asserts the handler is called with the database it announces. The ordering claim is proven for "the notice hands over the handle"; no test races the engine's handler against the rebind.
- **R115** (M, CONFIRMED; A6) `lib/bloc/optimized_note/optimized_note_bloc.dart:307-316` → `lib/services/auto_save_service.dart:194-199` — R2's `NoteWriteRefusedException` is not a `SaveHeld`, so it landed in the generic `catch`: `SaveStatus.error` (the app-bar error dot) plus `_scheduleRetry()`, three rungs at 2 s / 4 s / 8 s each hitting the same tombstone. R10 had just established in this same diff that a deliberate refusal stays `unsaved` and spends no rung, and a tombstone refusal is the same shape. R2's window does close (the text stays pending), but the page burns its retry budget and shows an error for a note that is about to be retargeted. Checked: `note_row.dart:401` is the only other `UpdateOptimizedNote` dispatcher and passes no completer, and the `[AutoSaveService] Save failed:` lines in the suite are that `debugPrint`, not an uncaught error. Fix session: A6. → A6: fixed — new `SaveRefused` marker (`auto_save_service.dart:25-41`) handled at `:219-224` (unsaved, `onChangeDetected(true)`, **no** re-armed debounce, no rung), and `NoteSaveCoordinator._save` translates the exception into it (`note_save_coordinator.dart:409-418`) — the translation lives in the coordinator because a service importing a bloc would invert the layering. Tests `a refused write stays unsaved, spends no rung and arms nothing (A6 review R115)` and the coordinator twin, the latter verified failing pre-fix. The generic catch now also calls `onChangeDetected?.call(true)`, closing the gap R15 left there.
- **R117** (M, CONFIRMED; A6) `lib/services/counter_service.dart:377-384` with `lib/database/daos/counter_dao.dart:180-183` — R24's premise was "the DAO's own no-op check already suppresses a redundant write". It does not when there is no value row: the check is `existing != null && !existing.isDeleted && existing.value == value`, so `existing == null` falls through, the write proceeds, `db.enqueue(...)` inserts a `sync_outbox` row (`crdt_write.dart:115-126` has no bound check) and a `counter_values` row at `startValue` is inserted. Reachable for a counter whose value row never arrived — a merge carrying the `counters` row only, or a restore whose `counterData` lacked the value; `addCounter` → `insertCounterWithValue` seeds it for a counter created in-app. For an **unbound** user that is a persisted extra row and an outbox entry where there had been nothing, which breaches §4's "no behaviour change for an unbound database". Fix session: A6. → A6: fixed `lib/services/counter_service.dart:388-418` — `resetGlobal` records nothing when nothing is pending for the counter and the table holds no live global value row; memory is still set to `startValue` first, and the look is taken inside `_serialized` so a flush in flight writing that very first row cannot hide behind the read. **The DAO widening was declined on evidence:** `_upsertValue` is also `insertCounterWithValue`'s body (`counter_dao.dart:53`), where `value == startValue` is exactly what `addCounter` passes, so widening there would stop seeding a new counter's value row; widening only the public `upsertValue` would drop a restore's pin for any value equal to `startValue` and change `test/database/sync_outbox_test.dart:295`.
- **R109** (M, PLAUSIBLE; A6) `lib/pages/optimized_note_editor_page.dart:2916-2923` → `:1200-1208` — R3 replaced the snapshot check with `_awaitRemoteWork(leaving: true)`, whose `do { while (_remoteBusy > 0) await _remoteWork; … } while (_remoteBusy > 0)` exits only when no remote change is pending at all. A pull streaming several pages that each touch this note keeps `_remoteBusy > 0`, so the exit never resolves; `PopScope.canPop` is false and `_isExiting` is already true, so the user's back presses are swallowed (`:2456`) and nothing is shown. Before this session the exit had no busy-wait at all. Fix session: A6. → A6: fixed `lib/pages/optimized_note_editor_page.dart:2921-2931` — the exit awaits one `_remoteWork` turn (the handlers queued when it asked, which is M1's window) plus one `_retryUnfiled()`, then falls through to the `_holdsDeletedNotesText` test; `_awaitRemoteWork` itself is unchanged, so the write gate keeps its S4b-1 H2 semantics. **No test:** with a bounded number of merges the old loop also terminates, so the only discriminating case is an unbounded stream of merges — a 30 s timeout before the fix. The bound is argued, not proven.
- **R111** (M, PLAUSIBLE; A6) `lib/pages/optimized_note_editor_page.dart:2919-2925` — R8's fix re-arms `filing.failed = false` and relies on `_run` raising the notice during the wait, but `_retryUnfiled()` (`:1214-1217`) returns the **in-flight** `_filing` pass when one exists and that pass may already have attempted this filing; with `_remoteBusy == 0` nothing re-runs `_run`, the method returns false, `exitAborted()` runs and the user gets **no** notice — where before the exit raised `syncNoteKeptAsNewFailed` itself. A silent back button on a page that will not close. Fix session: A6. → A6: fixed `:2931-2937` — after the wait a still-unfiled `keepsText` filing gets `_raiseFilingFailure` as a backstop. No new test: the harness has no seam that makes `_retryUnfiled` join an attempt which already failed *this* filing with `_remoteBusy == 0`; the existing M1/L4/L10 cases stayed green.
- **R110** (L, PLAUSIBLE; A6) `lib/pages/optimized_note_editor_page.dart:2965-2967` — R18's declared exception stacked two messages: `_awaitRemoteWork` runs `_retryUnfiled()` → `_attempt` → `_run`, and `_run` shows the notice itself at a filing's **first** failure, so in the ordinary case (the user taps Move while the merge handler is filing) `_run` showed `syncNoteConflictCopyFailed` and `_currentNoteMetadata` showed it again. Fix session: A6. → A6: fixed `:2984-2995` — `_currentNoteMetadata` speaks through a new `_raiseFilingFailure`, which no-ops when `filing.failed` is already up.
- **R127** (L, PLAUSIBLE; A6) `lib/pages/optimized_note_editor_page.dart:2966` — `_currentNoteMetadata` used `_unfiled.first`, where `_showFilingNoticeOwed` (`:1292`) deliberately prefers the `keepsText` filing as the more urgent of the two, so with both pending Move/Share reported the conflict-copy failure and stayed silent about the deleted note's text; it also skipped `_run`'s `_isCurrentRoute` guard. Fix session: A6. → A6: fixed with R110 and R111 in one block — the same preference (`firstWhere(…, orElse: _unfiled.first)`) and the same `mounted && _isCurrentRoute` guard, through `_raiseFilingFailure`.
- **R112** (L, CONFIRMED; A6) `lib/bloc/sync/sync_bloc.dart:137` — R40 was only half closed: `_followEngine()` was fire-and-forget and `_withEngine(await _readStatus(user))` on the very next line still read `_followedEngine`, the **old** engine, so the first `RefreshSyncStatus` after a switch still laid the dropped space's `lastPullAt`/`lastPushAt`/`pause`/`parkedCount` over the new database's read; only the second refresh was clean. R40's own new test could not see it because `old` never emitted before the refresh. Fix session: A6. → A6: fixed `:146` — `_followEngine()` returns its future (the two fire-and-forget callers now say `unawaited`) and `_onRefresh` awaits it under the existing `statusTimeout`, so a dead engine still cannot keep the refresh from emitting. `test/bloc/sync_bloc_test.dart:663` strengthened (`old` emits `lastPullAt` before the switch; the refresh's status must carry none), verified failing pre-fix.
- **R108** (L, PLAUSIBLE; A6) `lib/services/counter_service.dart:252-254` — R26's abort branch `return`ed before `_scheduleDirtyFlush()`, which is R21's own symptom on the new path. Fix session: A6. → A6: fixed `:252-262`, **but the state is not reachable**: every recording path (`incrementGlobal`, `decrementGlobal`, `setGlobalValue`, `resetGlobal`, `increment`, `decrementForNote`, `setValueForNote`, `resetForNote`) calls `_scheduleDirtyFlush()` itself, so a tap made during the aborted write always arms its own timer. The line is kept as a belt for a future recording path (it is idempotent) and the test `a tap made during a flush whose rollback failed reaches the table with no further tap (A6 review R108)` guards the branch; it is the one id in the data-loss block with no discriminating pre-fix failure.
- **R119** (L, CONFIRMED; A6) `test/services/counter_service_test.dart:277-290` — R24's test seeded `upsertValue(id, '', 8)` before the Reset, so `existing != null` and the DAO's no-op check was never exercised; the case §4's unbound rule needs was not pinned. Fix session: A6. → A6: fixed — test `a Reset on a counter with no value row writes nothing, bound or not (A6 review R117/R119)`: a counter row inserted by hand with no `counter_values` row, `resetGlobal` + `flush()`, asserting `syncOutboxDao.pending()` empty and `getValue(id, '')` still null. Verified failing pre-fix (`Expected: empty / Actual: [...]`).
- **R120** (L, CONFIRMED; A6) `test/widgets/optimized_note_editor_page_test.dart:3898-3902` — `autosaveUntilSaved` loops up to six autosave rounds until `hasChanges` is false, so it cannot see the *extra identical write, push and outbox row* that R1's declared deviation was precisely about. Fix session: A6. → A6: fixed `:4915-4922` — the H1 case now pins the writes themselves: `noteBloc.updates.map((u) => u.content)` is exactly `['mine $body', 'more mine $body']`.
- **R122** (L, CONFIRMED; A6) `test/services/auto_save_service_test.dart:39,51` — `_FakeSaver.duringSave` was declared and invoked but no test set it; the R1 case called `h.service.writeIssued()` from the test body, so nothing exercised the real coordinator ordering of `writeIssued` relative to the dispatch. Fix session: A6. → A6: fixed — both R1 cases now drive `writeIssued` (and, in the second, the adoption before it) through `duringSave`, i.e. inside `onSave` where the coordinator calls it.
- **R123** (L, CONFIRMED; A6) `test/services/backup_service_dates_and_sort_order_round_trip_test.dart:15-18` — the new suite *comments* that `position` is deliberately not preserved and asserts nothing, so a later session could "finish" R62 by preserving it. Fix session: A6. → A6: fixed `:79-87` — `expect(restoredFolder.position, greaterThan(folder.position))` with the reason naming the rule.
- **R124** (L, CONFIRMED; A6) `lib/services/counter_service.dart:66-69` — R22's `static final _changes` is right in production (it mirrors `VocabularyService`) but is never closed and is shared with every `forTesting` instance, so a `CounterBloc` built over one hears another's `reload()`/`importData()`; `test/bloc/counter_bloc_database_switch_test.dart` never called `CounterService.reset()` in tearDown, so the instance leaked to the file's end. No failure today; the isolation guarantee is gone. Fix session: A6. → A6: fixed — `tearDown(CounterService.reset)` in the new file plus a `///` paragraph on `forTesting` saying the stream is static and shared. No other counter suite needs it (the rest build only `forTesting` instances, which `reset()` does not drop).
- **R126** (L, CONFIRMED; A6) `lib/services/auto_save_service.dart:260-278` — R1's change absorbed `adoptSavedContent`'s `///` block into `writeIssued`'s: one contiguous comment above `writeIssued` carrying two unrelated contracts, and `adoptSavedContent` left with no doc at all. An existing `///` was effectively deleted, which the house rule forbids. Fix session: A6. → A6: fixed `:260-284` — the original block is back above `adoptSavedContent` and `writeIssued` keeps its own.
- **R114** (M, PLAUSIBLE; A6 → A7) `lib/repositories/note_repository.dart:598`, `lib/repositories/folder_repository.dart:519` — the half R100/R101's fix does not reach: `watchNotesByFolder` and `watchFoldersByParent` bind `_db` at **subscription** time, so a page mounted before a database switch keeps a stream over the closed database. `rebindDatabaseTo` re-points the handle and drops the caches but cannot re-point a live subscription, so "merged folders reach the browser list" still does not hold for an already-mounted page. Input: the browser left mounted under the Settings database page while the user switches databases, then a pull. Fix: have the watch methods resubscribe on the switched notice, or key them off a broadcast the rebind re-seeds. → A6: **deferred: A7** — it is the repositories' streaming contract, not the DI wiring A6 owned, and A7 is already in the merge-to-surface path. → A7: fixed `lib/repositories/note_repository.dart:76,609`, `folder_repository.dart:61,528` and a new `lib/utils/restartable_stream.dart` — the two watch methods resubscribe on the switched notice. Tests `a note watch mounted before a switch reads the new database`, `a folder watch …` and `a note watch keeps following writes on the new database`, verified failing pre-fix (`Expected: ['After'] / Actual: ['Before']` twice, and `Expected: ['Later'] / Actual: []`). Residual R140: the helper turned a drift broadcast stream into a single-subscription one, so a second `listen` threw; closed in the same session. The fix review also confirmed nothing in `lib/` subscribes to either method today, so the fix is latent — `watchNoteById` and `watchFolderById` have the identical binding and are deliberately left, as a new id.
- **R116** (L, PLAUSIBLE; A6) `lib/database/daos/vocabulary_dao.dart:193-203` — R23's snapshot guard turns a remote **rename** into a live duplicate pair: snapshot `['Squat']`, the field still says `Squat`, the merged row now says `Back Squat`; the insert loop finds no `byTerm['Squat']` and inserts, the tombstone loop sees `Back Squat` in neither `known` nor `seen` and keeps it. Both live. Before R23 the local rename won and the remote row was tombstoned. No data loss, and arguably the safer direction, but it is a duplicate shape the phase record's §8 does not record — and R35's suggestion-bar dedupe now hides the second row from the very user who would collapse it. Fix: none if the owner accepts the direction; say so in §8. → A6: **deferred: owner** — recording it means choosing between "a rename never loses a term" and "§8 grows a third accepted duplicate"; the lead did not take that for the owner. The pair collapses on the next save of that vocabulary.
- **R118** (L, CONFIRMED; A6) `lib/pages/optimized_note_editor_page.dart:1307-1316` — R9 is closed as documentation, not as a fix: the new paragraph states the LWW rule and declines the splice with a sound reason, but both behaviours the id named are unchanged — a remote body merge on a title-dirty page still resets the undo stack through `_adoptLoadedContent` → `loadText`, and a concurrent remote rename still loses to the pending local title **with no notice**. If R9 reads as closed, the owner is accepting both. → A6: **deferred: owner** — lead default (c). The splice is a second document-replacement path on the typing path (`markdown-engine`'s one-grammar rule and the editor's single `loadText` owner), so it is a slice, not a fix.
- **R121** (L, CONFIRMED; A6) `test/controllers/note_save_coordinator_test.dart:240-247` — the assertion R10 had to change is itself a behaviour the owner should know: a held write now reads `SaveStatus.unsaved` instead of `SaveStatus.error`, and its retry comes at the 5 s debounce instead of the 2 s first rung. That is R10's intent, but it means a held write's first retry is **slower** than before and the app bar shows nothing at all while a filing is stuck — the only signal left is the filing's own snackbar, which R110, R111 and R127 are about. → A6: **deferred: owner** — no code change; recorded so the trade R10 made is on the record rather than only in a test diff.
- **R125** (L, CONFIRMED; A6 → A7) `test/widgets/optimized_note_editor_page_test.dart:4081+` and `test/services/sync/sync_engine_test.dart` — R106's two new tests assert `bodies, contains(losingText)` and deliberately leave the copy **count** to R99. Correct while R99 is open, but it means nothing notices if the count grows again. → A6: **deferred: A7** — when A7 lands R99's hook branch, that `contains` becomes an exact count; it is the regression proof for the fix itself. → A7: fixed `test/widgets/optimized_note_editor_page_test.dart:4127-4136` — with R99 landed, `bodies, contains(losingText)` is now `expect(hookCopy, isNull)` + `expect(filed, hasLength(1))` + the single copy's body is `'theirs'`; `sync_engine_test.dart:354` gained `content: 'typed on A'` on the announced copy row.
- **R128** (L, CONFIRMED; A6) `lib/services/sync/sync_puller.dart:352` and the phase record's §8 — two record-only carry-overs the fix pass surfaced. The puller still uses the "every `SqliteException` but 19" deny-list R107 had to undo in the counters; it is safe there (it rethrows and the page is re-pulled) and it reads the primary code, so `1555 SQLITE_CONSTRAINT_PRIMARYKEY` masks to 19 correctly — but it is the shape a third reader would copy. And `test/database/sync_outbox_test.dart:703-718` ("a value pin it already has") would pass vacuously if a counter's first per-note value ever stopped creating a row. → A6: **fixed** for the part the lead owns — the phase record's §8 bullet no longer claims the merge-created duplicate term is offered twice (R35 fixed that in this session); the `sync_puller` note is **deferred: A7**, which owns that file, as one sentence beside the predicate. → A7: fixed `lib/services/sync/sync_puller.dart:389` — one paragraph beside the predicate saying why the deny-list is safe here (the puller rethrows and the page is re-pulled; `resultCode` is the primary code, so `1555` reads as `19`) and that the shape must not be copied into a path that swallows. The phase-record half was already done in A6.

**A7 (fix pass II) — 55 of the 57 ids built, 19 new ids R129–R147.** The
session ran three `implementer` groups by file (the engine, the pusher,
the puller, the binding and status services → the merge, the DAOs, the
bindings and the category seed → the hooks, the repositories and the
editor seam), then one medium-effort `reviewer` over the whole diff, then
a fourth implementer on what that review found, then the gate. D4 A was
applied as written: every H and M, and the lows whose fix sits in a file
the session already opened; two lows left, one H left to the owner.

**The fix review earned its cost again.** Of the 55 fixes it read, seven
took something away, **one of them a High**: R99's new `OpenNoteRegistry`
asked its question at **merge** time, inside the page transaction, while
the editor answered a different one at **announcement** time — so a
pending **title-only** edit (phase record §3.9 M6), a save that landed in
the window, or a page that went clean between the two moments each left
the losing body with **no copy at all**, worse than the double copy R99
was closing. That is A6's R107 lesson repeated one layer up: a predicate
is only safe together with the response it drives, and the two sides of a
suppression must be asking the same question at the same moment. The fix
makes the registry a **claim** the page latches, not a question the hook
asks. The other six: the folder repair ran during the bind's initial merge
and pushed a flattening move (R130), and minted **below** the move it
repairs once R65 moved the clock advance off the merge (R131); R65 left
`persistClock()` outside the page transaction, breaking `crdt_write.dart`'s
own "no committed row carries a stamp above the stored value" (R132);
R79's UTC-midnight requirement could park a legacy row forever (R133);
R46's run-ending throw left the entry queued and so failed **every** later
run (R134); and R114's helper turned a drift broadcast stream into a
single-subscription one (R140).

**A7's lettered defaults.** **(a) R98 was not built** — A5's default (e)
says the fix session takes it only with the owner's letter, and no letter
was left; the three options stand in the id. **(b) R77 took the record
sentence**, A3b's own default (a): phase record §3.4 (4) now states the
half-resurrection, and no merge-side re-tombstone was written, which §3.4
(4) and phase record §5 forbid. **(c) R39 went to S4b-2** and **R83 was
left under D4 A**, both branches the ids themselves offer. **(d) R133 was
probed against the owner's data rather than guessed**: a copy of
`C:\Users\mobx3\Downloads\gym_notes_anta.db` (never opened in place) holds
96 day rows across the three tables and **every one** is at UTC midnight,
so the park-forever path is latent, needs no migration, and the fix is a
normalisation on the way out in `encode` only — the stored column, the row
key and the outbox entry are untouched. **(e) R41 was built by the lead**,
not an implementer: it fell out of group 1's brief by mistake and is a
test the id spells out in full.

- **R129** (H, PLAUSIBLE; A7) `lib/services/sync/app_sync_apply_hooks.dart:200` with `lib/pages/optimized_note_editor_page.dart:1120,1129,1361,1368` — R99's predicate is asked at **merge** time, inside the page transaction, and answered by a **different** decision at **announcement** time. Three branches of `_adoptRemoteUpdate` return without filing while the hook had already stood back, and the losing local body is then preserved nowhere (`_apply` drops a null copy with no log line, `sync_puller.dart:323-333`): a pending **title-only** edit (§3.9 M6 — `_hasUnsavedText` is true, but the page takes `_adoptLoadedContent(arriving, titlePending: true)` and replaces the body in place); `saveStatus == saving` with `hasChanges == false` at merge time, the save landing before `_queueRemote` so the page takes the clean branch; and a page that goes dirty → clean in the window, which the save hold does not cover. The converse (clean → dirty) gives two copies again and makes R125's new exact assertion flaky. Input: note open, the user types in the **title only**, an earlier autosave of the body still queued, a newer remote body arrives. Before this diff it was a conflict copy; after it, the stored local body is gone from the row, from the editor and from any copy. Fix: make both sides answer one condition. Fix session: A7. → A7: **fixed** `lib/pages/optimized_note_editor_page.dart:1140,1371` + `app_sync_apply_hooks.dart:214` + `open_note_registry.dart` — `holdsUnsavedText` became `claimsConflictFiling`, a **claim** the page answers on its *body* being unsaved and latches in `_owesConflictCopy`, consumed by `_adoptRemoteUpdate` whatever it reads then. Tests `a pending title edit claims no copy: the engine files the body the merge overwrote (A7 review R129, M6)` and `a page that claimed the copy files it even when its save landed first and left it reading clean (A7 review R129)`, both verified failing pre-fix (`Expected: not null / Actual: <null> / the page claims nothing` and `Expected: an object with length of <1> / Actual: [] / Which: has length of <0>`).
- **R130** (M, PLAUSIBLE; A7) `lib/database/daos/folder_dao.dart:877` — R63/R64's `_repairMergedParent` mints a local stamp and queues an outbox entry with no regard for `bind_merge_pending` / `bind_floor`, and judges reachability against a **half-applied page**. Input: a rebind after a restore, where the local rows are pre-bind state — a remote folder F merged before its parent P's live envelope arrives in the same pull sees P's stale local tombstone, is re-parented to the nearest live ancestor and that move is **pushed into the space**; when P arrives live moments later the subtree has been flattened on every device. The shape R76 was fixed for in the same diff; parents are on §4's list. Fix: skip the repair while `bind_merge_pending` is set, and run it once over the page's folder keys after the page's merges. Fix session: A7. → A7: **partially fixed** `lib/database/daos/folder_dao.dart:884`, test `the repair stands back while the bind's initial merge is pending (A7 review R130)`, verified failing pre-fix (`Expected: '4bed5d5a-…' / Actual: <null>` — the row had been re-parented to the root and queued). The second half is **declined for scope**: there is no per-page DAO seam, and adding one (`SyncTableBinding.afterPage` + a public `repairMergedParents`) is a new seam across three files. Residual: inside one **non-initial** page, a folder whose parent is locally a tombstone and whose live envelope is later in the same page is still repaired and the move still pushed. → **deferred: owner** (it needs the seam).
- **R131** (M, PLAUSIBLE; A7) `lib/database/daos/folder_dao.dart:877` (R63 × R65) — the repair calls `db.stampLocal` from a clock the page has **not** advanced, because R65 moved `advanceClock` to after the page transaction. When the writing device's HLC wall is ahead of this one's, the repair sorts **below** the remote move it repairs: the push is denied, the same remote parent re-applies on the next pull, the repair fires again and the queue is re-armed every run — the doc comment's "the space converges on it" is false. Before R65 this could not happen. Fix: advance the clock to the remote stamp immediately before `stampLocal`. Fix session: A7. → A7: fixed `lib/database/daos/folder_dao.dart:892`, test `a remote move that closes a cycle is cut to the root` through the tightened `expectRepairQueued` (R143), verified failing pre-fix (`Expected: a value greater than <0> / Actual: <-1>`). Noted, by design: `HybridLogicalClock.maxDrift` is one hour, so a writer more than an hour ahead is still clamped and the repair still sorts below — that is R98's territory, not this one's.
- **R132** (M, PLAUSIBLE; A7) `lib/services/sync/sync_puller.dart:342` — R65 left `persistClock()` **outside** the page transaction, so a kill between the commit and that insert leaves `last_hlc` below stamps carried by committed rows, which `lib/database/crdt/crdt_write.dart:263-265` states as an invariant. Next launch seeds low; the user's first edit on a merged note mints below it, loses on the next pull and produces a conflict copy of the user's own text. Fix: keep the **store** inside the transaction while the in-memory advance stays outside. Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:346` + a new `CrdtWrite.persistStamp(stamp)` (`crdt_write.dart:261`), test `a page leaves a seed covering the stamps it committed, even where the clock itself is held to the drift guard (A7 review R132)`, verified failing pre-fix (`Expected: a value greater than or equal to <0> / Actual: <-1>`). The test drives a second, non-kill instance of the same defect: `persistClock()` stored the **clamped** clock, so a remote stamp beyond `maxDrift` left the seed below a committed row with no crash at all.
- **R133** (M, PLAUSIBLE; A7) `lib/services/sync/sync_table_binding.dart:213` — R79 tightened `dayKeyOf` from "whole-second epoch-ms" (phase record §3.4 (8)) to "UTC midnight", but the three day DAOs do not normalise (only the three services do) and no migration normalised the stored columns. A legacy or imported row whose `day` is a *local* midnight pushes fine (`rowKeyOf` does not validate) and **parks forever on every receiving device**; under the bind floor `_yieldToFloor` also retires its outbox entry, so it never syncs again — one-way silent loss of a presence mark, a skip or a day description. **Probed on a copy of the owner's export** (never opened in place): `calendar_event_skips` 0 rows, `calendar_event_absences` 91 / **0** not at midnight, `calendar_event_occurrences` 5 / **0** — latent, no migration needed. Fix: keep `dayKeyOf` strict on the receiving side and make the push side unable to produce an unpushable envelope. Fix session: A7. → A7: fixed `lib/services/sync/sync_table_binding.dart:226,249,257` (`localDayKeyOf`, `dayEnvelopeMs`, `dayEnvelopeKey`) + the three day bindings, test `a row stored at a local midnight still pushes a key dayKeyOf accepts (A7 review R133)`, verified failing pre-fix (`FormatException: the day is not a UTC midnight / e1|1774735200000`). **Deviation:** `rowKeyOf` is **not** normalised — it is the local identity the outbox entry carries, and normalising it would make `_prepare`'s `byKey` lookup miss and silently `ackThrough` the entry. The normalisation is in `encode` (key and `dayMs`) and `loadByKeys` uses the lenient `localDayKeyOf`. A pre-existing non-midnight row now pushes as **the UTC midnight nearest its stored instant** — the calendar day a local-midnight write stood for, in zones either side of UTC — while the row, its column and its outbox key are untouched.
- **R134** (M, PLAUSIBLE; A7) `lib/services/sync/sync_pusher.dart:137` — R46 replaced "park that table for the session" with a run-ending `ArgumentError` for an outbox entry whose table has no binding. The entry stays queued, so **every** later run throws at the same entry: the engine fails permanently with back-off and no exit, where before it degraded to one stalled table. Fix: keep the loud failure and park that one entry afterwards. Fix session: A7. → A7: fixed `lib/services/sync/sync_pusher.dart:143`, test `the entry it failed on is parked, so the next run gets past it (A7 review R134)`, verified failing pre-fix (`Expected: null / Actual: SyncGatewayFailure:<SyncGatewayFailure.unknown>`). The existing R46 case's `expect(report.parked, 0)` is now `1` — the park is the fix.
- **R135** (L, PLAUSIBLE; A7) `lib/services/sync/tables/counters_binding.dart:57` vs `:79` — R66's new comment claims an unknown scope "must cross this device unchanged". It cannot: `decode` still writes `_scopeOf(...).name`, the merge stores that, and the next `encode` reads `global` off the row. Fix: stop normalising on decode too, or correct the comment. Fix session: A7. → A7: fixed `lib/services/sync/tables/counters_binding.dart:59` — the comment, the cheaper option; decode still normalises, and the comment now says what the change buys (a value this build reads but does not recognise is re-encoded as stored; a value it never stored cannot survive).
- **R136** (L, PLAUSIBLE; A7) `docs/cloud-sync-phase-02-own-space.md` §3.4 (8) — R70 made `preview` lenient while the record says "every v43 column stays strict" and that the lenient accessor arrives "when the first one appears (none exists today)". Fix: amend the sentence in the same change. Fix session: A7. → A7: fixed — §3.4 (8) names `preview` as the first lenient v43 column and why (it crosses for backup-format parity and the merge recomputes it from the body).
- **R137** (L, PLAUSIBLE; A7) `lib/services/sync/sync_puller.dart:191` with `firestore_sync_gateway.dart:163-166` — on a `resumed` (ten-second overlap) page where every document was skipped, `latest` is the maximum *within the page* and is never compared against the stored cursor, so R44's new store can move the cursor **backwards**. Harmless (a re-read) but newly reachable. Fix: seed or guard the comparison. Fix session: A7. → A7: fixed `lib/services/sync/firestore_sync_gateway.dart:156` — `latest` is seeded with the `after` cursor, so `next` can never fall below it and the puller's equality check breaks instead of storing. No test: the Firestore gateway has no suite (R91, A8's).
- **R138** (L, CONFIRMED; A7) `test/database/crdt_write_guard_test.dart:150-154` — R72's `retires` regex ends with `|= ?[\w.]*\bsyncOutboxDao\b`, which lets an allow-listed file bind the DAO to a local and call *anything* on it unchecked — `sync_pusher.dart:100` does exactly that. A row insert still needs `syncOutbox`, `SyncOutboxCompanion` or the raw name, all of which the fence catches, so the must-not-change rule holds today; the fence just does not enforce "only these methods" as its own comment claims. Fix: drop the alias alternative and name the receiver. Fix session: A7. → A7: fixed `test/database/crdt_write_guard_test.dart:154` — the alias alternative is gone and the one receiver (`final outbox = _e._db.syncOutboxDao;`) is named literally.
- **R139** (L, PLAUSIBLE; A7) `lib/services/sync/app_sync_apply_hooks.dart:206` — R104's `_pageStrings ?? await _strings()` keeps the hazard alive: `beforePage` is `_guard`ed, so a single failed resolve puts the database-bound `SettingsService`/localization read back **inside** the page transaction, which is the thing R104 exists to remove; the new test covers only the happy path. Fix: drop the fallback or resolve unconditionally outside the transaction. Fix session: A7. → A7: fixed `lib/services/sync/app_sync_apply_hooks.dart:98` — the `_guard` is gone, so a failed resolve fails the page **before** its transaction. Test `a language that cannot be read fails the page before its transaction, never from inside it (R139)`. The `??` remains only for a `fileConflictCopy` called without a page, the direct-call path the tests use.
- **R140** (M, CONFIRMED; A7) `lib/repositories/note_repository.dart:608`, `folder_repository.dart:528`, `lib/utils/restartable_stream.dart` — R114's helper wraps a drift **broadcast** stream in a plain `StreamController`, so a second `listen` now throws where it did not before. Input: two pages watching the same folder. The fix review also confirmed nothing in `lib/` subscribes to either rebound method today (`note_storage_service.dart:569` is the only wrapper and has no call site), so R114's fix is latent while the new surface is real. Fix: preserve the broadcast contract. Fix session: A7. → A7: fixed `lib/utils/restartable_stream.dart:34` (a broadcast controller), test `two pages may watch the same folder at once (A7 review R140)`, verified failing pre-fix (`Bad state: Stream has already been listened to.`). `watchNoteById` / `watchFolderById` have the identical subscription-time binding and are deliberately **not** rebound — a new id, see below.
- **R141** (L, CONFIRMED; A7) `test/services/sync/support/sync_pair.dart:265-273` — R103's `_tombstoneColumns` excludes `updatedAt` and `deletedAt`, the two columns R67/R81 changed, and `version`, which R103's own fix text named: the convergence suite passes identically with and without R67/R81. Per-DAO coverage existed only in three of the thirteen merge suites. Fix: put the assertion in `merge_contract.dart`. Fix session: A7. → A7: fixed `test/database/support/merge_contract.dart:198` — the `updated_at == deleted_at` assertion now runs for all thirteen tables, guarded on the column's presence because `counters` and `counter_values` have none (it failed on them with `Expected: <1772409600> / Actual: <null>` before the guard). `sync_pair`'s exclusions stay as they are: the two devices' tombstone timestamps are reconstructed from the stamp under §3.4 (4), and the per-DAO contract now holds them instead.
- **R142** (L, CONFIRMED; A7) `lib/services/sync/sync_engine.dart:76` — R56's new `SyncRunSkip.initialMergePending` has one producer and no reader anywhere in `lib/` or `test/`, so R56 adds a state nothing can regress on. Fix: assert it, or drop it. Fix session: A7. → A7: fixed `lib/services/sync/sync_engine.dart:536` — `onAppBackgrounded` returns its `SyncRunReport` (not started → `SyncRunSkip.stopped`), asserted in `sync_engine_test.dart`'s `going to the background pushes nothing before the floor pull`; `test/support/fake_sync_engine.dart` follows the signature.
- **R143** (L, CONFIRMED; A7) `test/database/folder_merge_test.dart:124` — `expectRepairQueued` asserts `row.hlcTimestamp, isNot(newerHlc)`, which cannot tell a repair stamped **above** the remote from one stamped below — exactly the property R131 breaks; with `newerHlc = 'ffffffffffff:0001:remote'` the repair is always below and the test still passes. Fix: compare, do not negate. Fix session: A7. → A7: fixed `test/database/folder_merge_test.dart:153` — `compareTo(movedUnder) > 0`, and the group now uses a stamp inside the HLC drift guard so the assertion can discriminate at all. (`greaterThan` is not usable on a `String`: `NoSuchMethodError: Class 'String' has no instance method '<'`.)
- **R144** (L, CONFIRMED; A7) `test/widgets/optimized_note_editor_page_test.dart:4111` — R99's test exercises the real `OpenNoteRegistry` end to end, but only the body-dirty branch; R129's loss path has no test on either side. Fix: with R129. Fix session: A7. → A7: fixed — the title-only branch is the first of R129's two tests, built end to end through the real registry.
- **R145** (L, CONFIRMED; A7) `lib/database/crdt/crdt_merge.dart:28` vs `lib/database/daos/content_chunk_dao.dart:370,391` — R65's new doc asserts "the clock is **not** advanced here" while `mergeChunk` still calls `db.hlc.update` inside its own transaction, the hazard R65 names; `mergeChunk` has no caller in `lib/`. Fix: make the doc true. Fix session: A7. → A7: fixed `lib/database/crdt/crdt_merge.dart:37` — the doc names `mergeChunk` as the one exception and why it is harmless. `mergeChunk` itself untouched (deleting it is scope).
- **R146** (L, CONFIRMED; A7) `lib/services/sync/sync_puller.dart:342` — `persistClock()` runs after **every** page including one where nothing merged, costing one `sync_metadata` insert per page that changed nothing. Fix: guard it; folds into R132. Fix session: A7. → A7: fixed `lib/services/sync/sync_puller.dart:349` — the post-page `persistClock()` is gone entirely, so the one clock write per page is R132's in-transaction one and a page that merged nothing writes none. That is what keeps `sync_engine_test`'s `a page is one transaction: one clock write per page` at two writes; it failed with four while both stores were in place.
- **R147** (L, PLAUSIBLE; A7) `lib/services/sync/app_sync_apply_hooks.dart:52` — R104's `_pageStrings` is never cleared, so it outlives its page and a locale change between pages is served from it until the next `beforePage('notes')`. Fix: clear it when the page ends. Fix session: A7. → A7: fixed `lib/services/sync/app_sync_apply_hooks.dart:107`, test `the page's language does not outlive the page (R147)`.
- **R148** (L, CONFIRMED; A7) `lib/repositories/note_repository.dart` `watchNoteById`, `lib/repositories/folder_repository.dart` `watchFolderById` — R114's twins. Both bind `_db` at **subscription** time exactly as `watchNotesByFolder` and `watchFoldersByParent` did, and neither was rebound, so a page mounted before a database switch keeps a stream over the closed database. Filed rather than built because R114's own fix is latent — the fix review confirmed nothing in `lib/` subscribes to any of the four today (`note_storage_service.dart:569` is the only wrapper and has no call site) — and the two by-id methods have no caller at all, so building them now would be surface for surface's sake. Fix when a page first subscribes: the same `restartableStream` wrapper and `_rebinds` seed the other two use. Also open from the same change: `restartableStream`'s controller is deliberately never closed (it forwards no `onDone`, because a closing database ends its DAO streams exactly when a rebind is on the way), so a repository disposed while a page still listens leaves the subscription alive until the page cancels. → **deferred: owner** (neither is reachable today).

---

## 4. Must not change

- Everything in the phase record §5 (the `gym_notes` directory, backup
  format 7, the HLC encoding, soft deletes, positions, `noteId == ''`,
  the outbox written only inside `CrdtWrite`, `content_chunks` never
  queued, the restore's unbinding inside `SyncSuspension.run`, no
  Firestore type outside the two gateway files, the layering, no new
  pattern, no migration without the owner).
- **No behaviour change for an unbound database.** A fix that alters the
  autosave, the counters, the folders or the launch path for a user who
  never syncs is a regression unless the ledger id it fixes is itself a
  regression (then the id says so and the fix restores the pre-sync
  behaviour).
- The three saved suites (`calendar`, `browser`, `alerts`) and the 27
  goldens unchanged — the review ships no visible change.
- The rules are not deployed; `firebase.json` stays gitignored; no
  Firebase config file enters a commit.
- The owner's export `C:\Users\mobx3\Downloads\gym_notes_anta.db` is never
  opened in place — a copy, as the rehearsal did.
- S4b-2 (the Sharing page's Sync section, the picker, the registry, the
  space service) and S6 are not built here: the letters D1–D8 of the
  phase record are still out.

---

## 5. Budget

One unit = one Opus 5.5 `reviewer` run at `high` over about ten files
(roughly 80 turns). Leads are counted at about 0.4 units on Opus, 0.1 on
Sonnet; an `implementer` at 1.5; a medium-effort fix reviewer at 0.6;
`qa-runner` 0.2; `docs-writer` 0.1. Fable is 2.5× Opus per token.

| Session | Lead | Agents | Units |
| --- | --- | --- | --- |
| A0 | Sonnet | qa-runner | 0.3 |
| A1a, A1b, A1c | Opus | one reviewer each | 3 × 1.4 = 4.2 |
| A2 | Opus | reviewer | 1.4 |
| A3a, A3b | Opus | one reviewer each | 2.8 |
| A4 | Opus | reviewer (+ the probe) | 1.5 |
| A5 | Opus | reviewer (D3 A) | 1.6 (D3 B: ≈ 3.5) |
| **Night 1** | | | **≈ 12** |
| A6, A7, A8 | Opus | implementer + medium reviewer each | 3 × 2.5 = 7.5 (A7 with two implementers: 9) |
| A9 | Sonnet | qa-runner, docs-writer | 0.5 |
| **Night 2** | | | **≈ 8–10** |
| **Block A** | | | **≈ 20–22** |

The calendar review (`docs/calendar-review-2026-10-26.md`) costs about
the same again (≈ 16 units). **The minimum sync path** when the week is
short: A0, A1a, A2, A3a, A5 and one fix session for the H and M ids
(≈ 9 units); A1b, A1c, A3b, A4 and the lows wait. The order of §2 is the
order of risk, so a night cut short still covered the worst first.

---

## 6. Off the schedule, and deferred

- **S4b-2 and S6** (phase record §4): need the letters D1–D8, the owner's
  yes on the rules deploy, the strays stopped, a Google sign-in typed on
  the Pixel 9 Pro. They follow this review, not the other way round: the
  picker and the Sync section are built on an engine this review has
  read.
- **The rules deploy**: never from an overnight session.
- **A fix that needs a migration** (v44): `→ deferred: needs v44, owner`,
  with the column and the reason; the `drift-migrations` recipe when the
  owner says yes.
- **The pre-existing** `CounterService.importData` `noteIdMap` defect
  (readiness §8): not in scope; one focused fix when the owner wants it.
- Findings struck by the owner (severity `—`) and ids `→ deferred` by a fix
  session are the review's Deferred list; A9's status header counts them.
- **A6's Deferred list**, so A9 counts it without re-reading §3.2: **to A7**
  — R99 (the hook branch of the double conflict copy, needs the hook to
  learn the open note id), R114 (`watch*` subscriptions still bound to the
  closed database after a switch), R125 (turn R106's `contains` into an
  exact copy count once R99 lands), and R128's one sentence beside
  `sync_puller.dart:352`'s "every `SqliteException` but 19" predicate.
  **Left by D4 A** (no H or M fix of A6 opened their files) — R17
  (`content_chunk_dao.dart`: tell an unreadable body apart from an empty
  one) and R43 (`folder_repository.dart`: one recursive CTE for
  `nearestLiveFolderId`). **To the owner** — R116 (R23's guard turns a
  remote rename into a live duplicate pair; recording it means choosing
  between "a rename never loses a term" and a third accepted duplicate in
  the phase record's §8), R118 (R9 is closed as documentation: the undo
  reset on a title-dirty merge and the silent title LWW both stand) and
  R121 (R10's trade — a held write's first retry is now the 5 s debounce
  instead of the 2 s rung, and the app bar shows nothing while a filing is
  stuck).
- **A7's Deferred list**, so A9 counts it without re-reading §3.2: **to the
  owner** — R98 (the far-future remote stamp written verbatim onto the row;
  A5's default (e) says the fix session takes it only with the owner's
  letter, and the three options all change merge semantics, the HLC
  encoding or the no-visible-change rule), R130's **second half** (inside
  one non-initial page a folder whose parent is locally a tombstone and
  whose live envelope is later in the same page is still repaired and the
  move still pushed; it needs a per-page DAO seam, `SyncTableBinding.afterPage`
  + a public `repairMergedParents`, across three files) and R148
  (`watchNoteById` / `watchFolderById` are R114's unrebound twins, and
  `restartableStream`'s controller is never closed — neither is reachable
  today, so building them now is surface for surface's sake). **To S4b-2** —
  R39 (the two bind refusals are hard-coded English `StateError` messages;
  the ARB keys land with the picker that first shows them). **Left by D4 A**
  (no H or M fix of A7 opened their files) — R83 (`event_skip_service.dart`,
  `event_presence_service.dart`, `event_occurrence_service.dart`: filter
  `exportData` to live event ids, or say in the record that the calendar
  deliberately does not). **Declined** — R86 (both branches the id names
  regress) and R66's `label` half (an index this build cannot name has no
  verbatim form on a wire that carries the name). **Needs v44, owner** —
  R67's `counter_dao.dart` share: `counters` and `counter_values` have no
  `updated_at` column at all.

---

## 7. Decisions (D1–D7; the default is marked, the owner flips a letter here)

- **D1 — Nights.** **A (default):** two nights — reviews, the owner reads
  §3, then fixes. B: everything in one chain
  (`-Sessions A0,…,A9 -Commit`); the owner reads the ledger in the morning
  with the fixes already in.
- **D2 — Commits overnight.** **A (default):** night 2 runs with
  `-Commit`: one commit per fix session on `main` after its gate, short
  natural subject, the record in the same commit; night 1 commits the
  record alone per session. B: no `-Commit`; every session ends with a
  ready commit and the tree keeps the gated changes.
- **D3 — A5's reviewer.** **A (default):** the Opus `reviewer`. B:
  `fable-max` (≈ 2.5× that session; the owner writes "D3 B" here and the
  A5 lead reads it).
- **D4 — What the fix sessions build.** **A (default):** every H and M,
  and the L ids whose fix sits in a file the session already edits; the
  other lows `→ deferred` with the file and the intended fix. B: every id.
  C: H only.
- **D5 — Severity `—`.** **A (default):** the owner strikes ids by editing
  §3 between the nights; the fix sessions skip `—`. B: nothing struck;
  the owner reads the fixes in `git log`.
- **D6 — Order of the blocks.** **A (default):** the sync block first, the
  calendar review after; A3b's calendar matrix and A9's calendar suite
  are its first evidence. B: the calendar reviews on night 2 and the sync
  fixes on night 3 (one tree and one `flutter test` at a time rule out
  running them beside each other).
- **D7 — The unbuilt review fixes.** **A (default):** the S4b-1b list
  (A6) and the S5b list (A8) are built in this review's fix passes, each
  as a ledger id with the phase record's own fix text. B: left for S4b-2
  and S6 as the phase record planned.
