# Browser, counters, backup, archives and databases — the review (2026-11-27)

**Status: COMMITTED `bd9d746d` (2026-11-27), on `main`** — one commit of
105 files (code, tests, the skill references) on the owner's word the same
day, without a further test run at his request: it is the tree of §6's
gate, and no file under `lib/` or `test/` changed between that gate and
the commit. Run on
2026-11-27 from one Fable 5.2 lead session on the owner's "you may do them
in your preferred order … focus is quality": two read-only reviews (Opus
5.5) of areas that had had none since the calendar and sync reviews, then
one fix slice per area, each by an `implementer` in a worktree of its own
and each read again by a `reviewer` until that reviewer said it could be
committed. **All of them went in as their last review passed them** (§4):
the whole suite was green on that tree, and so were the saved device
suites and a hand-driven check of the database and restore paths on the
emulator (§6). The records went in with the commit after it.
The reviews filed 40 findings (§2); the fix slices' own reviews filed more
(§4). The decisions the lead took in the owner's absence are §3, each with
the option not taken, so he can overturn any of them. What nobody built is
§5.

Contents: §0 How to continue · §1 The ask · §2 The findings · §3 Decisions ·
§4 The slices as built · §5 Deferred · §6 Gate.

## 0. How to continue

- The fix slices of §4 are **committed as `bd9d746d`** on `main`; this
  record and the others of the session followed in a docs commit. The
  detached worktrees under `%TEMP%\anta-wt-<id>` are where the slices were
  built and reviewed; nothing in them is still needed. What is NOT in the
  tree, and must not be applied without the owner, is kept as patches in
  `build/session-2026-11-27/` (git-ignored): the tag catalog and `#`
  autocomplete (`t1.patch`, `t1b.patch`, `t2.patch`, `t2b.patch` — schema
  v57; `docs/tag-system-roadmap.md`) and the religious calendar's year
  bundle (`s0.patch`; `docs/religious-calendar-roadmap.md` §7.1). Those
  patches were cut against the tree that `bd9d746d` committed.
- One `implementer` and one `reviewer` per slice, each in its own worktree
  (`delegation`); the lead merges by patch and keeps the whole-suite gate,
  run in seven foreground chunks (`verify`).
- A fix that an independent review has not read is not done. §4 marks each
  slice's review state.
- Every finding below was read off a reviewer's report; the ones marked
  CONFIRMED were reproduced by a probe test in that reviewer's worktree,
  the others rest on reading. A line number in a finding is from `8cccd1a5`.

## 1. The ask

The owner asked what could be done with a spare allowance; the lead offered
six items and he took them all, quality first. This record covers two of
them: the **database safety fixes** left open by the settings rework's
closing review (`docs/settings-rework-roadmap.md` §9) and the **read-only
review** of the browser, counters, backup and import/export. The other
four, each in its own record:

- **The religious calendar** — `docs/religious-calendar-roadmap.md`: the
  legal days are in the main tree (§4.6 here), the verified year bundle is
  built and unmerged, and it is parked on three questions only the owner
  can answer.
- **Tags** — `docs/tag-system-roadmap.md`: the first tier turned out to be
  shipped already; the tag catalog and `#` autocomplete in the editor were
  built as patches that are NOT in the main tree, because the catalog
  carries a schema step.
- **Markdown settings on the settings kit** —
  `docs/markdown-settings-rework-roadmap.md`: a designer's spec with
  lettered decisions; nothing built.
- **The folder browser on the UI language** —
  `docs/browser-sheets-roadmap.md`: a designer's spec for the tier it
  starts with (the sheets and pickers that open from the browser), with
  lettered decisions; nothing built.

And one more record the tag work produced: `docs/tag-browser-roadmap.md`,
a spec for where the app lists the tags in use; nothing built.

**Two of the four database faults the lead offered were already closed**
before the session — the shared copy's consistency window and the event
service's empty cache, both by `20d5da9c` — and stood open only in a stale
Deferred list. The settings record carries the correction.

## 2. The findings

State: **fixed** = in the main tree, proven red-first, and read by a
reviewer; **in review** / **in repair** = built, not yet through; **left**
= not built, §5.

### 2.1 Browser (review R1)

| # | Finding | Evidence | State |
| --- | --- | --- | --- |
| B1 | Only the first 20 subfolders of a parent are reachable: `LoadFoldersPaginated` defaults to a page of 20 and nothing dispatches `LoadMoreFolders` | CONFIRMED on the real page (25 folders, 20 rows) | fixed (§4.5) |
| B2 | One app-wide `OptimizedFolderBloc` follows the last-loaded parent: after root → folder → back, a create, a pull-to-refresh, a bulk label and a merged-in folder at the root do not show | CONFIRMED on the real page, five sequences | fixed (§4.5) |
| B3 | A folder delete leaves its notes cached as live in `NoteRepository` until the app resumes | CONFIRMED | fixed (§4.5) |
| B4 | `FolderRepository.deleteFolder` never evicts the descendants it tombstoned (it walks the tree after the delete) | CONFIRMED, masked a tick later by the bloc | fixed (§4.5) |
| B5 | A delete confirm awaits the note count under a loading dialog nothing pops when the read throws or the row unmounts | reading | fixed (§4.5) |
| B6 | An empty list plus a folder-bloc error shows a spinner for good | did not reproduce on the page; the bloc-level half ("Error replaces Loaded") is real | left |
| B7 | `softDeleteFolderWithDescendants` reads the descendants outside its transaction and passes one unbatched `IN (…)` | reading; the race reproduced by the fix's test | fixed (§4.5) |
| B8 | The same cascade stops at a tombstoned middle folder, leaving a live folder a merge put under it | reading | left |
| B9 | `FolderStorageService.deleteFolders` is one transaction and one stamp per folder | reading | left |
| B10 | `NoteDao.updateNotePosition` does not refuse a tombstone (no caller in `lib/`) | reading | fixed (§4.5) |
| B11 | A re-parent through `FolderDao.updateFolder` keeps the old position (no caller passes `parentId`) | reading | left |

