# Category Scaling Roadmap — ANTA

**Status: waves 1 and 2 shipped (2026-08-29). Waves 3a, 3b and 4 remain.**
This is the plan of record for scaling calendar event categories from the
shipped baseline (9 built-ins, a 63-icon palette, no search / reorder / hide
anywhere) to a set that stays usable at forty categories.

What exists now is the **whole data and logic layer, with no UI on it yet**:

- **B2 schema + facade + service + backup** — `calendar_categories.is_hidden`
  at schema **v33**, `CalendarCategories.visible` / `visiblePlus`,
  `CategoryService.setHidden`, additive `isHidden` backup key (no version
  bump). The consumer surfaces are *not* pointed at `visible` yet — that swap
  happens inside the 3a/3b rewrites, exactly as this document plans.
- **A1 catalog restructure** — `CalendarIconEntry(key, icon, keywords)`,
  `groups` as the one source, derived lookup / group / folded-search maps,
  English keywords on all 63 entries, `CalendarIcons.groupLabel` shared out of
  the picker sheet, and `matchesSettingsQuery(..., preFolded: true)` so the
  prebuilt index is not re-folded per keystroke. **The picker UI itself is
  still the flat unsearchable `Wrap`** — that is A1 step 4, in wave 3a.
- **B1 DAO + service** — `CalendarCategoryDao.reorder` (one read-free batch,
  dense `0..N-1`) and `CategoryService.reorder` with the writes serialized onto
  a chain. No drag UI yet.
- **B5 `countByCategory`** — one `GROUP BY`, added to `query_count_test`'s
  guard. Not rendered yet.
- **B3 `lib/utils/category_search.dart`** — `rankCategories`, membership by
  `matchesSettingsQuery`, order by `FuzzyRank`, icon-only hits demoted a band,
  explicit `(band, sortOrder, id)` sort. No search field yet.

Two notes for whoever picks up 3a:

1. **`CategoryService.reorder` already serializes** (B1 step 4). The page's job
   is the optimistic `setState` and passing its *current* full local order —
   do not build a second chain in the widget.
2. `CategoryService.forTesting(db)` now exists, matching the other calendar
   services.

Nothing outside `test/` reads `visible`, `visiblePlus`, `reorder`,
`countByCategory` or `rankCategories` yet; wave 3a is where they get callers.

Read alongside `docs/calendar-events-feature.md` (the running behaviour of the
subsystem) and the `calendar-events` skill (hard rules). This file is written to
be **self-sufficient**: a fresh session should be able to implement any one wave
from this document plus the skills, without reconstructing the analysis.

## Context

The category system was designed for a fixed set. Three things break as it grows:

- **The icon picker** is a flat grouped `Wrap` of 63 icons with no search, and
  the catalog lists every key twice (`_byKey` and `groups`) — already a drift
  hazard, untenable at 300.
- **The management page** (`calendar_categories_page.dart`) is an unfiltered
  `ListView` with a FAB. No search, no reorder, no way to retire a category
  short of deleting it and recolouring its history.
- **The picker sheet** (`category_picker_sheet.dart`) is the same flat list,
  and it is the surface used *during capture* — the one place where scrolling
  past forty rows actually costs something.
- **Both filter sheets** (`agenda_filters_sheet.dart`,
  `calendar_filter_sheet.dart`) render one `FilterChip` per category in a
  `Wrap`, which grows without bound and buries every other section.

`markdown_settings_page.dart` already solves search + reorder + hide for
shortcuts and utility buttons. Reuse that vocabulary rather than inventing a
second one.

## Decisions taken

Resolved 2026-08-29. Do not reopen without a reason to.

### 1. Hidden means archived, not filtered

A hidden category is dropped from the pickers, the calendar filter sheet and
the agenda chips. Events already carrying it **still render on the calendar in
their own colour**. Deleting stays the way to remove data.

`CalendarPageLoaded.hiddenCategoryIds` is transient bloc state that resets to
`{}` on every load, and the `calendar-events` skill states that filter is
render-time only *by design* — the deliberate inverse of skips. Seeding it from
a persisted flag would create two sources of truth that can disagree, with no
way to tell which the user meant. The motive here is scale, and what breaks at
forty categories is the picker, not the grid.

If hidden-off-the-grid is ever wanted, it ships as a separate slice that
persists **the filter** as its own setting — never by overloading the category
row.

