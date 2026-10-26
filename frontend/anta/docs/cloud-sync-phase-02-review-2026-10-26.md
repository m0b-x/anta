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
pass browser -d emulator-5556`, `qa pass alerts -d emulator-5556`, each in
the background, one `--only` rerun per red; the browser suite's
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

- (nothing has run)

### 3.2 Findings

Shape in §0.6. The night-1 summary line goes first when A5 writes it.

- (none yet)

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