### 2.2 Counters (review R1)

| # | Finding | Evidence | State |
| --- | --- | --- | --- |
| C1 | Pinning a counter scrambles the saved order past 32 counters (`List.sort` with a comparator that ties); the per-note list the same | CONFIRMED | fixed (§4.4) |
| C2 | A tap right after a Reset, with a flush in flight, is lost | CONFIRMED | fixed (§4.4) |
| C3 | `CounterService` read from GetIt is the instance on the closed database after an in-process switch (the pause flush, the per-note page, the restore) | reading | fixed (§4.4, §4.2) |
| C4 | `CounterService.getInstance` publishes a half-built instance | reading | fixed (§4.4) |
| C5 | Counter bloc handlers emit from the state they captured before their awaits | CONFIRMED for an edit and a pin; the second review found it still true of both refresh paths | fixed in the third pass (§4.4) |
| C6 | `deleteNoteValue` during a flush leaves the value in memory (unreachable from the UI) | CONFIRMED | fixed (§4.4) |
| C7 | The success snackbar shows when a counter write failed | reading | fixed (§4.4) |
| C8 | `CounterShortcutHandler` inserts at a selection read after its awaits | the handler has **no caller**; the editor counts through `ShortcutApplier` | the dead handler is as it was; the live path's own fault (one counter named twice writes one number twice) was found there and fixed (§4.4) |
| C9 | A counter edit writes the whole captured counter and can undo a pin a sync applied meanwhile | reading | left |
| C10 | An unpinned counter dragged above pinned ones snaps back at the next reload | reading | left |
| C11 | Per-note values first written by taps share the genesis epoch; two devices with different start values lose one side's taps at the join | reading | left — the CRDT's semantics, the owner's |
| C12 | The counter form accepts a step of 0 and turns an unparseable number into 1 | reading | left |

### 2.3 Backup restore (review R2)

The JSON exporter was removed in S18; `BackupService` only restores files
made before, on the onboarding path.

| # | Finding | Evidence | State |
| --- | --- | --- | --- |
| K1 | A restore that fails half-way keeps what it wrote, unbound; a retry duplicates it | CONFIRMED | fixed (§4.2) |
| K2 | One malformed counter wipes every counter, drops later ones and reports success | CONFIRMED | fixed (§4.2) |
| K3 | A restore loses the manual order of sibling folders (the archived `position` is ignored) | CONFIRMED | fixed (§4.2) |
| K4 | An event linked to a note the archive does not carry keeps a link to an id that exists nowhere | CONFIRMED | fixed (§4.2) |
| K5 | Per-note bar and currency rows of such notes are written under their archived ids | reading | fixed (§4.2) |
| K6 | Onboarding calls `setState` after an await unguarded; a non-text file reads "import failed" | reading | fixed (§4.2) |
| K7 | Restored language and theme do not apply until the next launch | reading | fixed (§4.2) |
| K8 | `BackupService.getInstance` publishes before its await | reading | fixed (§4.2) |
| K9 | Folder and note dates are written without a zone, so a restore in another zone shifts the instants | reading | left — a format decision |
| K10 | The restore writes raw settings keys | reading | left |
| K11 | A backup from a newer build is never refused (none can be made any more) | reading | left |

### 2.4 Archives — notes and folders exported and imported (review R2)

| # | Finding | Evidence | State |
| --- | --- | --- | --- |
| A1 | A Markdown round trip strips the note's leading whitespace (`trimLeft`) | CONFIRMED | fixed (§4.3) |
| A2 | An archive round trip loses the folders' manual order and each folder's `updatedAt` | CONFIRMED | fixed (§4.3) |
| A3 | One non-UTF-8 file stops the import half-way and leaves the part behind | CONFIRMED | fixed (§4.3) |
| A4 | A title collision at the column limit aborts the whole import | CONFIRMED | fixed (§4.3) |
| A5 | On desktop an export is deleted as soon as `share()` returns | reading | fixed (§4.3) |
| A6 | An exported untitled note carries the unlocalised heading "Untitled" and comes back titled so | reading | left |

### 2.5 Databases (the settings record's §9, review of 2026-11-01)

| # | Finding | State |
| --- | --- | --- |
| D1 | `deleteAllData` deletes the device id before a database that then refuses, so the install gets a new identity | fixed (§4.1) |
| D2 | Optimize opens through `AppDatabase.getInstance()`, which switches the app when the stored name has moved | fixed (§4.1) |
| D3 | A switch writes the active name before the restart dialog, and the next `getInstance()` from anyone switches under it | fixed (§4.1) |
| D4 | A failed whole-table read publishes an empty catalogue (categories, templates; also saved filters, saved views, vocabularies) | fixed (§4.1) |
| D5 | The shared copy's consistency window | was closed by `20d5da9c` |
| D6 | The rename of the open database in place | fixed as close → rename → restart (decision J); its second review confirmed two data hazards in the first build, the repair closed them and the third review passed it (§4.1) |

## 3. Decisions the lead took (the owner was away)

Each is reversible. "Not taken" is the option he would pick to overturn it.