### 2. Icon keywords are English, in code, unlocalized

Keywords are match-only — never rendered — so the AppLocalizations rule does
not reach them. 300 icons across en/de/ro would be ~1000 ARB entries nobody
reads. Per-locale reachability comes from the **group labels**, which are
already localized and join the searchable fields: a German user typing
`Ernährung` still lands on the nutrition section.

This is a deliberate, documented exception to the l10n rule. State it in the
`calendar_icons.dart` doc comment.

### 3. Letters ship regardless of the tree-shake spike

A failed `--tree-shake-icons` spike commits us to the `CategoryGlyph` fallback,
not to dropping the feature. The spike **prices** A3 (pass = half session, fail
= full session); it does not gate it.

## Architecture stance

- **The management page stays service-direct. No `CategoryBloc`.** The page
  already documents that choice ("the same service-direct pattern the holiday
  settings use"). Search and reorder are local UI state, mutations go through
  `CategoryService`, and the facade's `revision` bump is what the calendar
  reacts to. A bloc would be a new pattern for zero consumers.
- **Actions key on ids, never on indices.** The shortcuts page carries
  `({item, index})` records because it mutates local lists by position; this
  page mutates by id through the service, so filtered views need no index
  bookkeeping. The only positional surface is the reorder drop callback, which
  maps its render index to the id list before it leaves the widget.
- **One search grammar, three surfaces.** `SettingsQuery` decides membership,
  `FuzzyRank` decides order. `calendar_icons.dart` owns the icon index (A1);
  `category_search.dart` owns category ranking (B3) and *consumes* the icon
  index rather than re-folding keywords. The markdown engine's
  one-grammar-two-surfaces rule, applied here.
- **v33 stays a plain column.** `calendar_categories` has no CRDT fields today.
  Giving it `hlcTimestamp` / `deviceId` / `version` is real work belonging to
  the cloud-sync roadmap's category phase — not smuggled into a hide flag. One
  concern per migration.

## Slices

Ten slices. Each ships value on its own.

### A1 — Searchable icon picker  (catalog SHIPPED, picker UI pending)

Ships: typing `run` narrows to running icons, across the existing 63, before a
single new icon lands.

1. Collapse the catalog to one source. Introduce
   `CalendarIconEntry(key, icon, keywords)`; `groups` holds entries; derive the
   lookup map from it. `forKey(String?)` keeps its signature and its O(1) cost,
   so **no caller changes**.
2. English keywords for all 63 existing entries.
3. Precompute folded search text (key with `_` → space, joined keywords) into a
   static `late final` index built on first touch. A keystroke is then
   `contains` over prebuilt strings, not `FoldedText.of` allocations across the
   catalog. That budget is microseconds — **the filter stays synchronous, no
   debounce**. Localized group labels are folded once per sheet open (they
   change with locale, the catalog does not) and joined into the same match set.
4. `IconPickerSheet` becomes stateful; `SettingsSearchField` under the title.
   Empty query keeps today's grouped sections; an active query renders one flat
   result `Wrap`. Membership via `matchesSettingsQuery`, ordering via
   `FuzzyRank.score` — which respects `fuzzy_rank.dart`'s own rule that it ranks
   but never decides what matches.
5. Empty state with a clear action.

**Watch:** `_byKey` is `const` today and `forKey` runs on render paths
(`CalendarCategories.iconFor` feeds `day_summary_resolver.dart` and
`agenda_list_view.dart`). The derived map must be built once, never per call.

Tests (`test/constants/calendar_icons_test.dart`): keys unique; every `groups`
entry resolves through `forKey`; **every `CalendarCategories.builtInSeeds` icon
key exists** (makes the standing comment in `calendar_categories.dart`
enforceable); every entry has ≥1 keyword; sample queries return expected keys.

Files: `constants/calendar_icons.dart`, `widgets/icon_picker_sheet.dart`,
ARB ×3 (`searchIcons`, `noIconsMatch`).

### A2 — Expand the catalog (~63 → 300)

Twelve new groups: **work** (work, groups, handshake, business_center, badge,
phone_in_talk, co_present, description, meeting_room), **education** (school,
menu_book, history_edu, quiz, backpack, draw, translate), **health**
(medical_services, vaccines, medication, healing, local_hospital,
medical_information, bloodtype, hearing), **home** (home, cleaning_services,
local_laundry_service, kitchen, chair, yard, plumbing, handyman, construction,
key), **finance** (payments, savings, account_balance, credit_card,
receipt_long, request_quote, trending_up, redeem, shopping_cart), **foodDrink**
(local_pizza, lunch_dining, breakfast_dining, ramen_dining, bakery_dining,
icecream, liquor, local_bar, egg, set_meal), **transport** (directions_car,
directions_bus, train, tram, local_taxi, two_wheeler, electric_scooter,
local_gas_station, ev_station, commute, luggage), **entertainment** (movie,
music_note, headphones, photo_camera, palette, brush, theater_comedy, mic,
piano, tv, festival), **people** (people, volunteer_activism, church, mosque,
synagogue, nightlife, diversity_3, child_care, elderly), **nature** (sunny,
cloud, ac_unit, umbrella, park, forest, water, eco, thunderstorm, nights_stay,
pets, agriculture), **tech** (computer, phone_android, wifi, cloud_upload, code,
build, memory, print, storage), **symbols** (circle, square, bookmark, label,
priority_high, warning, check_circle, block, lock, shield, push_pin).

1. Add the `IconGroupId` values. The `switch` in `_groupLabel` is sealed over
   the enum, so the compiler enumerates every missing label.
2. Entries plus keywords, group by group.
3. An `iconGroup<Name>` ARB trio per new group.
4. Write the additive-only rule into the file's doc comment.
5. **Recently used** — the feature that makes 300 icons feel small. A `Recent`
   pseudo-group pinned above the catalog: the last ~12 picked keys, most recent
   first, persisted as CSV through `SettingsService` + a new
   `SettingsKeys.recentIconKeys` (never a raw prefs key). `IconPickerSheet`
   records the pick on pop; unknown keys dropped on read, the same
   forward-compatible parsing every calendar setting uses. Hidden while a query
   is active — search results are already the shortlist.

> **Hard rule.** Icon keys are persisted — `calendar_categories.icon_key`,
> `calendar_events.icon_key`, `calendar_event_templates` and the fasting
> appearance settings all store them. **Additive only: never rename or delete a
> key that has shipped.** To retire an icon, drop it from `groups` but keep it
> resolvable in the lookup map.

Splits cleanly: **A2a** groups + the ~150 everyday icons, **A2b** the long tail
and a keyword pass.

### B1 — Persisted reorder  (DAO + service SHIPPED, drag UI pending)

Ships: drag categories into your own order and it sticks — in the picker, the
calendar filter sheet, the agenda chips and the templates page at once, because
every one of them reads `CalendarCategories.all`.

**No schema change**; `sort_order` already exists.

1. `CalendarCategoryDao.reorder(List<String> idsInOrder)` — one `batch()` in a
   transaction writing dense `0..N-1` plus `updated_at`. Dense values matter:
   `CalendarCategories._byOrder` tie-breaks on `id`, so duplicate orders shuffle
   on their own.
2. `CategoryService.reorder(...)` → DAO → `_load()`, which republishes the
   facade and bumps `revision`.
3. Page becomes `ReorderableListView.builder`, lifting the drag proxy and handle
   pattern from `markdown_settings_page.dart`: a `ReorderableDragStartListener`
   handle in `leading`, a `ReorderableDelayedDragStartListener` around the card.
   Optimistic `setState` against a local id order, then persist.
4. **Serialize the persists.** Two quick drags racing two async `reorder` calls
   can land out of order and resurrect the first arrangement. Chain each write
   onto the previous one's future and always send the *current* local order, so
   the last write is the whole truth regardless of arrival order.
5. Overflow menu gets **Sort A–Z** — one `reorder()` over labels sorted with the
   current locale's fold. The escape hatch for anyone who reaches forty
   categories before caring about manual order.

Built-ins and customs interleave freely — someone will want *Work* first.
`_seedBuiltIns` uses insert-if-missing and never rewrites existing orders, so a
future built-in still lands at its catalog index, possibly mid-arrangement. That
is existing documented behaviour; leave it.

Tests: order persists across reload; `CalendarCategories.all` reflects it;
`revision` bumps.

#### Drag behaviour at scale

At forty categories the drag crosses more than one screen, so edge auto-scroll
is load-bearing. **Flutter provides it — the work is not breaking it.**

Verified against Flutter 3.44.2,
`packages/flutter/lib/src/widgets/reorderable_list.dart`:
`SliverReorderableListState.didChangeDependencies` binds an
`EdgeDraggingAutoScroller` to `Scrollable.of(context)` and pumps it from
`_dragUpdate`. `autoScrollerVelocityScalar` defaults to
`_kDefaultAutoScrollVelocityScalar = 50`. Dragging a row to the top or bottom
edge scrolls the list, in both directions, with **zero configuration**.

The catch is `Scrollable.of(context)` — the *nearest enclosing* scrollable:

- **Correct:** `Column(children: [searchField, Expanded(child:
  ReorderableListView.builder(...))])`. The search field is a fixed header, the
  list owns the only scrollable, and the auto-scroller binds to the thing that
  actually scrolls.
- **Broken:** `SingleChildScrollView(child: Column(children: [searchField,
  ReorderableListView(shrinkWrap: true, physics: NeverScrollable...)]))`. The
  list builds its own inner `CustomScrollView`, `Scrollable.of` finds *that*, and
  it has no scroll extent — so `startAutoScrollIfNecessary` has nowhere to go.
  Dragging to the edge does nothing while the outer view is the one that needed
  to move. This is the trap; do not nest the list in an outer scroll view.

`markdown_settings_page.dart` uses `SliverReorderableList` inside a
`CustomScrollView` — also correct, since the sliver shares the outer scrollable
— but that shape exists only because the page has many sections. The categories
page is one list; prefer the simpler `Column` + `Expanded` form.

Three more, all cheap:

- **Unfocus the search field on drag start.** An open keyboard halves the
  viewport, which halves the usable drag region. (A *query* cannot be active
  during a drag — B3 disables reorder while filtering — but focus with an empty
  field can.)
- **Leave `autoScrollerVelocityScalar` at its default** until it is checked on
  device. At ~72px rows, forty categories is ~2900px against a ~700px viewport;
  if the crawl feels slow, that parameter is the knob. Do not pre-tune blindly.
- **Never reload the list mid-drag.** `SliverReorderableList.didUpdateWidget`
  calls `cancelReorder()` whenever `itemCount` changes, so any async
  `_refresh()` that lands during a drag and changes the row count silently kills
  it. The optimistic-then-persist order already avoids this (the write happens on
  drop); just don't add a service-revision listener that rebuilds the list from
  under an active drag.

**The real fix for long drags is not scrolling faster.** Dragging row 40 to the
top is miserable at any velocity. Two escapes make it rare:

1. **Sort A–Z** (above), and
2. **Move to top** as the first entry in the options popup that B2 introduces —
   one tap, no drag, and it covers the dominant case of promoting a category you
   have started using a lot. It is one `reorder()` call with the id moved to
   index 0. Add it when that menu lands.

### B2 — Hide a category (schema v33)  (schema + facade + service + backup SHIPPED; consumer surfaces pending)

Written against Decision 1 (hidden = archived).

1. `_migrateV32ToV33`:
   `ALTER TABLE calendar_categories ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0`,
   guarded by `PRAGMA table_info` so it is idempotent. Bump
   `DatabaseSchema.currentVersion` to 33 **and add the column to the create
   path**, or `schema_parity_test` fails — which is exactly its job.
2. Table, model `isHidden` + `copyWith`, then `build_runner`.
3. `CategoryService` mapping; `exportData` writes `'isHidden'`, `importData`
   reads it as `?? false`. **No backup version bump** — additive, and an older
   backup restores everything visible. Same precedent as v19 / v20.
4. `updateCache` builds a second unmodifiable list, `visible`.
   **`all` must keep returning everything** — drop a hidden category from it and
   `resolve()` falls through to `other`, repainting every one of its events grey.
5. Point `CategoryPickerSheet`, `CalendarFilterSheet`, `AgendaFiltersSheet` and
   `UpcomingAgendaView` at `visible`. The management page shows everything,
   dimmed at `Opacity(0.5)` like the shortcuts list. *(On the wave route the
   first three are rewritten by C and D anyway — make the swap there rather
   than editing those files twice.)*
6. **Guard: every surface holding a selection renders `visible` plus its own
   selected ids.** The picker must still list the event's current category when
   hidden, or opening an old event's editor quietly offers to reassign it; the
   agenda's allowlist chips must still show a hidden id sitting in
   `UpcomingAgendaFilters.categoryIds`, or the user cannot un-select a filter
   they can no longer see. One helper — `visiblePlus(Iterable<String> keep)` on
   the facade — so the rule is written once. `CalendarFilterSheet._clearAll`
   switches to `visible` ids for the same reason.
7. Row gets a `visibility` / `visibility_off` button and a `PopupMenuButton`
   carrying **Move to top**, Hide/Show, Edit, Delete — the "category options"
   menu, which un-crowds a trailing row now holding three actions. Built-ins can
   be hidden; they still cannot be deleted. *Move to top* belongs to B1's
   concern (see "Drag behaviour at scale") but ships here, because this is the
   slice that introduces the menu to put it in.
8. Hiding leaves `sort_order` untouched, so **unhiding restores the category to
   its old position** — the behavioural edge over delete-and-recreate. It falls
   out of the design for free; state it in the docs so it survives as intent.

Tests: hidden absent from `visible`, present in `all`; a hidden category still
resolves for an event using it; backup round-trips the flag; a pre-v33 backup
imports visible.

Same change updates the schema-lineage line in the `calendar-events` skill,
`docs/calendar-events-feature.md`, and the category section of
`COPILOT_CONTEXT.md`.

### B3 — Search the category list  (ranking SHIPPED, search field pending)

1. New `lib/utils/category_search.dart` holding one ranking function, shared by
   the page and the picker sheet so the two cannot drift:

   ```
   rankCategories(SettingsQuery, Iterable<CalendarCategory>, AppLocalizations)
     → List<({CalendarCategory category, int rank})>
   ```

2. Membership via `matchesSettingsQuery` over the localized label, the raw
   `name`, the icon key with underscores as spaces, the icon keywords and the
   localized group label.
3. **Name is the priority**, expressed as a rank band rather than a filter:
   order by `FuzzyRank.score` on the name alone, and demote an icon-only hit
   below every name hit. An icon match still gets you there, never ahead of a
   name.
4. Sort on `(band, sortOrder)` explicitly — **`List.sort` is not stable in
   Dart**, so a bare band sort reshuffles same-band rows between rebuilds. The
   agenda's summary cards hit exactly this; inherit the fix.
5. `SettingsSearchField` shown only above `AppConstants.listSearchThreshold`
   (12) — consistent with the rest of settings, and it keeps the page clean for
   someone still on the nine built-ins.
6. Empty state.

> **Required.** Reorder must switch off while a query is active — render indices
> no longer map to real positions. Copy the shortcuts fix exactly: fall back to
> a plain `ListView` and grey the drag handle **in place**, so clearing the query
> does not shift every row sideways.

Tests: a name hit outranks an icon-only hit for the same query; diacritics fold
(`sanatate` finds `Sănătate`); an icon keyword reaches a category whose name
does not match.

### B4 — Create from the app bar

`SettingsAppBar` already accepts `actions`, so this needs **no shared-widget
change** — it is just what this one page passes.

1. Drop the `FloatingActionButton.extended`.
2. Add `IconButton.filledTonal` with `Icons.add_rounded` and a `createCategory`
   tooltip. A filled *icon* button rather than a labelled one because
   *Kalenderkategorien* plus a text button overflows the bar.
3. Return the list's bottom padding from 96 to the normal page value — that 96
   was FAB clearance.

Tradeoff: a bottom-right FAB is the better one-handed target, and this project's
bar is that a design should survive one-handed use. Two things make the move
acceptable — the app bar is pinned so the action never scrolls away, and
creating *during capture* stays where the thumb is (the picker sheet keeps its
own add affordance in C). If it feels wrong on device, keep both.

### B5 — Usage counts  (countByCategory SHIPPED, rendering pending)

Ships: every row says how many events use it, and deleting says exactly what it
will do — what makes hide-vs-delete an informed choice.

1. `CalendarEventDao.countByCategory()` — one
   `SELECT category, COUNT(*) ... WHERE is_deleted = 0 GROUP BY category`
   returned as `Map<String, int>`. **One statement for the whole page, never a
   count-per-row loop** — `test/database/query_count_test.dart` exists to catch
   that shape; add this query to its guard.
2. The page loads the map alongside the categories and renders it in the row
   subtitle (*12 events*, ICU plural, joining `categoryDefault` for built-ins).
   Loaded once per page entry, refreshed after delete; advisory, not live state.
3. Delete confirmation becomes concrete: *"Move 12 events to Other and delete
   Fitness?"* at `count > 0`, today's wording at zero. Same `AppDialogs.confirm`,
   sharper `content`.
4. Once B2 has landed, a nonzero count earns one extra sentence suggesting
   **hide** instead — deleting recolours history grey, hiding does not.

### C — The picker sheet

1. `CategoryPickerSheet` becomes stateful; `show()` keeps its signature.
2. Title row gains a trailing `IconButton.filledTonal` add button — the same
   affordance as B4, so the two surfaces read as one system.
   `SettingsSearchField` below it.
3. **No autofocus.** The sheet's job is picking; raising the keyboard on every
   open pushes the list up and costs a tap to dismiss.
4. Rows come from the shared `rankCategories` over `CalendarCategories.visible`,
   plus the selected id even when hidden.
5. Replace the trailing "Create category" row with an empty state that prefills
   what was typed — *Create "Dentist"*. One additive parameter:
   `CategoryEditorSheet.show(context, initialName:)`.
6. The editor sheet grows a **soft** duplicate guard: when the trimmed name folds
   equal to an existing category's label, show a helper line under the field
   (*"Dentist" already exists*) **without blocking Save**. At forty categories
   near-duplicates are how the set rots, and a hidden duplicate is the moment the
   user learns hiding exists. Never a hard block — a custom *Cardio* alongside
   the built-in may be exactly what someone wants.
7. Raise `heightFactor` 0.7 → 0.85 now there is a search field; keep the
   bottom-clearance maths, which `sheet_bottom_clearance_test` guards.

### D — Filter sheets at scale

Ships: the two filter sheets stay one screen tall at forty categories.

B2 points these at `visible`, which drops hidden categories — but a user with
forty *active* ones is still the case that breaks. Both
`agenda_filters_sheet.dart` (`_buildCategories`) and `calendar_filter_sheet.dart`
render a `Wrap` of one `FilterChip` per category. At ~140px a chip and 2–3 per
row, forty categories is 700–1000px of chips, which buries every other section
in the sheet.

**The panel's summary chip is already correct** — `upcoming_agenda_view.dart`
renders one `Categories (3)` chip, and `restrictiveFilterCount` counts categories
as **one** restriction, not N. Do not "fix" either; they are the pattern the
sheets should copy.

1. **`CategoryPickerSheet` grows a multi-select entry point**, mirroring
   `CalendarDatePickerSheet.pickSingle` / `.pickMulti` exactly — the established
   local precedent for one sheet serving two arities:

   ```
   CategoryPickerSheet.pickSingle(context, selectedId:)  → String?
   CategoryPickerSheet.pickMulti (context, selected:)    → Set<String>?
   ```

   Both inherit C's search field, ranked rows, `visiblePlus` and the add button
   for free — which is the whole reason D comes after C rather than duplicating
   a second searchable list.

2. **`pickMulti` is semantics-free** (set in, set out), like its date twin, so it
   can serve an allowlist and a denylist without knowing which it is:
   `agenda_filters_sheet.categoryIds` is an **allowlist** (empty = all);
   `calendar_filter_sheet._hidden` is a **denylist** (empty = show all). The
   caller inverts. **Unlike `CalendarDatePickerSheet.pickMulti`, empty must not
   collapse to `null`** — empty is a real, meaningful state on both sides here.
   Say so at the call site; the date sheet's collapse is the thing someone will
   copy by reflex.

3. **Both sheets swap the `Wrap` for a `_PickerTile`-shaped row** above
   `AppConstants.listSearchThreshold` (12) and keep today's chips below it.
   Short sets are genuinely better as chips — one tap, no navigation — and the
   threshold means a user on the nine built-ins sees **zero change**, which also
   keeps `test/widgets/agenda_filters_sheet_test.dart` passing untouched.
   The tile reads: leading `Icons.category_rounded`, title *Categories*,
   subtitle either *All categories* or the first two or three names plus
   *+N more* (two lines max), trailing chevron.
4. Do **not** re-add a chip row for the selection beneath the tile — twenty
   allowlisted categories would rebuild the exact wall the tile removed. The
   subtitle names them and the panel's removable `Categories (N)` chip already
   undoes them.
5. `calendar_filter_sheet` keeps its **Select all / Clear all** header buttons
   operating on the whole set directly, so the common "show everything again"
   reset never needs the sub-sheet. (B2 already switches `_clearAll` to
   `visible` ids.)

A sheet opening a sheet is established here — `EventEditorSheet` →
`CategoryPickerSheet`, `CategoryEditorSheet` → `IconPickerSheet`. It also
preserves `AgendaFiltersSheet`'s documented invariant: the sub-sheet returns
into the **local draft**, so nothing re-runs the agenda scan behind the sheet
until Apply.

Files: `widgets/category_picker_sheet.dart`, `widgets/agenda_filters_sheet.dart`,
`widgets/calendar_filter_sheet.dart`, ARB ×3 (`categoriesAllSelected`,
`categoriesNSelected`, `categoriesMore`).

### A3 — Letters and digits

Ships: A–Z and 0–9 as glyph "icons" — the letter-avatar look Google Calendar and
Outlook give their categories.

`Icon` renders `String.fromCharCode(icon.codePoint)` styled with
`icon.fontFamily`. A `const IconData(0x41)` carrying **no** font family therefore
renders a plain "A" in the ambient font — which means letters can be ordinary
catalog entries and every downstream surface, from `DaySummaryEntry.icon` to the
day bars, works unchanged.

**Spike first:** add one letter key, run `.\build_release.bat arm64`, confirm the
release build survives `--tree-shake-icons` (on by default) and the glyph renders
on device. Per Decision 3 this prices the slice, it does not gate it.

- **Pass** → `letter_a`…`letter_z`, `digit_0`…`digit_9` in two new groups.
  Keywords are the character plus its name. Ranking earns its keep: a bare `a`
  token matches half the catalog, so A1's exact-key tier must sort letters first.
- **Fail** → `CategoryGlyph` widget plus `CalendarIcons.letterFor(key)`, swapped
  in at every display site while `iconFor` keeps its `IconData` return for
  compatibility. A ten-site change; the slice grows to a full session.

Cosmetic either way: a letter at `fontSize: 24` sits smaller and lower than a
Material glyph and takes the ambient weight. Accept, or add an optional
`sizeScale` to `CalendarIconEntry` read only by display surfaces.

Optional polish: an *Auto — first letter of the name* entry atop the picker.

## Execution order

Two routes. Both respect the same dependency graph:
A1 → A2; A1 → B3; B1 → B3; B2 → C; B3 → C; C → D. B4 and B5 are independent.

### Multi-session (one slice at a time)

`A1` → `A2` → `B1 + B4` → `B2 + B5` → `B3` → `C` → `D` → `A3` (any time after A1).

### Single-session (waves)

**Five slices — B1, B2, B3, B4, B5 — all rewrite
`calendar_categories_page.dart`.** Across sessions that is fine; in one session
it is five passes over the same `build` method. Collapse them into one rewrite,
and batch the slow tooling (`build_runner`, `gen-l10n`) instead of running it per
slice.

| Wave | Contents | Model | Commit after |
| --- | --- | --- | --- |
| 1 ✅ | B2 schema (table, migration, `currentVersion`, create path, model); A1 catalog restructure; B2 facade + service + backup | Opus | yes |
| 2 ✅ | B1 DAO + service; B5 `countByCategory`; B3 `category_search.dart` | Sonnet | yes |
| 3a | A1 picker UI; **one rewrite** of `calendar_categories_page.dart` carrying B1+B2+B3+B4+B5; `UpcomingAgendaView`'s chip source | Opus | yes |
| 3b | C, then D (D needs C's `pickMulti`) | Opus preferred, Sonnet viable | yes |
| 4 | A2 icons + keywords + recent-icons; A3 spike + letters | Sonnet | yes |

**Why 3 splits.** It was already the densest wave, and D pushed it over: nine
files of substantive UI plus ~15 ARB keys ×3, with an internal dependency chain
(page rewrite → C → D) that loses the *capture-time* surfaces first if the wave
runs out. 3a is the management page and everything it needs; 3b is the two
consumption surfaces, which share `rankCategories` and `visiblePlus` and want to
be built together. Each ships standalone value.

**B2's "consumer surfaces" are not a separate step.** Three of the four files
that need pointing at `visible` / `visiblePlus` — `CategoryPickerSheet`,
`CalendarFilterSheet`, `AgendaFiltersSheet` — are rewritten by C and D anyway, so
do the swap *inside* those rewrites rather than touching the same files twice.
Only `UpcomingAgendaView`'s chip source is standalone; it rides 3a.

**3b is the delegation candidate.** By the time it runs, `rankCategories` (wave
2) and `visiblePlus` (wave 1) both exist and this document specifies C and D
down to the two traps (semantics-free `pickMulti`, no empty-collapse). That
keeps Opus to waves 1 and 3a if budget is tight.

**Session grouping.** Waves must run in order; the session boundaries are the
choice. Four sessions: `1 + 2` · `3a` · `3b` · `4`. Wave 2 is small enough that
opening a fresh session for it costs more context than it saves, so it rides
with 1 — but only **after** `flutter test test/database/` passes, which is the
gate on the migration. **3a always runs alone**: it is the densest wave and the
one where a mid-rewrite interruption hurts most. Under tight budget, `3b + 4`
can share a Sonnet session, in that order.

Start each session fresh against this document rather than continuing the
previous one — the plan is written to be re-entered cold, and a stale
conversation is the most expensive thing you can carry into a wave.

Run `flutter test test/database/` immediately after wave 1 — if the migration is
wrong you want to know before ten UI files sit on top of it.

**A2 is deliberately last** despite being first in the original framing. It is
the only slice that is pure additive content with zero architectural risk, and
nothing depends on it (B3 needs A1's keyword *mechanism*, not the 300 icons).
Stopping after 3a leaves a fully working searchable / reorderable / hideable
management page; stopping after 3b adds the capture and filter surfaces. Both
are honest stopping points over the existing 63 icons. Stopping mid-A2 costs
nothing — it is a list.

Wave 4 is also the best delegation in the plan: highest token output, lowest
reasoning demand.

## Verification

| After | Run |
| --- | --- |
| Wave 1 | `dart run build_runner build --delete-conflicting-outputs`, `dart analyze lib`, `flutter test test/database/` |
| Wave 2 | `dart analyze lib`, `flutter test test/utils/ test/services/` |
| Wave 3a | `flutter gen-l10n` (check `untranslated.txt`), `dart analyze lib`, `flutter test` |
| Wave 3b | `flutter gen-l10n`, `dart analyze lib`, `flutter test test/widgets/` then `flutter test` |
| Wave 4 | `dart analyze lib`, `flutter test`, `.\build_release.bat arm64` for the A3 spike |

## Invariants — do not break

1. **Icon keys are persisted in four places. Additive only** — never rename,
   never remove.
2. **`CalendarCategories.all` keeps every category.** Hidden ones are excluded
   only from a separate `visible` list.
3. Every mutation goes through `CategoryService._load()` → `updateCache` →
   `revision++`. The grid's per-day memo keys on that counter, so a rename or
   recolour that skips it paints stale.
4. `forKey` stays O(1) off a map built once — it runs on render paths.
5. Reorder and filtering are mutually exclusive in the UI, always.
6. **The reorderable list must own the nearest enclosing `Scrollable`.** Edge
   auto-scroll binds to `Scrollable.of(context)`; nesting the list in an outer
   scroll view with `shrinkWrap: true` silently disables dragging past the fold.
7. The calendar's `hiddenCategoryIds` filter stays transient and render-time
   only. `is_hidden` is a different thing wearing a similar name — keep the two
   straight in the code and in the docs.
8. Any surface holding a selection renders `visible` **plus its own selected
   ids**, through the one `visiblePlus` helper — never a per-surface
   re-derivation.
9. Whole-page data comes from single statements — one `GROUP BY` for counts, one
   batch for reorder. `query_count_test` is the guard.
10. Ranked lists sort on `(band, sortOrder)` — `List.sort` is not stable in Dart.
11. **No surface renders one chip per category over the full set.** A bounded
    summary (`Categories (3)`) plus a sub-sheet is the pattern; a `Wrap` over
    `CalendarCategories.all` is the anti-pattern. `restrictiveFilterCount`
    counting categories as one restriction is part of this and must stay.

## Deferred, not planned here

- **CRDT fields on `calendar_categories`** — belongs to the cloud-sync roadmap's
  category phase, not to a hide flag.
- **A persisted calendar category filter** — the "hidden also means off the grid"
  reading of Decision 1, if it is ever wanted, as its own slice.
- **Category groups / nesting.** Forty flat categories with search and hide is
  the target; a hierarchy is a different feature with its own data model.
- **Per-category default event fields** (duration, priority, reminder). Adjacent
  and tempting, but it is `calendar_event_templates`' job — a category is a
  taxonomy, a template is a prefilled event.
