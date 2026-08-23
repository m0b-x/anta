# Calendar performance roadmap (2026-08)

**Status: Phases 0, 1 and 2 shipped (2026-08-20). 3.1, the agenda half of 3.2,
and the debounce half of 4.1 shipped (2026-08-21) via
[calendar-anchor-perf-regression-2026-08.md](calendar-anchor-perf-regression-2026-08.md).
The rest of Phases 3-5 planned.**

This started as a review, not a changelog. Every finding was verified by reading source;
no profiler run backs the timing estimates yet — Phase 0 exists to produce those numbers
before any fix is judged. Items are grouped into phases by risk, not by subsystem.

## What shipped, and where the plan was wrong

Phase 0 and Phase 1 were re-verified against source before implementation. Six claims did
not survive that pass; they are corrected in place below, and recorded here so the next
session does not re-derive them:

1. **1.1's `buildWhen` would have shipped a stale missed marker.** `DayBarsResolver:131`
   and `CellTintResolver:50` both read `EventPresence.isMissed`, and presence bumps
   `occurrenceRevision` — so excluding that revision from the grid freezes the marker.
   Fixed by adding `presenceRevision` (additive; `occurrenceRevision` still bumps too) and
   `CalendarPageLoaded.sameGridInputs`.
2. **1.2's "nothing else in the form reads the title" is false.** Two build-phase reads:
   `_canSave` inside the Save `ListenableBuilder`, and "Save as template" with **no**
   builder at all — it depended entirely on the deleted `setState`.
3. **1.3 cannot be golden-tested** (no golden infrastructure exists) and is **not**
   pixel-identical: `Opacity` fades a composited layer, per-colour alpha fades each layer
   independently. Guarded by resolved-`Color` assertions instead.
4. **1.5's third index is harmful.** `getActive()` is `SELECT *`, so an index on
   `(event_id, day)` covers 2 of 9-10 columns. Measured at 20k rows: non-covering, it is
   *slower* than the scan it replaces. Two indexes, plus narrowed `getActiveKeys()`
   projections so skips/absences become genuinely covering. Occurrences keep the scan.
5. **1.5's predicate was not "restated verbatim".** Drift's `.equals(false)` emits a bound
   parameter, and whether SQLite matches that against a partial index is version-dependent
   (3.53 does, 3.50 does not). The new reads emit a literal `is_deleted = 0`.
6. **`createCalendarIndexes()` could not host the new indexes.** It runs inside the v9→v10
   migration, where `calendar_event_skips` (v30) and `calendar_event_absences` (v26) do not
   exist yet — `IF NOT EXISTS` guards the index name, not the table, so any user upgrading
   from ≤v9 would have hit a hard migration failure. Split into
   `createCalendarDeltaIndexes()`.

1.7's framing was also narrowed: every *in-app* holiday mutation already dispatches a full
reload, so the bug is latent there. The genuine holes are **backup restore** and **database
switching**, and both are broader than holidays — see the note under 1.7.

A code-review pass on the finished work then caught three more, all fixed and folded in:

7. **1.6's bulk read was O(notes), not O(settings).** `user_settings` holds a
   `note_position_<id>` row per note, so `getAllSettings()` inverted the optimization at
   volume — 56.5 ms vs 1.9 ms at 10k notes, on the pre-first-paint path. Replaced with a
   keyed `getValuesFor(keys)`.
8. **1.3 washed out the day number** on the one branch where it sits on an opaque chip.
   Fading a glyph and its opaque background independently destroys their contrast. That
   branch keeps a composite `Opacity`; the rest still fade by colour.
9. **The 0.1 benchmark timed the wrong method** — `getActive()`, after 1.5 moved both
   `_load`s to `getActiveKeys()`. Now times both.

Phase 2 was verified the same way, and two more of its premises did not survive:

10. **2.1 as written was a crash, not a slow path.** "Every call site already awaits
    `getInstance()`" is false — nineteen sites resolved the seven services **synchronously
    from GetIt**, and `BackupService` is reachable from **onboarding**, the first screen a
    new user sees. Removing the registrations without migrating those sites would have
    broken backup import on fresh installs, swallowed into a generic failure snackbar.
11. **2.2's premise is false.** `main.dart:139` never ran at startup: `BlocProvider.lazy`
    defaults to `true`, so the reload and the ledger fan-out cost a **calendar-open**, not a
    launch. Two consequences: the LRU-thrashing argument is backwards in time, and **2.1
    never depended on 2.2** — the reverse of what this document implies. Also, the reload is
    one indexed `SELECT`; the fan-out is the real N, and it has **three** callers, of which
    the roadmap names one.

And its code-review pass caught two more, both fixed:

12. **Batching broke the ledger's per-note isolation.** Moving decompression into the batch
    put it outside the per-note `try/catch`, so one undecodable chunk wiped the money
    surfaces for *every* linked note. The batch now drops an unreadable note from its map —
    absent means "unreadable", `''` means "no content".
13. **A failed service seed stranded the bloc permanently.** A rejected future stays
    rejected, so re-awaiting it meant every later create/update/delete silently no-oped and
    not even a database switch could recover. The resolver now falls back to `getInstance()`
    once the seed has been consumed, successfully or not.