| # | Decision | Not taken |
| --- | --- | --- |
| A | **A restore is all or nothing for a database error, refuses a file whose folders or notes are malformed before anything is touched, and skips a damaged row of an optional section** (counters, calendar, per-note settings), saying how many it skipped. | Keep partial restores; or refuse the whole file for any damaged row (the first build did, and a review showed one bad counter then cost the notes). |
| B | Restored sibling folders keep their archived order among themselves; they are still appended after what is there (the recorded rule). | Leave list order. |
| C | A link or a per-note setting that points at a note the archive does not carry is dropped, also when the archive carries no note at all. | Keep the archived id. |
| D | An archive's folders are recreated in the order of their entries, and `_folder.json` gains an optional `updatedAt`; `archiveVersion` stays 1 (an older build ignores the key, an older archive imports as before). | A version bump; a `position` field. |
| E | Every temporary export is written into a folder of its own under `anta_exports/`; on desktop it is left for the launch sweep, because the share sheet may still be reading it. | Delete when `share()` returns (the old rule, which could also hand one note's text to another note's share). |
| F | A file an import cannot read is skipped, counted and named in the snackbar (one new string). | Decode it as Latin-1 (a guess: wrong for Romanian text). |
| G | A title longer than the column is cut on a whole character and the note's body keeps the whole title. | Refuse the note; cut silently. |
| H | A failed counter write says so with the existing "Couldn't save the change" (`categoryChangeFailed`); a counter's own key is owed. | A new string now. |
| I | **A switch that asks for a restart stores the name for the next launch only** (`DatabaseManager.activateAtNextLaunch`): the Databases page and an alarm of another database. The process stays on the database it has open; `setActiveDatabaseName` stays the switch-now call the sync download and onboarding's restore from a file use (the first build moved onboarding too, and a review showed the app then finished onboarding on the empty launch database). A name with no file is refused. | The record's "switch pending" latch inside `AppDatabase.getInstance` (it leaves every reader of the active name ahead of the open database); a second persisted key applied at launch. |
| J | **Renaming the database that is open closes it first and asks for a restart** (one new string). No file is renamed under a live connection on any platform. | Rename in place (what Android did, with every singleton still holding the old name); refuse to rename the active database. |
| K | `deleteAllData` deletes each database before its own sidecars and the device id last; a test pins that SQLite itself drops a `-wal` beside an empty database. | Sidecars first (the first build; it could strand a database without its last commits). |
| L | A failed whole-table read keeps the cache and publishes nothing. | Publish empty (the old rule); fail the caller. |
| M | A parent's folders load whole (a ceiling of 10,000). | Page them (select-all and drag-reorder assume the whole list). |
| N | The Romania profile gains 2 January, and 6 and 7 January from 2024 (the religious calendar's D6, built here as its S1). | — |
| O | **A pushed folder page draws its own state only**: its header and a loading spinner for its first frames, never its parent's rows (which were tappable and opened the parent's folders). | Reading the child's rows before the push (the tap then waits for the read); a spinner that appears only after a delay (a new primitive). |
| P | **A number a counter shortcut writes into a note is the service's own count**, each token waiting for its own; in a new note with no id yet the editor keeps the presses and files them on the note when it is created. No note is created early for a counter press. | Creating the note at the first press (an empty note if the person then leaves); refusing the shortcut until the note exists. |

**Two recorded rules were overridden.** The settings record's §5 says the
delete-all path is "never reordered", and its §9 marks the switch flow
"must-not-change". The lead named both before starting and read the
owner's "you may do them" as his yes. If that was not what he meant, K and I
are the two to reverse.

## 4. The slices as built

### 4.1 Databases — in the main tree; reviewed three times; the third review: fit to commit

`lib/database/database.dart`, `lib/services/database_manager.dart`,
`lib/pages/database_settings_page.dart`,
`lib/controllers/alert_ring_controller.dart`, `lib/pages/onboarding_page.dart`,
`lib/services/kept_share_notices.dart`, and the five services of D4.
Suites: `test/database/delete_all_data_test.dart`,
`test/services/database_manager_next_launch_test.dart`,
`test/services/failed_read_keeps_cache_test.dart`, and cases added to the
Databases page suite and the alarm controller suite (none changed).

The first review found no wrong-database write and no rule breach, proved a
pin per claim by reverting its guard, and confirmed two faults: the first
delete order could delete a `-wal` beside a database that then survived, and
two services republished a closed database's rows after a switch. Both are
fixed, with decision J and the kept-notices list following a rename — the
lead's own fix pass, written without a second reader.

**The second review read that fix pass and confirmed, by probes, three
faults in it.** They are repaired, and the third review read the repair
(both below).

- **A database call that lands while the open database is being renamed
  writes into an empty database left under the old name.** After the close
  and the file's move, the stored name still says the old one until the end
  of `renameDatabase`; any `AppDatabase.getInstance()` in that window opens
  the old name, SQLite creates it empty, the caller writes there, and the
  rename reports success. An alert reconcile, a resume or a sync push is
  enough.
- **A rename onto a name that still has a leftover `-wal` replaces the
  renamed database's contents with the deleted one's**, with the integrity
  check still passing. The slice's own delete order leaves such leftovers
  and its comment called them safe; that holds beside an empty database
  (pinned against the shipped SQLite) and not for a file that arrives by
  rename. `deleteDatabase` could leave one before this session too.
- **Onboarding's restore from a file left the app on the launch database
  until the restart** — a regression of the slice's first version, which
  moved that pinned path to `activateAtNextLaunch`. The review filed it as
  the "onboarding completed" flag landing in the wrong database; its third
  round showed HEAD writes the flag to the same place, so the flag is an
  older fault and the regression was the database the app stayed on.

Also from that review: a rename that fails after the close leaves the page
saying "couldn't rename" with the stored name already moved; `deleteAllData`
stops on a file SQLite removed between the listing and its delete; and the
page suite's pinned delete-all case failed once in a whole-file run, because
the file-by-file deletes last long enough for the loading dialog's exit to
overlap the check.

