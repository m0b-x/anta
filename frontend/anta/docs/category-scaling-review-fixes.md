# Category Scaling — Post-Implementation Review Fixes

**Status: RESOLVED 2026-08-29. Every item below is applied, deferred by
decision, or closed as no-change — see the outcome line under each.** Written
against commits `61149c9`, `a1ea25a`, `6775c53`, `221ef57` (waves 1–3b of
`category-scaling-roadmap.md`); the fixes landed alongside wave 4.

## Outcome at a glance

| Item | Outcome |
| --- | --- |
| F1 `updateCategory` clobbers `sort_order` | **Fixed**, and it uncovered a second bug — see below |
| F2 agenda sub-sheet inverted seeding | **Fixed** — seeds and collapses in the caller |
| F3 `Select all` vs archived denials | **Withdrawn — false positive.** Implemented, then reverted; see below |
| F4 search field vanishes mid-query | **Fixed** in both the page and the picker |
| F5 icon tiles unnamed | **Fixed** — `Tooltip` on every tile, before A2 made them 217 |
| F6.1 rounded icon variants | **No change** — the plain forms are the precedent (below) |
| F6.2 nested `setState` | **Fixed** |
| F6.3 `forTesting` binds silently | **Fixed** — asserts on a different `AppDatabase` |
| F7 stale ids, locale collation | **Deferred**, recorded in the roadmap's deferred list |

## Second pass — reviewing the fixes themselves

A code review of *this* fix pass found three more, all now resolved. Worth
recording because two of them were introduced **by** the fixes:

- **`_exactBand` collided with `FuzzyRank`'s own sentinel.** Both are `-1`, and
  `band: scored >= 0 || scored == _exactBand ? scored : FuzzyRank.tiers`
  therefore promoted every entry that matched *only* through its group label to
  the **best** band instead of the worst, making the `FuzzyRank.tiers` fallback
  dead code. Exact-term and fuzzy score are now resolved separately. The
  existing `cardio` test could not catch it — for that query every entry lands
  in one band and the catalog-index tie-break reproduces the expectation by
  coincidence — so a `recovery` case was added, where three entries carry the
  word as a keyword and two match through the heading alone.
- **`importData` was the one mutation left outside `_serialize`**, while the
  class doc had just been rewritten to claim every mutation is chained. It
  opens by wiping the table and the management page fires its mutations
  un-awaited, so an in-flight `create` could land mid-restore as an orphan row.
  Now serialized like the rest.
- **F3 was a false positive** and its "fix" regressed the filter sheet — see
  the F3 section.

**F1 uncovered a latent bug the review did not see.** Serializing every write
made `CategoryService`'s chain load-bearing on a path no test had exercised, and
it deadlocked every widget test that awaits a mutation directly: the tail was a
`Future<void>.value()` built in a *field initializer*, which captures the zone it
is created in. Built during `setUp`, its continuations schedule on the root zone,
which the `FakeAsync` a `testWidgets` body runs in never drains — so the first
write never completed. The chain's tail now starts `null` and an idle service
awaits nothing. **The same latent trap was already in the shipped
`_reorderChain`**; it only stayed invisible because every reorder in the tests is
followed by a `runAsync` drain. Roadmap invariant 12 records it.

This is the fix list from a full review of the shipped category-scaling work.
It is written to be implemented cold, one slice at a time, by a fresh session —
read `docs/category-scaling-roadmap.md` first for the vocabulary (waves,
invariants, `visible` / `visiblePlus`, allowlist vs denylist), then this file.

The overall verdict is that the implementation is faithful to the roadmap and
its invariants: the schema/migration/backup work is correct, `rankCategories`
and the icon index match their specs, the reorder chain and the optimistic
order are right, `visiblePlus` is applied everywhere a selection lives, and the
three carried-over traps (empty query bypasses the ranker, `runAsync` drains,
bounded pumps) are all respected. `dart analyze lib` is clean and all 136
category-suite tests pass. The fixes below are what a long-term system still
wants; none of them is a data-loss or crash bug.

One bookkeeping note before the fixes: commit `221ef57` is titled "Phase 3b
and 4" but contains **only wave 3b**. The roadmap's status line ("Wave 4
remains") is correct; trust it, not the commit message, when reconstructing
history.

Verification for the whole file, once all fixes land:

```powershell
dart analyze lib
flutter gen-l10n            # only if F2/F5 add ARB keys; check untranslated.txt
flutter test
```

---

## F1 — Stop `updateCategory` writing `sort_order` (required)