**Method note.** Every roadmap claim was re-verified against source before being
implemented, and the ones that would have shipped bugs (1.1, 1.2, 1.5's index placement,
2.1's registration removal) were caught in that pass, not by tests. Item 6 — a hard
migration failure for anyone upgrading from ≤v9 — was caught only because the implementer
read the v9→v10 call site instead of trusting "add it to `createCalendarIndexes()`". Items
12 and 13 were caught only by reviewing the finished diff. Treat the remaining phases the
same way: the line numbers in this document are from 2026-08 and many are now stale.

---


Three independent audits (SQL/persistence, UI/frame-time, recurrence expansion), each
reading source rather than inferring. Findings are merged here and de-duplicated; where
two audits found the same thing from different angles it is noted, because that
convergence is the strongest signal in the review.

## Verdict

The **design** is right and should not be re-litigated. Recurrence is computed and never
materialised; the schema, PRAGMAs and index/predicate discipline on `calendar_events` are
careful and already guarded by tests; the memoization contracts (`_dayCache`,
`_monthNetCache`, `_InlineMarkdownCache`, `FastingCalendar`) are correct on the axes they
claim to cover.

The **costs** are in when work runs and how often, not in what the code computes:

- Nothing about the calendar has ever been measured at volume. `volume_benchmark_test.dart`
  seeds only notes/folders.
- The whole subsystem loads eagerly at app start, before the first frame, for users who
  may never open the calendar.
- A month paint is O(42 x all events) with no rule-level pruning, and the per-call
  constant factor is ~70% avoidable re-normalization.
- Every state emission rebuilds all 42 cells plus the panel; per-cell resolver output is
  recomputed from scratch each frame.

One latent **correctness bug** surfaced (holiday cache invalidation, 1.7). It is masked
today by an unrelated full reload.

## Where the audits disagree

The SQL audit listed `_dayCache`'s wholesale-clear-on-overflow under "fine"; the UI and
recurrence audits both flagged it. The latter two are right — the SQL audit was not
looking at month-paging behaviour, where the clear evicts the page being painted.

Unverified claim to check before acting: `day_bars_resolver.dart:246` and
`day_summary_resolver.dart:313` both comment that events "arrive pre-sorted", while both
files also sort defensively. Establish which is true before removing either sort (3.3).

---

## Phase 0 — Measure first — **shipped**

Nothing below should be judged by feel. Build the harness before the fixes.

**0.1 — done.** `test/database/volume_benchmark_test.dart` gained a sibling calendar group
at 200 and 2,000 events across all nine rule kinds, with ~5 years of skips/absences/
occurrence overrides and **10% tombstones** (never collected, so a benchmark without them
measures a state no 5-year user is in). The `ANALYZE` in `_seed` was **removed**: the app
never runs it, so seeding-then-analyzing measured a query plan production cannot reach.

Baseline (in-memory, best-of-three):

| | 200 events | 2,000 events |
| --- | --- | --- |
| `calendarEventDao.getAll()` | 3.4 ms | 31.0 ms |
| `eventSkipDao.getActiveKeys()` *(the `_load` path)* | 2.5 ms | **20.2 ms** |
| `eventSkipDao.getActive()` *(backup export)* | 3.9 ms | 35.2 ms |
| `eventAbsenceDao.getActiveKeys()` | 2.6 ms | **20.3 ms** |
| `eventAbsenceDao.getActive()` | 3.9 ms | 35.6 ms |
| `eventOccurrenceDao.getActive()` | 4.0 ms | 36.5 ms |
| description bytes resident | 35.9 KB | 559 KB |

Both shapes are timed on purpose. `getActiveKeys()` is what the services' `_load` calls and
what the partial indexes cover; `getActive()` is the wider read backup export still needs.
Timing only the latter would leave a `_load` regression — or a dropped index — invisible.

The delta reads were ~112 ms of startup at N=2,000 before 1.5; the two covering indexes cut
the skip and absence halves to ~40 ms combined, a **43% reduction each** on the path that
actually runs at launch. Occurrences keep the scan, deliberately (see 1.5).

The description figure settles the *Deliberately not doing* question: 559 KB at 2,000
events is not worth fracturing the read path for.

**0.2 — done, but not as specified.** `StatementCounter` is at
`test/database/support/db_test_support.dart:96`, not `query_count_test.dart:8-13`, and it
works only because Drift accepts an injected `QueryInterceptor`. `CalendarEvent.occursOn`
has no such seam, and `RecurrenceRule` is `sealed` so a decorating subclass cannot be
written from a test at all. Instead: `CalendarEvent.debugOccursOnCalls`, incremented inside
an `assert` so both the statement and its closure are stripped from profile and release
builds. `test/bloc/calendar_occurs_on_budget_test.dart` asserts **exact** counts, not
ceilings — a cold 42-day month at N=200 costs exactly 8,400 calls (confirming the ~84,000
projected at N=2,000), a second pass costs 0, a presence write costs 0, and a skip costs a
full re-expansion. It runs in the default suite: it counts work, not time.

**0.3 — not shipped as code**, and deliberately: it needs a device, a human, and produces
an artifact the repo cannot hold. Recipe: `flutter run --profile`, DevTools timeline, three
interactions (cold month swipe / day tap / agenda keystroke), record UI and raster ms.
**Phase 3 is gated on this being captured; Phase 1 was not**, because every Phase 1 item
has a deterministic guard (call count, query plan, statement count, resolved colours).

---

## Phase 1 — Contained, mechanical, low risk — **shipped**

Each was independently landable. Together they cut UI-thread and raster cost on the most
common interactions without touching any algorithm. Every item ships with a guard test.

**1.1 Split the page-root `BlocBuilder`.** *Done, with a correction.* The body builder in
`calendar_page.dart` had no `buildWhen`, and re-verification found three more unfiltered
builders the roadmap missed: the filter icon, the export menu and the FAB. All four now
have one. The body builder switches only loading/error/loaded; the grid and the panel
subscribe separately underneath, each inside a `RepaintBoundary` (the module previously had
none anywhere).

The roadmap's rule — props **minus** `occurrenceRevision` — is **wrong** and would have
shipped a stale missed marker: `DayBarsResolver` and `CellTintResolver` both read
`EventPresence.isMissed`, and presence bumps `occurrenceRevision`. Instead
`CalendarPageLoaded` gained **`presenceRevision`**, bumped alongside `occurrenceRevision` by
the two presence handlers so no existing consumer's semantics change, and
`sameGridInputs(other)` — every prop except `occurrenceRevision`, comparing the two
collections by identity (every handler that changes either builds a fresh instance, so it
can over-rebuild but never under-rebuild, and a day tap does not deep-compare N events).

Narrowing a `buildWhen` makes a captured state stale, so the filter sheet and the export
action now read `context.read<CalendarBloc>().state` at press time — the filter sheet needs
`format`, which its `buildWhen` deliberately ignores.

*Guard:* `test/bloc/calendar_grid_rebuild_test.dart`. The presence case is mandatory: it is
the only thing standing between a future presence write path that forgets the bump and a
permanently stale marker.

**1.2 Stop the title field rebuilding the whole editor form.** *Done.* The title field's
`onChanged: (_) => setState(() {})` is deleted; the Save button's existing
`ListenableBuilder` now listens to `Listenable.merge([_descriptionRevision, _titleController])`.

The roadmap's "nothing else in the form reads the title" is **false** — "Save as template"
read `_titleController.text` directly with no builder at all, and depended entirely on the
deleted `setState`. It now has its own `ListenableBuilder`; without that it would have
stayed permanently disabled after typing a title. Listening to `_titleController` directly
is safe: the prohibition documented at `:225` is specific to the re_editor
`CodeLineEditingController`, not to a plain `TextEditingController`.

*Guard:* `test/widgets/event_editor_title_test.dart`, including that the `CodeEditor`
element is `identical` across a title keystroke — the subtree is no longer re-mounted.

**1.3 Fold the outside-day fade into colours.** *Done.* Both whole-cell `Opacity` wrappers
are gone (one branch keeps a scoped one — see below).
`CalendarDayCell` fades `numberColor`, the accent where it is used as a paint colour, and
`tint.wash`/`tint.edge` through a private `_fade`; `CalendarDayBars` gained a defaulted
`opacity` parameter applied to bar colours, the outline and the overflow chip. Both
**multiply** alpha rather than set it — tint colours already arrive with alpha applied.
`CalendarDayCell.outsideAlpha` is the single shared constant, and no call site changed
signature.

Two things the roadmap did not say. `_onAccent` must keep estimating brightness on the
**un-faded** accent, or an outside selected day's number inverts on a pale accent. And the
result is **not pixel-identical** — `Opacity` fades a composited layer while per-colour
alpha fades each layer independently, so wherever layers stack (a glyph over an opaque
chip) they differ by `0.65 x 0.35 x (over - under)`. Flattening against a backdrop was
rejected: the cell has three call sites with three different backdrops.

**One branch keeps its `Opacity`, and must.** Where the chip is opaque (`isSelected ||
filledToday`) the number is painted *on top of* it, so fading the two independently destroys
their contrast and the digit washes out against its own background — a legibility
regression, not just a colour shift, and the review caught it. That branch keeps a single
composite layer; every other branch paints on transparency, where per-colour alpha and
`Opacity` are exactly equivalent. Cost: at most two layers per grid (an outside day can be
today or selected), against the 22-26 this item removed.

There is **no golden infrastructure** in this repo, so "golden-test the outside cell" was
not viable — and a golden would have failed by design here. *Guard:*
`test/widgets/calendar_outside_fade_test.dart` asserts resolved `Color` alphas, that an
inside cell is untouched, that no `Opacity` survives on the transparent branches, that the
opaque branch keeps exactly one and leaves the number at full alpha, and the `_onAccent`
inversion case.

**1.4 Hoist `DateTime.now()` out of the date-picker cells.** *Done.* `now` is hoisted into
`build()` beside the existing `l10n`/`theme`/`accent` and threaded into `_cell`; `_marker`
dropped its `BuildContext` for an `l10n` and a resolved `busyColor`. `now` stays a **raw
local** `DateTime` compared with `isSameDay`, matching the main grid — normalizing would be
a behaviour change wearing a perf fix's clothes.

The `:426`/`:437` half of the claim was overstated: both sit behind two early returns, so
they only ever fired for days that actually have events. *Guard:*
`test/widgets/calendar_date_picker_hoist_test.dart` — exactly one rendered cell has
`isToday`.

**1.5 Add partial indexes on the delta tables.** *Done — two indexes, not three, and via a
new method.* Schema **v31**: `idx_calendar_event_skips_active` and
`idx_calendar_event_absences_active`, both `ON (event_id, day) WHERE is_deleted = 0`.

Three corrections, each load-bearing:

- **`createCalendarIndexes()` could not host them.** It runs inside the v9 to v10
  migration, where neither delta table exists yet (`calendar_event_absences` is v26,
  `calendar_event_skips` is v30). `IF NOT EXISTS` guards the *index* name, not the table, so
  every user upgrading from a database at or below v9 would have hit `no such table` on
  launch. Split into `DatabaseIndexes.createCalendarDeltaIndexes()`, called from
  `createAllIndexes()` and from the v31 migration only.
- **No index on `calendar_event_occurrences`.** `getActive()` is `SELECT *`; an index on
  `(event_id, day)` covers 2 of 10 columns, and `EventOccurrenceService._load` also reads
  `description`. Measured at 20k rows with 10% tombstones: an `ANALYZE`d planner *rejects*
  the non-covering index, and taken without `ANALYZE` it is **slower** than the scan it
  replaces (a rowid lookup per live row). A `_load` that reads every live row is already
  best served by a scan.
- **The predicate must be emitted as a literal.** Drift's `.equals(false)` emits
  `is_deleted = ?`, and whether SQLite proves that implies the partial index's `WHERE` is
  version-dependent — sqlite 3.53 (the test host) uses the index, 3.50 does not, and
  `pubspec.yaml` pins `sqlite3_flutter_libs: ^0.6.0+eol`. So `query_plan_test.dart` alone
  validates the Windows host, not the Android build. The new reads emit
  `const CustomExpression<bool>('is_deleted = 0')`, and the tests assert the SQL text
  contains it — a portable assertion the plan check is not. **The pre-existing
  `idx_calendar_events_start_date` canary has the same hole and may already be scanning on
  device; not fixed here, it deserves its own before/after.**

`getActive()` was **not** narrowed: `exportData()` needs `createdAt`/`updatedAt`, and
narrowing it in place would have broken backup export with no failing test. A new
`getActiveKeys()` returns `({String eventId, DateTime day})` and only `_load()` uses it,
which is what makes the two indexes genuinely covering.

*Guard:* `query_plan_test.dart` asserts `USING COVERING INDEX` on both, plus the literal SQL
text, plus a migration case that drops the indexes and runs the real v30 to v31 step.
`schema_parity_test.dart` picks the names up by regex with no edit.

**1.6 Bulk-read calendar settings.** *Done, scoped.* A general snapshot cache was
**rejected**: it would need all 40+ setters to invalidate it plus a clear in `reset()` for
the `DatabaseLifecycle` contract — disproportionate for an item billed mechanical. Instead
every value gained a pure decoder taking the raw stored string, and both the single-row
getters and the bulk path call it, so the two cannot drift. `getCalendarAppearance()` went
11 statements to 1; a new `getCalendarPageSettings()` returns the whole `CalendarPage`
bundle in **1** statement, down from 16-18.

**The bulk read is keyed, not `getAllSettings()`** — and this is the correction the review
forced. `user_settings` is not only app settings: `NotePositionService` writes a
`note_position_<id>` row per note, so a full-table read scales with the **note count**, not
with the number of settings. Measured: 40 rows → 5.1 ms bulk vs 6.2 ms for 16 point reads;
2,040 rows → 17.6 ms vs 2.6 ms; 10,040 rows → **56.5 ms vs 1.9 ms**. The optimization
inverted at volume, on the one path that runs before the first frame. `getValuesFor(keys)`
is still one statement and stays O(keys), driven by two explicit key lists on
`SettingsService`.

`UserSettings.value` is non-nullable, so `map[key] == null` is true exactly when the row is
absent — precisely `getValue`'s contract, which makes `containsKey` unnecessary. The
absent-vs-empty distinction is preserved inside the decoder for `getFastingSchedule` **and**
for `getFastingAppearance`, which has the identical shape and which the roadmap missed. Both
getters keep their short-circuit so the retired key is not read on the common path.

*Guard:* `test/services/settings_bulk_read_test.dart` — statement count, round-trip
equivalence against every single-row getter (populated and virgin), both absent-vs-empty
pairs, and a **keyed-not-full-table** case: statement count alone cannot tell an `IN` read
from a table scan, so that case seeds 200 `note_position_*` rows and asserts the single
statement binds one parameter per key. Verified to fail on a revert to `getAllSettings()`.

**1.7 Fix the holiday invalidation bug.** *Done, and reframed.* `PublicHolidays` gained a
`revision` counter in the shape `EventSkips` already has, bumped in **both** `configure` and
`resetCache` — a reset that did not bump would leave the calendar expanding against a closed
database's holidays. `CalendarBloc` holds it as a single generation
(`_dayCacheHolidayRevision`), checked by `_syncHolidayGeneration()` at the top of **both**
`eventsForDay` and `monthNetFor`: the latter also calls `occursOn`, so it inherits the same
dependency and must not depend on the former running first. A generation rather than a cache
key, so a holiday change drops the cache instead of growing it.

**The roadmap's framing was wrong.** It is not "works today only because settings-return
reloads": every in-app holiday mutation dispatches deliberately —
`AppNavigator.toCalendarSettings` has exactly one caller, followed immediately by
`LoadCalendarEvents`, and `_removeHoliday` dispatches directly, including on Undo. The
genuine holes are **backup restore** (`BackupService` to `PublicHolidayService.importData`
to `configure`) and **database switching** (`DatabaseLifecycle` to `resetCache`), neither of
which dispatches anything.

The revision counter closes the holiday third of those. **The rest is still open, and is
broader than holidays**: `CalendarBloc` is app-wide and long-lived, so after a restore or a
DB switch its `allEvents` is stale too, and `CalendarPage.initState` only calls
`_loadSettings()` — never `LoadCalendarEvents`. Fixing that means a service or a lifecycle
handler reaching into a BLoC, which inverts the layering rule, so it is **deliberately left
for Phase 2** rather than smuggled in here.

*Guard:* `test/bloc/calendar_bloc_holiday_test.dart`, verified to fail without the fix.

## Phase 2 — Startup — **shipped**

The calendar used to tax every launch, including launches that never opened it.

**Two of this phase's premises were wrong, and one of them was a crash rather than a slow
path.** Both are corrected in place below.

**2.0 Harden `PublicHolidayService.getInstance()`.** *Not in the original plan; a
precondition for 2.1.* It was the only one of the seven calendar services with **no
try/catch** around its load. While it ran inside `configureDependencies()` a throw crashed
the launch; moving it onto the calendar's render path would instead have left
`PublicHolidays` uninitialized — and an uninitialized read there is not a blank calendar but
a **wrong** one, because `WorkdaysRecurrence` and `PublicHolidaysOnlyRecurrence` consult
`isHoliday` from inside `occursOn`. Both failure branches now still call `configure`, which
degrades to "computed built-ins, no user deltas" instead of the fixed-date fallback that
changes which days an event occurs on.

**2.1 Register the calendar services lazily.** *Done — but the roadmap's route to it was a
crash.*

"The services are already self-initializing idempotent singletons and every call site
already awaits `getInstance()`" is **false**. Nineteen sites resolved them **synchronously
from GetIt** and would have thrown `StateError: not registered` the moment the registrations
went away: eighteen in `BackupService` (export and import) and one in `calendar_page.dart`.
**`BackupService` is reachable from onboarding** — `onboarding_page.dart` → `_importBackup()`
→ `importFromJson()` walks all seven — so this would have broken backup import on the first
screen a new user sees, and `importFromJson` swallows the throw into a generic failure
snackbar.

So the seven registrations are gone from `injection.dart` and all nineteen sites now
`await X.getInstance()`. That is the same `getInstance()` + `DatabaseLifecycle` contract the
`drift-migrations` skill already documents, and `FastingCalendar`, `NoteMoneyLedgerService`
and `SettingsService` already worked this way — the GetIt sites were the inconsistent
minority.

**A correctness win the roadmap does not claim.** `registerSingleton<T>(instance)` holds the
*object*, while `DatabaseLifecycle` only nulls the service's static `_instance`. After a
database switch `GetIt.I<CategoryService>()` returned an object bound to the **closed**
database — masked today only because the switch flow forces a restart. `getInstance()` is
self-healing; `GetIt.I<>` is not.

`CalendarBloc` now takes `FutureOr<CalendarEventService>`, so `registerFactory` stays
synchronous (`BlocProvider.create` requires it) while tests keep passing an instance
directly — **zero test edits**. Every handler that needs the service is already `async`, and
the two synchronous, build-time-callable methods (`eventsForDay`, `monthNetFor`) read
`state`, never the service.

**Where the facades get resolved, and why it is not `initState`.** `_onLoad` resolves all
seven and **never emits `CalendarPageLoaded` before they do**. That invariant is the whole
safety argument: the facades are read synchronously from render paths and from `occursOn`,
and an unconfigured read is silent — a cancelled occurrence reappears, every category goes
grey, and holidays fall back to fixed dates. Putting the resolution in `initState` would
have left three of the four `LoadCalendarEvents` dispatch sites unprotected.

They resolve through **one `Future.wait`**, not sequentially — the roadmap's own complaint
about the DI block was that the latencies add rather than overlap, and that applies just as
much where the load now lives. But `Future.wait` **fails fast**, so each future is wrapped
by `_resolveQuietly`: one bad service must not reject the batch and blank the calendar, and
each already degrades to an empty published cache on its own.

During that window the page shows the spinner it already had for `CalendarPageInitial`, so
no facade-reading surface renders. Two escape hatches sit outside the body builder: the
settings gear (already self-healing — `CalendarSettingsPage` awaits its own services) and
the **FAB**, now inert while `selectedDay` is null, because the editor reads
`CalendarCategories` and an early tap would show a picker with no categories.

`CalendarPageLoading` stays **deliberately unemitted**: `Initial` already produces the
spinner, and emitting `Loading` at the top of `_onLoad` would flash it over a *populated*
calendar on all three re-load paths.

*Measured:* the four benchmarked loads total ~12.5 ms at 200 events and **~107 ms at 2,000**.
Three of the seven were never benchmarked, including `CategoryService`, which ran a **write
transaction with nine `INSERT OR IGNORE` on every single launch**. And the benchmark uses
in-process `NativeDatabase.memory()` while production uses `createInBackground`, so ~16
sequential isolate round trips are **not** in that figure. Honest framing: this removes a
fixed per-launch tax that scales with round-trip latency, plus real query time for a heavy
user.

**2.2 Drop the redundant reload and batch the ledger fan-out.** *Done — after correcting the
premise.*

**`main.dart:139` never ran at startup.** `BlocProvider.lazy` defaults to `true`, so
`CalendarBloc` is constructed on the first `context.read`, which only happens on the calendar
page. The reload and the fan-out cost a **calendar-open**, not a launch. Two consequences:
the LRU-thrashing argument ("the folder browser is about to need it") is **backwards in
time**, and **2.1 never depended on 2.2** — the reverse of what the roadmap implies.

The reload is **one** indexed `SELECT` (~31 ms at N=2,000), guarded now by `_didInitialLoad`:
after 2.1 the first `_onLoad` *is* the first load, so `reload()` there would read the table
twice. The guard is deliberately **"first load only", not "cache is warm"** — the latter
would also skip the settings-return re-read, and Settings → Categories → delete reassigns
events to `other` in a transaction behind the service's cache.

The **fan-out was the real N**, and it has **three** callers the roadmap misses two of:
`_onLoad`, `_onCreateEvent` and `_onUpdateEvent` — every event create and every edit re-ran
the full N-note fan-out, a hotter path than load. `ContentChunkDao.loadContentForNotes` +
a `NoteRepository` wrapper take it from N+1 statements to **2**.

The batch query's shape is load-bearing, measured with `EXPLAIN QUERY PLAN`:
`WHERE note_id IN (…) AND is_deleted = 0 ORDER BY note_id ASC, chunk_index ASC`. Drop the
leading `note_id` and SQLite adds `USE TEMP B-TREE FOR ORDER BY`; drop the predicate and it
degrades to `SCAN`. The predicate is a **literal** for the same reason as 1.5.

Four ways a batched read silently corrupts, all guarded by tests:

- **Zero-chunk notes.** `loadContent` answers `''` for a note with no chunks and the ledger
  writes an entry; a batch returns *no rows*, so a reader that walks only the rows drops it
  and its day bars and month-net contribution vanish with no error. The map is **pre-seeded
  with `''`** for every requested id.
- **Unreadable notes.** Batching moved decompression outside the ledger's per-note
  `try/catch`, so one undecodable chunk threw out of `refresh()` and wiped the money
  surfaces for **every** linked note. A note whose chunks fail to decode is now **dropped
  from the map**: absent means "unreadable", `''` means "no content", and the ledger skips it
  rather than folding `''` — a corrupt note shows no money surfaces, not a balance of zero.
  *(Caught in code review, not by the original plan.)*
- **Per-chunk compression.** The compression threshold and the chunk size are independent, so
  one note legitimately mixes compressed and plain chunks. Branch per row, never per note.
- **Chunk ids sort wrong.** Ids are `'${noteId}_chunk_$i'`, so a string sort puts `_chunk_10`
  before `_chunk_2`. Key by `noteId`, order by `chunkIndex`.

The repository wrapper reads **and writes** `_contentCache`, which is behaviour-preserving —
the N sequential `loadContent` calls it replaces each populated it too — and means every
refresh after the first is served entirely from the LRU at ≤50 linked notes. Corrected for
the record: the folder *listing* never reads `_contentCache`; only its 3-note tap prefetch
and the note editor do, so the real blast radius of an eviction is one extra chunk read on
the next note opened.

`preloadContent`, `backup_service.dart:48` and `import_export_service.dart:357` were
deliberately **not** converted — a 3-note prefetch, a whole-database export that would
materialise every note in one result set, and a recursive folder walk that would fill the LRU
with an entire tree.

**2.3 Reload when the store was replaced underneath the bloc.** *The Phase-1 carryover,
closed here.*

`CalendarBloc` lives above `MaterialApp` and is never disposed, so after a **backup restore**
or a **database switch** its `allEvents` described a store that no longer existed — and
because `_syncHolidayGeneration` drops the day cache when the restore republishes holidays,
the result was stale data *freshly recomputed*, which is worse than an obvious blank.

`CalendarEventService.externalRevision` is bumped in exactly two places — the end of
`importData()` and `reset()` — i.e. the two mutations no dispatch can observe. Deliberately
**not** bumped by `upsert`, `deleteById`, `deleteAll` or `reload`: the bloc drives those and
already emits. It is static so it survives `reset()` nulling the instance.

`CalendarBloc.isStale` compares it against the generation the current state was built from,
seeded from the current value rather than a sentinel so the page's first check cannot
double-dispatch against DI's own load. The resolver re-resolves through `getInstance()` when
stale, because a switch leaves the cached reference bound to the closed database — **and
never touches the seed once stale**, even before the first load, or the bloc would bind
itself to a database that is no longer active. It also **falls back to `getInstance()` when
the seed itself failed**: a rejected future stays rejected, so retrying it would strand the
bloc forever with every create/update/delete silently no-oping. *(Both code-review catches.)*

*One review finding here was deliberately declined.* After a database switch the resolver
builds a service that loads on construction, and `_onLoad` then reloads on top of it — a
redundant `SELECT`. The fix looks obvious, but `getInstance()` may hand back an instance
somebody else built, whose cache predates writes this bloc cannot see; claiming freshness
there trades one redundant read on a rare, restart-adjacent path for **silently stale
events**. Only the seed path claims `freshlyLoaded`. The test
`'reloading clears the stale flag'` is what caught the over-correction.

`_CalendarViewState` is now `RouteAware` on the existing `AppNavigator.routeObserver`,
matching the precedent in `optimized_folder_content_page.dart`. `RouteObserver<PageRoute>`
only fires between page routes, so the editor, detail, filter and picker sheets — all
`PopupRoute`s — do not reach `didPopNext`; Settings, Backup and Database pages do.
`_openSettings` keeps an **unconditional** dispatch rather than going through the stale
check, because a category delete is an event-row change that bumps no revision.

Covered: restore or switch with the calendar off the stack, with it on the stack, and the
settings/categories return — plus `NoteMoneyLedgerService._ledgers`, which the re-dispatched
`_onLoad` recomputes. **Not covered:** a database switch where the user dismisses the
restart-required dialog and never returns to the calendar, and any future mutation of
`calendar_events` from a non-`PageRoute` surface (none exists today).

**2.4 `getAll()`'s predicate as a literal.** The same bound-parameter hole v31 fixed, on the
single hottest calendar query (~31 ms at 2,000 events, and after 2.2's guard it *is* the
first-load read). Note the plan assertion proves nothing here — the Windows test host is
sqlite 3.53 and uses the index either way; the SQL-text assertion is the portable half, and
the real before/after needs a device.

*Guards:* `test/bloc/calendar_load_test.dart` (8 cases — first-load statement count, the
one-shot guard against an out-of-band write, seed recovery, a stale seed never being used
even before the first load, and the three remaining staleness cases), the `note content
batching` group in `query_count_test.dart`, two plan cases in `query_plan_test.dart`, and
`test/services/note_money_ledger_test.dart` (zero-chunk note, soft-deleted note, unreadable
note). Each of the six review-caught bugs was verified to fail its guard before the fix, not
merely reasoned about.

**2.1's crash class also has a dedicated guard**, closing the one check this phase could
otherwise only verify by hand: `test/services/backup_service_calendar_round_trip_test.dart`
seeds one of every calendar entity, exports through `BackupService.exportAllData()`, and
imports the result back through `importFromJson()` — the exact call chain onboarding takes,
with nothing but `CounterService` registered in GetIt, matching production after 2.1. There
is no "v7 backup" fixture to import from an old install; v7 is simply the format the app
writes today, so a fresh export-then-import round-trip exercises the same nineteen call
sites, in the same order, that consuming an old file would. `importFromJson` catches
internally and reports `ImportResult(success: false)` rather than throwing, so this is also
the only guard that would have caught the *silent* form of the crash — a `StateError`
swallowed into a snackbar a manual click-through might not notice on the first try. Verified
to fail with exactly that `StateError` when one call site was reverted to `GetIt.I<>()`.

**The wipe between export and import is load-bearing, and the first version of this test
did not have it.** Importing back into the database it was exported from, while the services
still held the caches seeding populated, made every assertion pass whether or not the import
did anything — demonstrated by renaming the `calendarEvents` key so its branch never ran,
which left the test green. Clearing all seven tables *and* calling
`DatabaseLifecycle.notifyDatabaseSwitching()` first fixes both halves: a skipped import
branch now leaves the data missing, and the `getInstance()` calls inside `importFromJson`
genuinely construct their services rather than returning singletons the test already built —
which is what a fresh install actually does. A test that imports into the same store it
exported from proves nothing unless that store is emptied in between.

*Still open:* `getChunksForNote` has the same bound-parameter/partial-index hole as
`getAll()` — a third canary deserving its own device before/after. And the ledger fills the
shared 50-entry content LRU with bodies it folds and discards; fixing that means a
no-promote insert or a non-caching bulk read, and needs a measurement first.

---

## Phase 3 — The algorithmic core

Highest payoff and the only batch carrying real correctness risk. Land as one unit behind
Phase 0's differential and call-count tests. Estimated combined effect at N=2000:
**~84,000 `occursOn` calls per cold month -> ~7,600, with ~70% less work per call.**

**3.1 Stop re-normalizing in `occursOn`** — **shipped (2026-08-21)** via the
anchor-regression doc: `occursOnUtcDay(DateTime)` with cached `startDateUtc` /
`endDateUtc` (public, because `EventAgenda`'s pruning reads them across the file
boundary — not the private `_startUtc` this item named), `occursOn` kept as the
normalizing wrapper, the hot callers (`eventsForDay`, `monthNetFor`, the agenda
scan) repointed, and `EventSkips.isSkipped` / `EventPresence.isMissed` switched
to assume a date-only UTC day (debug-asserted). The `const` constructor was
dropped — nothing constructs a `const CalendarEvent`. Original analysis, for the
record (found independently by two audits):
`calendar_event.dart:328-340` rebuilds `DateTime.utc(...)` for both operands, but every
caller already passes date-only UTC (`calendar_event_service.dart:305,308` and `:54-62`
normalize on load and on write; every `day` argument is pre-normalized). That is 2
allocations and 6 external component getters per call, ~70% of the constant factor. Add
`occursOnUtcDay(DateTime)` with a debug `assert` on normalization, cache `_startUtc`/`_endUtc`
as non-`props` fields on the model, keep `occursOn` as the public normalizing wrapper, and
repoint only the hot callers. Same treatment for `EventSkips.isSkipped` /
`EventPresence.isMissed`, whose doc comments currently claim "no allocation" while allocating.

*Hazard:* a future caller passing a local `DateTime` would silently change meaning — today
the wrapper rescues it. The assert plus keeping the wrapper public is the mitigation. Check
`calendar_page.dart:447` and `event_detail_sheet.dart:273` first.

**3.2 Add superset-only candidate generation and a window index.**
**Partially shipped (2026-08-21)** — the anchor-regression doc's B2 added
span-based candidate pruning + one-time bucketing to the **agenda scan**
(`EventAgenda.occurrencesInRange`), exempting `SpecificDatesRecurrence` because
it has no pre-start guard. The **grid** half described here — `candidateDaysIn`
on `RecurrenceRule` plus the per-window index for `eventsForDay` — is **not**
done. `eventsForDay`
(`calendar_bloc.dart:61-76`) tests every event against every day with no pruning — a yearly
birthday is checked against all 42 visible days. Add
`Iterable<DateTime> candidateDaysIn(from, to, start, {retroactive})` to `RecurrenceRule`,
**with a base implementation that yields every day in the window**, so an un-overridden rule
is bit-identical to today. Override for `OneTime`, `SpecificDates`, `Yearly`, `Monthly`,
`Weekly`, `Daily`; leave `Workdays`/`Weekends`/`HolidaysOnly` on the base. Replace the
per-day memo with a per-window memo built in one pass, with two O(1) prunes (`endDate` before
window, non-retroactive `startDate` after window).

**`occursOn` must remain the sole arbiter** — every generated candidate is still validated
through it, so `endDate`, `retroactive` and skips stay enforced in exactly one place.

*Must stay byte-identical:* Feb-29 yearly skipping non-leap years (`recurrence_rule.dart:186`);
day-31 monthly clamping (`:162`); the Monday-grid week phase including the negative-index floor
in `_weekIndex` (`:62-65`) — stepping from `start` instead of the epoch grid silently changes
A/B-week phase; Euclidean `%` for retroactive days; the refusal to back-project the anchor
(`:11-19`); `Weekly` with an empty weekday set producing nothing.

*Also:* the hidden-category filter must stay **out** of the index and remain render-time —
moving it in makes a skip and a hide indistinguishable, which both `event_skips.dart:14-17`
and `calendar_event.dart:322-327` explicitly warn against.

**3.3 Sort once, memoize resolver output.** `eventsForDay` returns unsorted, so
`DayBarsResolver` (`:127`), `DaySummaryResolver` (`:144`) and `CellTintResolver` each copy and
re-sort per cell per frame — with a comparator whose common tie-break `toLowerCase()`s both
titles (`event_agenda.dart:154`). ~2,000 string allocations per frame, independent of N. Sort
once where the list is memoized, precompute a `_titleFold` on the model, and memoize the
**resolver outputs** (not just the instances, which `calendar_page.dart:77-103` already does)
keyed on the union of every facade revision.

*Verify first:* the "arrive pre-sorted" comments noted above.
*Risk:* an incomplete revision key stales a cell. The three surfaces must keep agreeing on
"top event" — sorting once upstream strengthens that, but the widget test that ticks
presence/skip/description and asserts a repaint is mandatory.

**3.4 Fix cache eviction and prewarm neighbours.** `calendar_bloc.dart:73` clears all 512
entries **inside `eventsForDay`**, i.e. mid-paint, evicting the page being painted right then;
each cell hits the cache twice (`eventLoader` at `:786` and `_buildDayCell` at `:762`), so the
clear can fire between the two lookups of the same cell. Consecutive pages overlap, so this
fires roughly every 16 page turns. Switch to window-based eviction (`focusedDay ± 3 months`)
driven from `_onChangeFocusedDay`, never from the lookup. Separately, `PageView` runs with
`cacheExtent: 0`, so the neighbouring month is built inside the first drag frame against a
cold cache — prewarm prev/next months in a post-frame callback at idle priority. Nothing may
dispatch from inside `eventLoader`.

---

## Phase 4 — Agenda and settings

**4.1 Debounce the agenda scan, not just the persist.**
**Partially shipped (2026-08-21)** — the anchor-regression doc's A4 added a
~200 ms debounce on the query-only rescan in `UpcomingAgendaView.didUpdateWidget`
(the field stays live; anchor/filter changes still scan synchronously). The
per-event template-description fold cache below is **not** done — the
per-(event, day) description fold remains, reached only for description-matched
candidates under a needle. Original analysis:
`calendar_bottom_panel.dart:141-155`
calls `setState` immediately and debounces only `_persist` (500ms). So every keystroke re-runs
the full range scan (`upcoming_agenda_view.dart:173` -> `_recompute`), which folds every title
and description (`event_agenda.dart:70`, `:172-183`) and re-folds descriptions **per (event,
day)** at `:192-200`. At N=2000 over 30 days that is ~60M chars copied per character typed; a
366-day custom range multiplies by 12.

Three independent fixes: debounce the scan (~150-200ms, keep the field fully controlled so the
caret never jumps); hoist template-description folding out of the day loop into a per-event
cache, folding only the day's *override* per day; and apply 3.2's candidate generation to the
day loop.

*Preserve:* the documented asymmetry at `event_agenda.dart:185-191` — an event whose override
on one day no longer mentions the needle must drop out of *that day* even though the template
still matches. Cache the fold; never substitute for the per-day decision.

**4.2 Rewrite `removeDiacritics`.** `folder_search_service.dart:41-48` indexes with `text[i]`,
allocating a one-character `String` per character. Iterate `codeUnits` and only consult the map
above ASCII. This is shared with note search, so it must produce byte-identical output —
table-driven test over the full `SearchConstants.diacriticsMap` key set.

**4.3 Memoize the day panel's resolver.** `calendar_bottom_panel.dart:201-204` constructs
`DaySummaryResolver.defaults(...)` — 5 provider allocations — inside `build`, then rebuilds
every row including an `IntrinsicHeight` double layout pass. Hoist onto state with the memo
shape `calendar_page.dart:81-91` already uses.

**4.4 Slider drags in calendar settings.** `calendar_settings_page.dart:918-922` and four
siblings do `setState` + an awaited settings write + haptic feedback *per drag tick*,
rebuilding a non-lazy `ListView(children:)` of ~40 rows plus the live preview. Keep a local
draft value, move the write and haptic to `onChangeEnd` (with a debounced fallback —
`onChangeEnd` does not fire for accessibility-driven changes on all platforms). The
`ListView.builder` change in `settings_section_list.dart` helps every settings page but widens
blast radius; treat separately.

---

## Phase 5 — Cleanup

**5.1** Backup import: per-row transactions. 2,000 events ≈ 8,000 statements and 2,000 WAL
commits, each with a guaranteed-miss `SELECT` (the table was just emptied by `deleteAll()`).
Add `importEvent` matching the existing `importOccurrence` convention and wrap each loop in one
transaction. The author's own measured table (`database.dart:204-217`) prices this at ~3x.
Verify `deleteAll()` precedes the loop in every service before changing upsert semantics to
insert.

**5.2** `RecurrenceCodec.decode` calls `jsonDecode` twice for weekly rules
(`recurrence_rule_codec.dart:76-79`). Load-time only. Preserve the defensive contract:
malformed payload must still let the kind through.

**5.3** `DayBar` keys interpolate `'event:${event.id}'` per event per cell per frame
(`day_bars_resolver.dart:141`). Precompute, without letting an event key collide with
`'fasting:'`/`'holiday'`/`'weekend'`.

**5.4** `FastingCalendar.cellStyleFor(day)` called twice per cell for the same day
(`calendar_page.dart:751` and `cell_tint_resolver.dart:97`).

**5.5** Copy-on-write publish in the three overlay services — currently a full map deep-copy
per single-day mutation. Preserve the stated invariant that a published snapshot can never be
mutated under a render path.

**5.6** `Semantics` per bar = ~126 extra render objects in the grid; `IntrinsicHeight` per
agenda/panel row is a double layout pass.

**5.7** `DayTimelineView` computes its layout in `build`.

---

## Deliberately not doing

**Projecting descriptions out of the event cache.** 2,000 events with 300-char descriptions is
~1.2MB resident, and the 10,000-char ceiling could push it toward 8MB. But descriptions are
genuinely needed by visible surfaces, and splitting the single read path would fracture what
the tombstone filter, backup snapshot and `.ics` export all inherit. Measure in Phase 0; act
only if the memory proves to matter.

**Indexing `calendar_events.category`**, or indexing the category/template tables. One scan of
2,000 rows on an explicit category deletion; the other tables are double-digit row counts by
design. Both would be pure churn.

## Do not churn — verified correct

Recurrence computed and never materialised. `idx_calendar_events_start_date` and the predicate
that restates it exactly (already guarded as a canary). The PK-composite indexes on the delta
tables. All bulk cascades and `reassignCategory` as single set-based statements with
`version + 1` in SQL. Connection PRAGMAs with their measured justification. Set-based
migrations. Holidays computed not stored; the per-year memoized generators for holidays and
fasting (no linear table scans despite file size). Two-level map lookups that avoid the
`'$id:$day'` composite-key trap. `_monthNetCache`'s four-input invalidation and its agreement
with `MoneyDayBarProvider`. `_dayCache`'s invalidation *triggers* — including the deliberate
non-triggers for description and presence writes. `_InlineMarkdownCache`. The `AgendaListView`
identity-keyed row memo and its real `ListView.builder`. Resolver *instance* memoization.
`now`/`accent` hoisting on the main grid. Panel state living below the page. The
`_descriptionRevision` relay. Equatable short-circuiting on `identical`, so a day tap does not
deep-compare N events. No timezone conversion anywhere in expansion.