**The repair (an `implementer` in `%TEMP%\anta-wt-s1`; in the main tree, its
suites green there).** `AppDatabase.whileClosed(name,
work)` replaces `closeIfOpen`: it takes a gate that every `getInstance`
waits on — checked after that call's last await, with nothing awaited from
there to the memo — closes the database when it is the open one, runs the
caller's work, and only then lets callers through. `renameDatabase` does
everything inside it: the target name's `-wal`, `-shm` and `-journal` are
removed first, the `.db` moves, and from the move on nothing throws — a
sidecar, the sync claim or a name that does not follow is logged, and the
call still answers whether the database was closed, so the page asks for
the restart. One pinned assertion changed with that: a sidecar that failed
to move used to throw once the names had followed. A failure before the
move rethrows, and the old name is opened again. `deleteAllData` runs its
listing and every delete in one turn of the event loop and passes over a
file already gone; the lead then moved its folder lookup above the close,
so nothing is awaited from the close to the last delete — an edit no test
pins. Onboarding's restore is back on `setActiveDatabaseName`, the file as
it was at HEAD. Seven new cases ask for the database at each point of a
rename, and each fix was seen red with its guard reverted.

**The third review: fit to commit.** Each fault of the second is closed on
the real code, by probes rebuilt for it: twenty callers writing through a
rename of the open database all waited, ended on the renamed file with
their writes in it, and nothing was created under the old name; a leftover
`-wal`, `-shm` and `-journal` under the target name are all removed; a
failure before the move leaves the names alone and every waiter on one
instance under the old name; a failure after it still asks for the
restart. Nothing awaited inside the section asks for the database (every
reset handler is synchronous and unawaited, the registry and the kept
notices are preferences only), two renames at once queue, and a throw
inside the section releases the gate. Three guards were removed in turn and
each turned its tests red; the three suites ran five times each without a
flake, the page suite's delete-all case among them. It also corrected its
own second round: **the onboarding flag was never a regression** — HEAD
writes it into the database being left too, because the settings service
is already bound to the launch database when the restore runs. What the
first build did change there was which database the app stays on, and that
is back as it was.

What it left, all low, none built:

- **R1** — `whileClosed` tells "open" from the memo alone, so a rename of a
  database that a switch is still closing does not wait for that close. On
  Windows it fails before anything moves (run: the checkpoint is refused as
  locked); on Android, by reading, the file can move under the closing
  connection, which leaves a `-wal` whose pages are already in the file —
  harmless at the next open. Reachable only while a sync download or the
  launch's recovery is switching, neither of which has a page on screen.
  Fix shape: await an open in flight before judging.
- **R2** — the stored name is written after the move, and a write that
  fails is logged (one that answers `false` is not even that — as before
  the session): the next launch then opens the old name, SQLite creates it
  empty, and the person finds an empty app with their data listed under the
  new name. It needs a failed preferences commit. Fix shape: move the file
  back and fail the rename.
- **R3** — a file SQLite deleted while another handle still held it answers
  "access denied" on Windows, not "not found", so delete-all can fail on
  it; the device id stays, so it is a spurious failure and nothing worse.
- **R4** — one of the seven new cases passed with the gate removed (at its
  step the names have already moved). Closed by the lead: the step cases
  now also assert that the caller was still waiting while the section ran,
  and all five turn red with the gate's loop taken out of `getInstance`
  (run).

Unpinned, by that review's list: the lead's reorder in `deleteAllData` (it
could not be told apart in a test: both orders pass), two concurrent
renames, the waiters racing the reopen, a throw releasing the gate, and
the `-shm` and `-journal` halves of the target sweep — each proven by a
probe that was not kept as a test.

To record, older than the session: after a restore in onboarding from a
file whose settings carry no onboarding flag, the next launch shows
onboarding again, and restoring the same file a second time adds another
copy of the database.

Left by the reviews, not built: an alarm whose database is gone now does
nothing on "Switch to …" where it used to create that database empty — it
needs a sentence, a new string and the alarm page's own tests (§5).

### 4.2 Backup restore — in the main tree (three passes); reviewed three times

`lib/services/backup_service.dart` (its restore rewritten: a shape check
before the unbind, every row write in one transaction),
`CounterService._importData`, `lib/pages/onboarding_page.dart`,
`lib/main.dart` (`_onOnboardingComplete` reloads the app settings).

The review restored one rich v8 archive with the old code and the new into
fresh databases: table for table the same, apart from the three intended
drops (decision C). It confirmed one regression — one damaged counter
detail or holiday row now failed the whole restore — which decision A
answers and the fix pass builds; a failure after the commit reported as a
failed restore; and a rewritten test that no longer pinned the outbox clear.

The second review ran about 120 damaged-file variants (every field of every
optional section replaced by an object, null, a number, a string, a list; a
duplicate row; a row that is not an object; a section of the wrong type)
through the fix pass: **none rolled the restore back and the notes landed
every time**, and the rich archive still restores table for table with
nothing skipped. Two gaps, which the third pass builds: **the skipped count
is right only for counter rows, holiday rows, non-object rows and wrong-type
sections** — a damaged event, alert, template, preset, view, digest,
vocabulary, occurrence, presence mark or skip row is dropped with no word
to the person; and two inputs (`counters: '[1,2]'`, `counterData` with no
`counters` key) still delete the counters that are there and restore none.
Left on purpose: a failure of the outbox clear or of the floor write after
the commit still reports the restore as failed — the floor is what keeps
restored rows from winning over the cloud copy at the next bind.