> **Done.** `sort_order` and `is_built_in` are `Value.absent()`; `setHidden`
> writes only the flag and re-reads inside its own serialized turn; every
> mutation (including `create` and `deleteCategory`) runs through `_serialize`.
> Four regression tests in `category_service_test.dart` under *"a write cannot
> clobber the order"*. See the zone note at the top of this file for the second
> bug this uncovered.

**The one real correctness fix in this list.**

`CategoryService.updateCategory` ([category_service.dart:167](../lib/services/category_service.dart#L167))
writes a **full row** — including `sortOrder` and `isBuiltIn` — from whatever
model the caller holds. Two callers hold models that can be stale on exactly
that field:

- `setHidden` reads `CalendarCategories.byId(id)` and writes it back. Hide and
  edit writes are **not** on the reorder chain, so nothing orders them against
  an in-flight drag persist.
- `CategoryEditorSheet` captures its `initial` model when the sheet opens and
  saves it (with new name/color/icon) whenever the user taps Save.

Failure scenario: drag a row to a new position (optimistic order applied,
`reorder` batch in flight or just landed), then hide it — or open its editor
before dragging and save after. The `updateCategory` write lands last and
restores that row's **pre-drag `sort_order`**. The row visibly jumps back on
the next load, and worse, the dense `0..N-1` ordering invariant is broken: the
stale value can duplicate another row's order, and `_byOrder`'s id tie-break
then shuffles rows that were never touched (the exact failure mode the DAO doc
comment on `reorder` warns about).

**Fix**, at the service level (the DAO's `updateCategory` stays a general
write):

1. In `CategoryService.updateCategory`, make `sortOrder` and `isBuiltIn`
   `Value.absent()` in the companion. Nothing legitimately changes either
   through this path — order changes go through `reorder`, and `isBuiltIn` is
   immutable by definition. `setHidden` and the editor sheet then can't
   clobber order however stale their model is.
2. Cheap hardening while there (optional but recommended): rename
   `_reorderChain` to `_writes` and route `updateCategory`, `deleteCategory`
   and `_persistReorder` all through it. That also closes the narrow
   load-interleaving window where two concurrent mutations' `_load()` calls
   complete out of order and briefly publish a cache missing the later write.
   Keep the existing error-isolation shape (`catchError` on the stored tail,
   error still surfaces to the caller).

**Test** (in `test/services/category_service_test.dart`): reorder to a new
order, then `setHidden` on a moved row using the *pre-reorder* model state
path; assert `getAll()` still returns the post-reorder dense order and the row
is hidden. A second test: `updateCategory` with a model whose `sortOrder` was
doctored to a wrong value leaves the stored `sort_order` untouched.

## F2 — Seed and collapse the agenda's category sub-sheet (behavioural)

> **Done**, exactly as specified: an empty allowlist opens the picker with every
> offered row checked, and a result covering everything on offer collapses back
> to `{}`. `CategoryPickerSheet.pickMulti` stayed semantics-free — both halves
> of the inversion live in `AgendaFiltersSheet._pickCategories`, which is what
> the roadmap meant by "the caller inverts". Unchecking every row still stores
> `{}`, matching the chips below the threshold. Three tests in
> `category_filter_sheets_test.dart`; the old test that pinned the *previous*
> seeding was rewritten rather than deleted, into the explicit-allowlist case.

The two `CategoryFilterTile`s look identical but their sub-sheets open
differently for the same displayed state:

- `CalendarFilterSheet._pickCategories`
  ([calendar_filter_sheet.dart:108](../lib/widgets/calendar_filter_sheet.dart#L108))
  inverts its denylist, so with nothing hidden the picker opens **fully
  checked** — matches the tile saying *All categories*.
- `AgendaFiltersSheet._pickCategories`
  ([agenda_filters_sheet.dart:119](../lib/widgets/agenda_filters_sheet.dart#L119))
  passes the raw allowlist, so with an empty allowlist (= all) the picker
  opens **fully unchecked** while the tile above it just said *All
  categories*.

Same tile, opposite-looking sub-sheets — the user cannot form one model of
what a checkmark means. There is also a semantic trap on the way back: a user
who checks every visible category stores the *explicit* full set, and a
category created later is then silently excluded from the agenda.

**Fix**, entirely inside `AgendaFiltersSheet._pickCategories` (the picker
itself stays semantics-free, and the no-empty-collapse rule on
`CategoryPickerSheet.pickMulti` stays exactly as it is):

1. When `_draft.categoryIds.isEmpty`, seed `selected` with every
   `CalendarCategories.visible` id instead of the empty set.
2. On return, if the picked set contains every visible id, store `{}` (the
   allowlist's own "all" encoding) rather than the explicit set — this is the
   *allowlist-specific* collapse, done by the caller that owns the semantics,
   which is where the roadmap said inversions belong. A picked set that is a
   strict subset stores as-is. Note the one lossy edge in a comment-free way
   (the doc, not code comments): picking "all visible plus a hidden id kept
   from before" also collapses to `{}`, which is fine — `{}` includes that
   hidden category's events too, and stays correct when new categories appear.
3. Unchecking everything still returns `{}` → allowlist empty → all. That
   matches what unchecking every chip does today below the threshold; no
   change needed, but preserve the existing test that pins it.

**Test** (extend `test/widgets/category_filter_sheets_test.dart`): opening the
agenda sub-sheet with an empty allowlist shows every visible row checked;
applying with all rows checked leaves `categoryIds` empty; unchecking one row
stores the explicit remainder.

## F3 — Decide the `Select all` vs archived-denials asymmetry (decision + small change)

> **WITHDRAWN — this finding was wrong, and shipping it regressed the sheet.**
> The recommended branch was implemented, a second review caught it, and it has
> been reverted to the original `_hidden = {}`.
>
> The finding read the asymmetry as an oversight. It is not. `_clearAll`'s union
> guards a **one-directional** hazard — *hiding* everything must not
> accidentally un-hide an archived denial — and that hazard has no mirror:
> *showing* everything showing an archived category's events is precisely what
> the button says, and by Decision 1 those events already render on the grid in
> their own colour anyway. Nothing in either reset touches `is_hidden`.
>
> Implementing it broke two things. The header is a single toggle on
> `allSelected`, so subtracting only the visible ids leaves an archived denial
> in `_hidden` forever: it never empties, the toggle never flips back, and
> "Select all" becomes a permanent no-op. And computing `allSelected` over
> `visible` while the tile below computes `selectsAll` over `visiblePlus(_hidden)`
> made header and tile disagree on screen — "all selected" above a subtitle
> enumerating a partial set.
>
> **The lesson worth keeping:** a symmetry argument is not a correctness
> argument. Before "fixing" an asymmetry, find the hazard the odd side guards
> and check whether it actually points both ways. The test now pins the
> asymmetry deliberately, with that reasoning in its doc comment, so the next
> reader does not re-raise it.

`CalendarFilterSheet._clearAll` was deliberately changed to **union** so a
reset cannot silently un-hide an archived category already sitting in the
denylist (roadmap, "As shipped" under D). But `_selectAll`
([calendar_filter_sheet.dart:87](../lib/widgets/calendar_filter_sheet.dart#L87))
still does `_hidden = {}` — the same silent un-deny of archived ids, from the
other button. The two resets now embody opposite philosophies.

**Recommended resolution** — mirror the clear-all reasoning:

1. `_selectAll` becomes `_hidden = _hidden.difference({for (final c in
   CalendarCategories.visible) c.id})` — it un-denies everything the sheet
   *offers* and leaves archived denials alone. The sub-sheet remains the
   escape hatch for un-denying an archived id (it lists `visiblePlus(_hidden)`,
   so the archived-denied row is reachable there).
2. `allSelected` (used for the header state) must then be computed over the
   visible set — `CalendarCategories.visible.every((c) =>
   !_hidden.contains(c.id))` — not `_hidden.isEmpty`, or the header never
   reads "all selected" while an archived denial exists.

If instead the deliberate answer is "Select all means *everything*, archived
included," that is defensible — but then say so in
`docs/calendar-events-feature.md` next to where the clear-all union is
documented, because the asymmetry will otherwise read as a bug to the next
reviewer (it did to this one).

**Test**: with an archived id in the denylist, Select all leaves it denied and
the header still reports all-selected; Clear all keeps its existing pinned
behaviour.

## F4 — Keep the search field alive while a query is active (small correctness)

> **Done** in both copies of the guard (`_isFiltering || length > threshold`).
> Two tests, one per surface: deleting the 13th category on the page while a
> query is live, and de-selecting an archived-but-selected row in the picker —
> the picker's own way of shrinking its offered set past the threshold.

`calendar_categories_page.dart:294` computes
`showSearch = _categories.length > AppConstants.listSearchThreshold`. Deleting
a category **while a query is active** can drop the count to the threshold or
below: the search field disappears, but `_query` stays set — the list stays
filtered with no visible way to clear it unless it happens to be empty (only
the empty state carries a Clear button).

**Fix**: `showSearch = _isFiltering || _categories.length >
AppConstants.listSearchThreshold`. Apply the same guard in
`category_picker_sheet.dart:171` for symmetry (it cannot currently shrink
mid-sheet, but the guard is one `||` and removes the assumption). The
markdown settings page does not need it — its lists cannot shrink while
filtering.

**Test**: on the page with 13 categories and an active query matching the
13th, delete it; the search field is still present and clearing it restores
the full list.

## F5 — Icon tiles need accessible names (polish, grows urgent with A2)

> **Done, and in time** — the tooltip landed before A2 took the catalog to 217
> tiles, so it was one wrapper rather than a retrofit. Message is the key with
> underscores as spaces, which needs no ARB entry.

`_IconTile` in
[icon_picker_sheet.dart:278](../lib/widgets/icon_picker_sheet.dart#L278)
renders a bare `Icon` in an `InkResponse` — no tooltip, no semantics label. At
63 icons a screen-reader user gets 63 unlabeled buttons; wave 4 makes it ~300.

**Fix**: wrap the tile in `Tooltip(message: ...)` (which also provides the
semantics label) using the key with underscores read as spaces — the same
humanization the search index already applies, so no new strings and no ARB
work. If a nicer label is wanted later it can become a localized concern, but
the keyword decision (English, match-only) deliberately does not cover
rendered text, so keep it to the humanized key for now.

Do this **before or during wave 4**, not after — it is one wrapper now and a
300-icon retrofit later.

## F6 — Small consistency and hygiene items (batch, low priority)

Safe to do in one pass; none changes behaviour.

1. **Rounded icon variants. → No change, deliberately.** The escape clause in
   this item is the answer: `markdown_settings_page.dart` — the page
   `settings_reorder.dart` was extracted from and `calendar_categories_page.dart`
   was modelled on — uses **48 plain `Icons.` references and zero `_rounded`**.
   The six icons flagged here (`visibility`, `edit`, `delete`, `more_vert`,
   `drag_handle`, `lock_outline`) match that precedent exactly, in the same
   roles. Rounding them would make the two reorder pages disagree, and
   `settings_reorder.dart` is *shared* with the markdown page, so it would
   change that page's look too. The rule this settles: **list-row chrome
   follows the older page's plain forms; affirmative and app-bar actions use
   `_rounded`.** Do not re-raise.
2. **Nested `setState` in the picker.**
   `_CategoryPickerSheetState._createCategory`
   ([category_picker_sheet.dart:150](../lib/widgets/category_picker_sheet.dart#L150))
   calls `_clearQuery()` — which itself calls `setState` — from inside a
   `setState` callback. Legal, but re-entrant for no reason: hoist the
   controller clear and query reset into the outer callback's body directly.
3. **`CategoryService.forTesting` silently ignores its argument** when an
   instance already exists, binding the test to whatever database came first.
   Add an assert that fires when a live instance is already bound to a
   *different* `AppDatabase`, so a test-ordering mistake fails loudly instead
   of passing against the wrong DB.

## F7 — Deferred, recorded so it is not forgotten

> **Still deferred, now recorded where it will be found**: both items moved into
> `category-scaling-roadmap.md`'s "Deferred, not planned here" list, which is
> the section a future session actually reads. One incidental change: the
> agenda's sub-sheet returns exactly what is checked, so any round trip through
> it now drops stale ids as a side effect — a mitigation, not the fix.

Not part of this fix pass; candidates for their own slices later.

- **Stale ids in persisted agenda filters.** Deleting a category reassigns its
  events but does not prune its id from `UpcomingAgendaFilters.categoryIds`
  (or any other persisted selection). A stale allowlist id is harmless-ish —
  `countByCategory`'s absent-key convention and `visiblePlus` both tolerate it
  — but an allowlist containing *only* stale ids filters the agenda down to
  nothing while the tile reads "0 selected". Pre-existing behaviour, made more
  likely by forty categories. A cleanup hook on `deleteCategory` (or a
  read-side prune the way calendar settings drop unknown keys) is the shape.
- **Locale-aware sort for A–Z.** `_sortAlphabetically` orders on the
  `normalizeForSearch` fold, which handles diacritics but is not true locale
  collation (German `ö`, etc.). Fine at this scale; revisit only if a user
  reports it.
- **Wave 4 (A2 + A3)** remains open per the roadmap, which is the plan of
  record for it. F5 above should ride with it if not done earlier.