One new string, `importSkipped` (the restore's own; the archive import has
`importSkippedFiles`).

The third pass: every import the
restore calls now answers how many rows it skipped — twelve services'
`importData` went from `void` to `int` — and the restore adds them up; a
test restores, for each of sixteen optional sections, one valid row beside
its damaged ones and finds the valid row landed and `skipped` equal to the
damaged count. A row whose parent was skipped is not counted itself. An
absent `counters` key or a list from which no row survives keeps the
counters that are there; an empty list still replaces them. A setting whose
value is a string, a number or a flag is written as text; anything else is
skipped and counted. Noted by its implementer and not changed: the alerts,
skips, descriptions and presence marks of a skipped event still land, under
an id no restored event holds.

The third review found nothing in that pass that changes what a well-formed
backup restores — the rich archive lands table for table with `skipped` 0,
and every exporter in the history wrote settings as strings, so the typed
read writes what was written before — and no variant, in about 120, where
the count disagrees with the rows dropped. By its reading the orphans of a
skipped event do no harm: the scheduler plans from the events it holds, so
an alert under an id no event has never rings. Three things it left to
judgment, none changed:

- a damaged built-in category counts although the seed puts the built-in
  back — what the person had made of it is lost;
- a second vocabulary under an id already restored counts one, as a second
  counter does (now said in the import's doc comment and pinned by a row of
  the table test), while a duplicate row of the other sections is taken
  without a count — an archive the app wrote never carries one;
- a junk row whose every field is a string lands uncounted, because it is
  readable.

It named one weak pin, closed by the lead: the case "a step after the
commit that throws does not stop the steps after it" now asserts that its
throwing step ran before the label style's, without which it proved
nothing. And it listed four guards as unpinned, which they are not: a
vocabulary's per-item `try` and the count in the holidays' insert `catch`
each turn their table case red when removed (run), the settings row of
that table carries a `null`, and the profiles' unknown-category drop is
pinned twice — the restore's own filter by the count, the service's by
`category_profile_service_test.dart`.

### 4.3 Archives — in the main tree (three passes); reviewed three times

`lib/services/import_export_service.dart`, `lib/utils/text_fit.dart`
(new), `lib/constants/temp_file_names.dart`, the import state and the
browser's import snackbar, one new string (`importSkippedFiles`).

The second review tried every way a cleanup or the launch sweep could
delete something that is not ANTA's own export (a link, `..`, a near-miss
name, an older build's files, the live database) and found none; both
guards fail their tests when reverted. Its seven small points are built in
the third pass: a folder named by one enormous character, a title taken
from a file name (the body now opens with the whole name), `.` and `..`
path segments dropped before the tree is rebuilt, a suffix longer than the
limit, and two tests. The same pass gave the conflict copy's title
(`lib/services/sync/conflict_copy_title.dart`) and the editor's numbered
title (`optimized_note_editor_page/remote.dart`) the one cut in
`lib/utils/text_fit.dart`: the editor's could leave half of a surrogate
pair in a title that is then stored and synced.

The skipped-files line at text scale 2.0 on 360 × 800, measured in the test
font (wider than Roboto), bar height without / with the line: de 244 / 484,
ro 244 / 444, en 204 / 364, after the copy was shortened (it was 644 in
German). No overflow.

**The third review found nothing that loses or changes note text.** It
compared the old and the new title cut of both outside callers over 156
titles in three languages (they agree everywhere except where the old cut
split a character), ran every path shape through a real zip, and proved a
pin for each item by reverting it. Of its five low points the lead built two
one-line guards afterwards, with a test proven by a revert: only the entry
written as `manifest.json` is the manifest (a path that merely normalises to
that name, `x/../manifest.json`, had become one), and the loop that rebuilds
missing folders stops at a path that is its own parent again. The other
three are in §5.

### 4.4 Counters — in the main tree (four passes); reviewed four times; the last two reviews: fit to commit

`lib/services/counter_service.dart`, both counter blocs and their events,
both counter pages, `lib/main.dart` (the pause flush).

The review found no new lost tap and no `done` that can hang. It showed the
slice's claim about the blocs was too broad (C5), one small regression
(Reset then Reset on a counter with no row now writes one), and that the
shortcut-handler change runs nowhere (C8).

The fix pass answered those; `done` on the four events became a
`Completer<bool>` (written / nothing attempted / failed), and
`AppNavigator.toCounterPerNote` awaits the service before it pushes. The
second review then confirmed, with storage right in every sequence it
tried:

- **A shortcut that names one counter twice writes the same number twice
  into the note while the counter counts two** (`"Set 1 / 1 "`, counter at
  2) — pre-existing, on the editor's real path
  (`optimized_note_editor_page/toolbar.dart`): each token reads the bloc's
  state before the previous increment has emitted.
- **With a per-note value picked on a card, a refresh that overlaps a tap
  or a Reset on the loaded note still leaves the page on the older value**:
  two cold reads of one note overlap after a `reload()` and the bloc is left
  holding a map later taps never reach.
- **The fix pass made a per-note refresh read each listed note separately**
  — one query per note, on every sync pull.

The third pass built all three. A shortcut's `{cN}` token now takes its number from the
service's own count through `CounterBloc.shortcutValue`, each token waiting
for its own, so two tokens on one counter write 1 then 2; the old code read
the bloc's state plus a step. The service reads a cold note once however
many callers arrive, and a read a reload overtook is not filed, so a
refresh never holds a map later taps do not reach. The per-note page's
refresh is one query whatever the number of notes (it was one per note),
read inside the flush queue with the pending taps laid over the rows. A
failed read in a refresh or a context switch is caught and carried as the
state's error. The counter picker inserts nothing when nothing was counted
(it wrote "0"). C8 stands as recorded: nothing calls
`CounterShortcutHandler.execute`; its change is unpinned.

**The third review: fit to commit.** It drove the shortcut through the
editor's own path minus the widget (`A1 B2`, `C3 D4`, `R5,R6,R7`, `K7 I8
K8`, cold and warm, global and per-note), reran its timing sweeps — every
pair right where the second round had three to nine in sixteen stale — and
found no lost tap and nothing that can hang. It confirmed one older fault
on the real path and one gap in the tests, which the fourth pass built:

- **The first press of a per-note counter's shortcut in a brand-new note
  was not counted** (older than the session; the third pass had changed
  which wrong number it wrote). A new note has no id until its first text
  lands, and a shortcut resolves its tokens before it inserts anything. The
  editor now keeps the presses made before the id, net of decrements, the
  bloc answers start + step × presses for them, and the listener that
  adopts the id files them on the note as ordinary taps in the same turn.
  `NoteSaveCoordinator` is untouched: no note is created early.
- **The fix that puts the right number in the note was pinned by no test**
  — with the toolbar swapped back to its second-pass version every suite
  passed. The editor suite now drives the real page's shortcut and picker
  with a real bloc over the real service; seven of its nine cases fail
  against the old toolbar.

**The fourth review: the pass may merge** (it is in the main tree). Its
probe, start 1 and step 2, presses before the id, a mixed press with the id
landing mid-way, one after: `Set 3, Set 5, Dec 3, Keep 3, Set 5, G1 L7,
Set 9`, the service and the row at 9 — where the same flow had written
"Set 1", "Set 1", "Set 2". The check that replaced the reload generation in
the service (a read files its map only while it is still its note's read)
covers everything the generation did. Left, both low:

- **A tap that is waiting on a note's cold read when that note is removed
  from the per-note page brings its row back** at start + step (new with
  the fourth pass: the delete drops the read, the tap reads again after
  it). The two must land within one database read. Fix shape: the delete
  waits for the read in flight instead of dropping it, so a tap issued
  first counts first and is then removed.
- **One press in a new note and back before the create's insert has
  answered**: the page is gone when the id arrives, so the press stays
  uncounted while the note keeps its number. The first press itself starts
  the create, so the window is the insert's tens of milliseconds. Fix
  shape: file from the create's completion, through a future for the new
  id that the exit path awaits.

### 4.5 Browser — in the main tree (four rounds); reviewed four times; the last review: may merge

Merged, backed out the same day, repaired, reviewed again and merged again.
The slice fixed B1–B5, B7 and B10 with tests that failed first, and its
first review confirmed a regression in the bloc's new contract: **after an
import from a subfolder, that page stops showing its own creates, renames,
labels and deletes**, because a page underneath moves the one bloc to the
root. The lead backed the slice out.

The repair (`%TEMP%\anta-wt-d1`): a page that another page route covers
neither loads nor refreshes and marks itself stale instead (a dialog or a
sheet does not cover it); on its return it always re-aims the one bloc at
its own parent in its own order, quietly — no Loading state; and the bloc
counts its aims, so a read a later aim overtook emits nothing.

**The second review: the slice may return.** It rebuilt the first pass
beside the tree and ran the failing sequence alone on both: the regression
was real (the repair's implementer had called it a harness artifact, and
was wrong) and is gone. All five findings of the first review are closed,
no path skips a covered load without marking the page stale, and no
sequence strands the page in front on a spinner. What it found, none of
it lost data or wrong rows that stay:

- **A covered page that never loaded shows a spinner for the first frames
  of its return** — the first back press after a launch restored into a
  nested folder (new with the repair's gate).
- **Every pop from any page costs a folder read and a rebuild** — one where
  there were none; two on the way back from a new note (new, cost only).
- **On a return that reloads, the notes go back to their first page and
  the count label loses its notes half while they load** (the label is
  new; the lost scroll is older).
- Older than the slice and seen again: a note moved into a covered parent
  stays hidden after the pop; a pushed folder page draws its parent's rows
  for its first frames.
- By reading: a page uncovered by a route removal instead of a pop never
  re-aims (only for a route the observer did not record).

**Rounds three and four built those, and the fourth review passed them**
(in the main tree):

- A page built under another one reads its first rows through answer-only
  events (`PeekFolders`, `PeekNotes`: the bloc answers a `Completer`, emits
  nothing and moves no aim) and draws them until its own state arrives. The
  third review caught the first version of this still showing a spinner —
  its test had passed only on another case's leftover state — because a
  bloc still in Initial was taken for the page's own; round four fixed that
  and gave the case blocs of its own. The reviewer's probe then drew rows in
  every frame of the reveal, three pages deep.
- A pop refreshes only when the page was marked stale or the bloc is aimed
  elsewhere (`isAimedAt`): a plain pop reads nothing, as before the slice.
- On a return the notes are re-read at the depth the page had them
  (`ReturnToNotes`), straight to Loaded: 45 of 45 notes, the scroll offset
  and the count label kept in every frame — better than before the slice,
  where the offset was lost — and a note moved into a covered parent now
  shows. A return that another folder's load overtook emits nothing.
- A pushed page draws its own state only (see decision O below).
- The lead took the fourth review's one tested line with the merge: the
  cold-start kick asks the bloc whether it is Initial, not the state the
  builder holds, so a page revealed from a stack built in one frame does not
  load a second time through Loading.

**One visible difference to name (decision O):** a folder page that is
pushed shows its header and its loading spinner for its first frames (two
in the test) until its own rows arrive. Before the slice it showed its
parent's rows for those frames — tappable, and a tap opened one of the
parent's folders. Not taken: reading the child's rows before the push (the
tap would then wait for the read), or a spinner that only appears after a
delay (a new primitive).

Left by the fourth review, all low: a builder re-created while its page is
covered draws an empty count label until the page's own state returns (the
rows stay); `LoadNotesPaginated` itself has no guard against being
overtaken, as before the slice; the folder half of the covered-answer drop,
the count label in reveal frames and `sortOrder:` on the reorder-success
refresh are pinned by no test (the reviewer's probes for them are in the
session's scratchpad, not in the suite).

### 4.6 The Romania profile's January — in the main tree

`lib/constants/public_holidays.dart`, two strings in the three ARBs,
`test/constants/holiday_seeds_romania_test.dart`, three cases in the alert
planner's suite. Not reviewed by an agent: fourteen lines of `lib/`.

### 4.7 The last three singletons — in the main tree; reviewed once: may merge

`lib/services/dev_options_service.dart`, `markdown_bar_service.dart`,
`note_position_service.dart`, and one new suite each
(`test/services/*_service_instance_test.dart`, thirteen cases, all red on
the old code: `LateInitializationError`, an unloaded bar, a second caller
bound to the database being left). Each `getInstance` now publishes only a
whole instance — the `SettingsService` shape the skill names — so the five
the skill listed as "to close when one is touched" are all closed. The bar
also counts its own resets, because `BackupService` resets it after a
committed restore with no database switch.

The review found no crash, no data from the wrong database and no hang:
two and ten concurrent first callers get one whole instance, a failed open
publishes nothing and the next call opens again, a switch in every pass
gives up as `SettingsService` does, and no caller relied on the early
publish (the editor's first frame gains no wait). Left by it, all low or
older than the slice:

- **After a restore the bar's restored profiles do not show until the
  next launch** (older; found by reading): `BackupService` resets the
  bar's static, but the instance GetIt registered before `runApp` is the
  one every page reads, and it is the pre-restore one. The comment "the
  bar re-reads on its next open" is not true of the running app. The same
  holds after a switch-now.
- A `reset()` during the bar's open makes two loads run side by side
  (both callers get the same instance; the writes are identical).
- A load whose database is closed under it by a switch throws to its
  waiters instead of starting over — better than before, where the
  half-built instance stayed published.
- `DevOptions.instance` keeps the previous database's options after a
  switch to one that stores none (older).

### 4.8 One pre-existing flake

`test/services/sync/sync_unseen_write_test.dart` asserted that a log line
did not contain `e1` while the line held a random note id; one id in eight
contains those letters. It now asserts on the table's name.

## 5. Deferred

Each with what reopens it. The low items each slice's last review left are
written with their slice and not repeated here: §4.1 (R1 to R3, and the
onboarding flag), §4.2 (three judgment calls on what counts as skipped),
§4.4 (a tap racing a note's removal; one press and back within a create)
and §4.5 (the count label of a re-created builder; three unpinned guards).

- **The restored Markdown bar shows only after a relaunch** (§4.7's first
  item; older than the session): the fix is the bar's readers resolving
  the service after a reset rather than holding GetIt's first instance.
- **The counter picker says nothing when it wrote nothing** (the counters
  not loaded, the counter gone, a count that failed): it no longer writes
  "0", and it does not tell the person either. It needs a string.

- **B6, "Error replaces Loaded"**: after a failed folder write the list
  keeps its rows but the bloc stays on Error until the next refresh, and
  the notes' infinite scroll stops meanwhile. Needs a decision on how a
  failed write is said (a snackbar from a listener is a visible change).
- **B8, B9, B11** (the folder cascade under a tombstoned middle folder;
  `deleteFolders` as one transaction; a re-parent keeping its position).
- **C9–C12** (an edit undoing a remote pin; a drag above pinned counters;
  the genesis epoch; the form's step 0). C11 is the CRDT's meaning and
  needs the owner.
- **Pin then unpin does not return a counter to where it was** — as before
  the session; whether it should is a product question.
- **A counter's own failure string** (decision H).
- **K9–K11, A6** (zone-less dates; raw settings keys in the restore; a
  newer backup; the unlocalised "Untitled").
- **Three edge cases of the title cut**, all hand-made inputs (the archive
  slice's third review): a title of one letter followed by one enormous
  character keeps only the letter (`TextFit.cut` falls back to code units
  only when nothing fits — append what fits of the character that does
  not); a name that opens with hundreds of spaces is cut to blanks (trim
  before the cut, or treat a blank cut as empty); a Windows absolute path
  in a zip becomes a folder named `C:`.
- **A restore from settings** would need every service's write chain
  drained before the transaction; today only onboarding calls it, where
  nothing else writes.
- **Alarms armed before a database is renamed keep the old name for good**
  (pre-existing; found by the second database review, which read
  `AlertScheduler._assignOsIds`: a registry row keeps its OS id whatever the
  name, and the arm signature carries no database name, so nothing re-arms
  them — not at the restart either). When one rings it is treated as another
  database's alarm: the page offers "Switch to <old name>", which is now
  refused and does nothing (§4.1) where it used to create that database
  empty; "Open event" is not offered; and an alarm whose Stop should remove
  its event does not. Fix shape: the database name in the arm signature, or
  a re-arm of everything on the first pass after a rename. An earlier line
  of this record said the reconcile heals them; the lead had read only the
  cancel loop, and it was wrong.
- **Closed here, not deferred — one editor test that hung now and then**
  (older than the session; seen on 2026-11-14 and again in this session's
  gate): `test/widgets/optimized_note_editor_page_test.dart`, "a change
  merged from another device (record §3.9) a save already in flight when
  the merge arrives cannot hide it…". An investigator reproduced it alone
  (3 runs in 13 on the loaded machine) and on demand: **the test's fault,
  not the page's.** The page files the conflict copy in a transaction it
  opens in the test's fake zone, which advances only on pumps; the test
  read the database right after a counted settle, Drift held that read
  behind the open transaction, and nothing pumps while a real read is
  awaited — a deadlock with no bound to hit. The page ended correct in
  every run (the row with the user's text, one copy with the merged text,
  the page clean), and no ordering was found that strands unsaved text.
  The case now waits for the page's own sign that the copy is filed before
  it reads: 40 runs of 40 alone on the same machine. Left, by reading: the
  short window after the in-flight save lands and before the copy is
  filed, in which a process death would lose the other device's version on
  this device — only where the merge engine stood back for the page, a
  path this test does not drive.
- **What no device has shown yet.** The saved suites passed on the
  emulator (§6), but they are thin exactly where this session worked: the
  browser suite is three flows and never stacks folder pages or returns
  from a restored one; the settings suite opens the Databases page and
  reads its buttons, and drives no switch, rename, optimize or delete-all;
  nothing presses a counter shortcut. A real share sheet on desktop and
  predictive back over a restored stack were not seen either. §6 says what
  a hand-driven check on the emulator added.

### 5.1 The docs this work owed — written in the same session

- `.claude/skills/drift-migrations/SKILL.md`: the sentence that listed
  five singletons still assigning `_instance` before their await now says
  all of them publish whole (§4.2, §4.4, §4.7), and a new section holds
  the rules for switching, renaming and deleting a database.
- `docs/settings-rework-roadmap.md` §9: the optimize, rename, delete-all,
  switch and failed-read items each carry an "Amended 2026-11-27" note —
  built and reviewed that day and committed as `bd9d746d`.
- `.claude/skills/anta-context/references/feature-areas.md`: the restore's
  rule, the counters' cache and shortcut rules, and the database manager's
  switch, rename and delete-all. `references/import-export.md` was updated
  by the archive passes.

## 6. Gate

The whole suite, in seven foreground chunks, on the main tree at 15:00 on
2026-11-27, with every slice of §4 in it as its last review passed it:
**`+19381 ~17`, no failure** — services `+3698 ~5`; every directory but
widgets and services `+8563 ~9`; the widget suites in three parts `+2536
~1`, `+2105`, `+2290 ~2`; the editor page suite in two `+149`, `+40`.
`dart analyze lib test`: no issues. `untranslated.txt`: `{}`. The logs are
in `build/session-2026-11-27/logs/` (git-ignored; `final2_*`).

Earlier runs the same day: at 13:19, before the singleton slice (§4.7),
`+19368 ~17`, no failure — the tree the first device pass and the
hand-driven check below ran on; at 11:45, before the counters' fourth pass
and the browser's last two rounds, `+19337 ~17`, no failure.

One run in between stopped at the timeout on the editor suite's known
hanging case; it is explained and repaired in §5 ("Closed here, not
deferred").

**The device pass**, on `anta_qa_1` (`emulator-5556`), one guest, nothing
else running on the machine, the QA build made from the final tree at
15:00 (`8cccd1a5`, dirty — the tree of the figure above): **browser 3/3,
settings 21/21, calendar 35/35, alerts 5/5 — every flow green, none
flaky, none recovered**, and no runtime error in any flow's capture of
the run log, logcat and the agent. The reports are under `build/qa/pass/`
(`browser_20261127_150121_…`, `settings_20261127_150157_…`,
`calendar_20261127_150754_…`, `alerts_20261127_152108_…`). The same four
suites had passed the same way on the 13:20 build, before the singleton
slice (`…_132101_…` to `…_134042_…`). `sync`, `sync_pair`, `share` and
`alerts_pair` were not run.

**A hand-driven check on the same guest, on the 13:20 build**, for what
the saved suites do not drive (shots in `build/qa/shots/`, named `20261127_13…_A…`
to `…_D…`; `qa errors` clean after each):

- **Renaming the open database, as built.** Rename `qa` to `renamedqa`: the
  dialog "Restart required / The database was renamed. Please restart the
  app to continue. / Exit App", which stayed through system back (both
  ways the harness sends it) and taps outside it. After Exit App and a
  start from the launcher: the same three folders with the same counts,
  one database listed, `renamedqa`, active, and nothing under the old
  name.
- **Switching, as built.** A second database created (no restart, a
  snackbar), then switched to: a confirm, then "Restart required / Please
  restart the app to use the new database."; the page behind it still on
  the first database. After Exit App and a start: the second database,
  empty, active; the first still listed.
- **A stack restored at launch, then back, as built.** Root → Training →
  Week 1, the app relaunched: it reopens in Week 1. Back: Training's rows
  and "1 folder" in the shot taken at once and in the one a second later,
  no spinner; back again: the root's rows and "3 folders", the same.
- **Optimize.** On the empty second database: "Reclaimable: 0 B", then the
  snackbar "Already compact" — while the Statistics card's Size fell from
  1.26 MB to 364.0 KB (Size counts the `-wal`, Reclaimable counts free
  pages, and Optimize ends on a checkpoint). Older than the session; the
  page says "compact" as its own number shrinks.

Seen on the way, older than the session, for the owner: "Exit App" leaves
the process alive (`SystemNavigator.pop` closes the screen only) — the
next start is a new engine in the old process, and both flows above came
up on the right database; a database's row shows the size of its `.db`
alone while the Statistics card adds the `-wal` (364.0 KB beside 1.87 MB
for one database); the page's caption says "Creating or switching
databases will restart the app", and creating does not. Not driven:
Optimize with space to reclaim, delete-all, a counter shortcut, predictive
back.
