# Calendar & Events — Feature Reference

A deep, implementation-aware description of the calendar/events subsystem in
`anta`, written as of schema **v14**; the **Addendum (schema
v15–v18)** at the end of this document covers everything added since —
panel modes, the upcoming agenda, the day timeline, `.ics` export, and the
priority-scale inversion. This document focuses on the **events** feature
plus the **public-holiday** subsystem it depends on. Everything below is
grounded in the actual code paths in [lib/](../lib/) — file references are
linked.

> Schema lineage relevant to this subsystem: **v10** created the calendar
> tables; **v11** added the Until bound + time-of-day columns; **v12** added
> `description`; **v13** added holiday profiles; **v14** added the optional
> event ↔ note link (`note_id`); **v15** added the data-driven
> `calendar_categories` table (user-creatable categories); **v16** added
> `color_value` / `tint_icon` / `priority` columns; **v17** added the
> `suppressed` flag on `public_holidays`; **v18** inverted the stored
> priority scale (data-only: `p -> 6 - p`, see the Addendum); **v24** added
> the sparse `calendar_event_occurrences` table (per-occurrence description
> overrides, §6.6); **v33** added `calendar_categories.is_hidden` (§2.3);
> **v34** added the nullable `calendar_events.show_in_day_rail` (per-event
> day-rail override, NULL = auto — see the v34 addendum). The
> recurrence **interval** ("every N …") shipped without a migration — it rides
> inside the existing `rule_payload`.

---

## 1. Product purpose

The calendar lives inside an offline-first personal tracker. It is **not** a
general-purpose calendar (no meetings, no invites, no sync). Its purpose is to
let one person:

- **Plan recurring commitments** — schedule repeating sessions (3×/week, every
  workday, weekends only, etc.) so the calendar answers "what should I do
  today?". Training was the original case and is still the densest one.
- **Annotate the year** — mark holidays, fasting periods, birthdays,
  competitions, deload windows, measurements, rest days.
- **Stay context-rich on a single device** — every event is local SQLite,
  with no account, no cloud, and survives device wipe via the JSON backup.

Design principle: the calendar must be useful **the second the user installs
the app**, with zero setup. That is why public holidays are pre-seeded and
why one-time events are the default.

---

## 2. Domain model

### 2.1 [`CalendarEvent`](../lib/models/calendar_event.dart)

The single value object representing an event. It is `Equatable` and
immutable; mutation is done through `copyWith`.

| Field           | Type                       | Notes                                                                                              |
| --------------- | -------------------------- | -------------------------------------------------------------------------------------------------- |
| `id`            | `String`                   | UUID v4, generated client-side. Stable across edits.                                               |
| `title`         | `String`                   | User-entered, ≤ 120 chars (UI-enforced). Trimmed on save.                                          |
| `categoryId`    | `String`                   | Id of a `CalendarCategory` (built-in enum-name like `gym`, or a custom UUID). Resolved to color/icon/label at render time; an unknown id falls back to `other`. |
| `startDate`     | `DateTime` (date-only UTC) | Anchors recurrence math. For one-time events this *is* the event date.                             |
| `rule`          | `RecurrenceRule`           | Sealed hierarchy — see §3.                                                                         |
| `endDate`       | `DateTime?` (date-only UTC) | Optional inclusive upper bound for recurring rules. `null` = "no end".                            |
| `time`          | `EventTime?`               | Optional time-of-day annotation (start minute + optional duration). `null` = all-day.             |
| `description`   | `String?`                  | **v12**. Free-form markdown, length capped by the `eventDescriptionLimit` setting (§6.6). `null`/empty = none. Stored verbatim. |
| `noteId`        | `String?`                  | **v14**. Optional link to a workout note (`notes.id`). Folder resolved at navigation time.        |
| `iconKey`       | `String?`                  | Key into the `CalendarIcons` catalog. `null` = use category default.                                  |
| `allDay`        | `bool` (derived)           | Computed as `time == null`. The persisted `all_day` column mirrors this on write only.            |

`CalendarEvent.occursOn(day)` is the central query. It:

1. Normalizes both `startDate` and `day` to date-only UTC.
2. Short-circuits to `false` if `endDate != null && target.isAfter(endDateUtc)`
   (the **Until** bound, applied at the model layer because it is orthogonal to
   the rule shape).
3. Otherwise delegates to `rule.occursOn(target, start)`.

### 2.2 Categories (data-driven since v15)

`CalendarEvent.categoryId` is a `String` referencing a row in the
`calendar_categories` table. Categories are **user-creatable**: built-ins are
seeded with stable ids equal to the historical `CalendarEventCategory` enum
names (`'gym'`, `'cardio'`, …) — which is exactly what `calendar_events.category`
already stored — so the migration needs **no event-data rewrite**. Each
category carries:

- A label — built-ins resolve a localized label by id
  (`CalendarCategories.labelOf` → `l10n.eventCategory*`); custom categories show
  their stored `name` verbatim.
- A color (`color_value`, 32-bit ARGB int) and an icon (`icon_key` into
  `CalendarIcons`).

The `CalendarEventCategory` enum survives only as the **built-in seed catalog**
and the source of localized built-in labels. Runtime lookups go through the
synchronous `CalendarCategories` facade (`byId`/`resolve`/`all`/`labelOf`/
`iconFor`), mirroring the `PublicHolidays` cache so render paths stay O(1) with
no `await`. An unknown id resolves to a fallback (`other`) so deleting a custom
category never corrupts its events; `CategoryService.deleteCategory` also
reassigns those events to `other` in a transaction. Built-ins cannot be
deleted. CRUD lives in `CategoryService`; the UI is `CategoryEditorSheet`
(name + icon + color) and `CalendarCategoriesPage` (§2.4), plus the add button
and the create-what-you-typed empty state in `CategoryPickerSheet` (§2.5). The calendar filter is a
hidden-id set (`CalendarPageLoaded.hiddenCategoryIds`), so new categories are
visible by default.

One built-in carries editor behavior: selecting **Birthday**
(`kBirthdayCategoryId`, a cake-iconed yearly category) on a still-one-time
event pre-fills a `YearlyRecurrence` so birthdays repeat every year with no
extra taps. It never overrides a recurrence the user already configured.

### 2.3 Hiding a category (v33) — archiving, not filtering

`calendar_categories.is_hidden` retires a category the user has stopped using
without deleting it. A hidden category is dropped from the pickers, the
calendar filter sheet and the agenda chips, but **events already carrying it
still render on the calendar in their own colour**. Deleting stays the way to
remove data, and it is what reassigns events to `other`.

That behaviour is a consequence of the shape rather than a special case:
`CalendarCategories.updateCache` builds `visible` as a **second** unmodifiable
list beside `all`, which keeps every row. Narrowing `all` instead would make
`resolve()` fall through to `fallback` and repaint the category's entire
history grey — the exact opposite of what hiding is for.

Three rules follow:

- **Choosing surfaces render `visible`.** Anything that offers a category to
  pick or to filter by.
- **Any surface holding a selection renders `visiblePlus(keep)`** — `visible`
  plus its own selected ids — through that one helper, never a per-surface
  re-derivation. The event editor must still list the category its event
  already carries, or opening an old event quietly offers to reassign it; the
  agenda's allowlist chips must still show a hidden id sitting in
  `UpcomingAgendaFilters.categoryIds`, or the user cannot un-select a filter
  they can no longer see. It returns `visible` itself when nothing hidden is
  kept, so the common case allocates nothing and stays identity-stable for
  widget memos.
- **The management page shows everything**, hidden rows dimmed.

Hiding leaves `sort_order` untouched, so **unhiding restores the category to
the position it held** — the behavioural edge hiding has over deleting and
re-creating. Built-ins can be hidden; they still cannot be deleted.

`is_hidden` is **not** `CalendarPageLoaded.hiddenCategoryIds`. The latter is
transient bloc state that resets to `{}` on every load and is render-time only
by design (the deliberate inverse of skips — see the v30 addendum). It is never seeded from
the persisted flag: two sources of truth for "hidden" that can disagree leave
no way to tell which the user meant. If "hidden also means off the grid" is
ever wanted, it ships as its own persisted **filter** setting.

The migration is one `ALTER TABLE … ADD COLUMN` with a `PRAGMA table_info`
guard, and the column is deliberately **plain**: `calendar_categories` carries
no CRDT fields, and giving it `hlc_timestamp` / `device_id` / `version` belongs
to the cloud-sync roadmap's category phase rather than riding in on a hide
flag. Backup gains an additive `isHidden` key with **no version bump** (the v19
/ v20 precedent) — a pre-v33 archive cannot describe a hidden category because
none existed, so restoring everything visible is exactly what it recorded. The
flag is read by *type test* rather than a cast, so a junk value costs the flag
rather than the whole category row.

Design record: `docs/category-scaling-roadmap.md`, which also owns the wider
plan for keeping the set usable at ~40 categories (searchable icon picker,
persisted reorder, search, usage counts, bounded filter surfaces).

### 2.4 Managing categories at scale

[`CalendarCategoriesPage`](../lib/pages/calendar_categories_page.dart) is the
one surface that lists **every** category, hidden rows included and dimmed to
`Opacity(0.5)` like the shortcuts list. It stays **service-direct** — no
`CategoryBloc`: search and order are local UI state, mutations go through
`CategoryService`, and the facade's `revision` bump is what the calendar reacts
to on return.

- **Reorder.** `ReorderableListView.builder` writing through
  `CategoryService.reorder`. **Every mutation on that service — create, update,
  hide, reorder, delete — is serialized onto one chain**, not just reorder: each
  ends in a `_load()` that republishes the whole facade, so two racing writes
  can republish out of order even when both land. The page therefore does the
  optimistic `setState` and hands over its *current* full local order, never a
  second chain and never a delta. Two details that are load-bearing rather than
  incidental: `updateCategory` leaves `sort_order`, `is_built_in` and
  `is_hidden` **absent** (callers hold a model captured earlier; order belongs
  to the drag and the archive flag to `setHidden` — a stale value undoes the
  drag and breaks the dense `0..N-1` ordering, or silently un-archives a
  category the user just retired from the un-awaited menu write), and the chain's
  tail starts **null** rather than a completed `Future`, because a
  `Future.value()` built in a field initializer schedules its continuations on
  the zone it was born in and would deadlock every widget test that awaits a
  mutation under `FakeAsync`. Because the local order leads
  the persisted `sort_order` until that write lands, an empty query renders the
  local list **directly** rather than through `rankCategories`, whose
  `sortOrder` tiebreak would snap the row back mid-drag. Escapes from a long
  drag: **Move to top** in the row menu and **Sort A–Z** in the app bar's
  overflow, both one `reorder()` call.
- **The list must own the nearest enclosing `Scrollable`** — `Column` +
  `Expanded`, never a `shrinkWrap` list inside an outer scroll view. Edge
  auto-scroll binds to `Scrollable.of(context)`, and an inner viewport with no
  extent silently disables dragging past the fold. The search field is a fixed
  header above it, and a drag start unfocuses it so an open keyboard cannot
  halve the drag region.
- **Search and reorder are mutually exclusive.** Above
  `AppConstants.listSearchThreshold` (12) the page shows a
  `SettingsSearchField` ranked by `rankCategories`; while a query is active the
  list falls back to a plain `ListView` and the drag handle greys **in place**,
  so clearing the query does not shift every row sideways.
- **Usage counts** come from one `GROUP BY` per page entry, exposed as
  `CalendarEventService.countByCategory()` — on the **event** service, since
  counting events is that domain's job and reaching this page always means the
  singleton is warm — never a count per row;
  `test/database/query_count_test.dart` is the guard. They are advisory:
  rendered in the row subtitle, refreshed after a delete, and folded into the
  delete confirmation, which at `count > 0` says what will move and suggests
  hiding instead.
- **Mutations fired from a menu callback are never awaited**, so each goes
  through one `_guarded` wrapper that catches and then reconciles with the
  service. A failed write springs the optimistic row back to what is stored
  rather than escaping as an unhandled async error.
- **The reorder chrome is shared.** `ReorderHandle`, `reorderDragProxy` and
  `ReorderLockedHint` live in
  [settings_reorder.dart](../lib/widgets/settings_reorder.dart), used by this
  page and by both reorderable lists in `markdown_settings_page.dart` —
  extracted for the same reason `SettingsSearchField` was. `ReorderHandle`
  keeps `index` (wire it to the list, or null when the list supplies its own
  default handles) separate from `enabled` (the visual grey).
- **Create moved to the app bar** (`IconButton.filledTonal`) from the FAB, so
  it never scrolls away and never collides with the list; creating *during
  capture* stays in `CategoryPickerSheet`.

[`IconPickerSheet`](../lib/widgets/icon_picker_sheet.dart) is searchable on the
same grammar: membership via `matchesSettingsQuery` over
`CalendarIcons.searchTextOf` — the prebuilt folded index, so a keystroke is a
`contains` over static strings and the filter stays synchronous and
undebounced — ordering via `FuzzyRank`, tie-broken by catalog position. An
empty query keeps the grouped sections; an active one renders one flat ranked
`Wrap`. The localized group labels are folded once per sheet open and joined
into the match set, which is how the deliberately unlocalized English keywords
stay reachable in de/ro.

The catalog is **216 entries across 24 groups**, and three things keep it
usable at that size:

- **An exact term outranks every `FuzzyRank` tier.**
  `CalendarIcons.isExactTerm(key, foldedTerm)` is true when the term *is* one of
  the entry's terms — its key read with underscores as spaces, or a whole
  keyword — rather than a fragment of one, and the picker ranks those in a band
  above `FuzzyRank.tierPrefix`. Without it a one-character query is useless:
  `FuzzyRank` scores a prefix of the whole search text, so `a` would rank
  `ac_unit`, `alarm` and `attach_money` above the **letter A**, whose text
  begins with "letter".
- **Recently used.** A section pinned above the catalog holding the last 12
  picked keys, newest first, persisted as CSV through `SettingsService`
  (`getRecentIconKeys` / `recordRecentIconKey`) under
  `SettingsKeys.recentIconKeys`. Unknown keys are dropped on read — an icon may
  be *retired* even though keys are additive-only — and duplicates collapse. It
  is hidden while a query is active, because search results are already the
  shortlist it exists to provide. It is a picker **section**, not an
  `IconGroupId`: the enum stays exactly the groups `groups` declares, and a test
  enforces that.
- **Letters and digits are ordinary entries.** `letter_a`…`letter_z` and
  `digit_0`…`digit_9` carry an `IconData` with **no font family**, so `Icon`
  paints the character in the ambient font and every surface that already
  renders an `IconData` — `DaySummaryEntry.icon`, the day bars, the row avatars
  — works unchanged. There is no `CategoryGlyph` and no `letterFor`. It also
  keeps them out of `--tree-shake-icons`, which subsets only the fonts a const
  `IconData` names; a release build with them present tree-shakes
  `MaterialIcons-Regular.otf` to a byte-identical size. Never give one a
  `fontFamily`.

Every tile carries a `Tooltip` of its key read with underscores as spaces —
216 unnamed buttons is what a screen reader would otherwise get.

### 2.5 Choosing categories at scale

[`CategoryPickerSheet`](../lib/widgets/category_picker_sheet.dart) serves two
arities off one sheet, mirroring `CalendarDatePickerSheet`:

```
CategoryPickerSheet.pickSingle(context, selectedId:)  → String?
CategoryPickerSheet.pickMulti (context, selected:)    → Set<String>?
```

Both render `visiblePlus(initialSelection)` — a hidden category the selection
already carries stays listed, subtitled *Hidden* so it does not read as an
ordinary row. The kept set is the selection the sheet **opened with**, not the
live one: keyed to the live set, un-ticking an archived row deleted it from the
list in the very next build, so the user could not change their mind and the
offered count could fall back under the search threshold mid-query. Both search
through the shared `rankCategories`, above
`AppConstants.listSearchThreshold` (12). There is **no autofocus**: the sheet's
job is picking, and raising the keyboard on every open pushes the list up and
costs a tap to dismiss. `heightFactor` is 0.85 now that a search field sits
above the rows. The title row carries the same `IconButton.filledTonal` add
button the management page's app bar does, and a query that matches nothing
offers to create what was typed — *Create "Dentist"* — through
`CategoryEditorSheet.show(context, initialName:)`.

That editor grows a **soft** duplicate guard: a trimmed name folding equal to
an existing category's label shows a helper line under the field (*"Dentist"
already exists*, or *… but is hidden* when the match is archived — usually
where a user first learns hiding exists) **without blocking Save**. Never a
hard block: a custom *Cardio* beside the built-in one may be exactly what
someone wants. It scans `all`, not `visible`, precisely so the hidden case is
reachable.

**`pickMulti` is semantics-free** — a set in, a set out — so it serves both
filter sheets without knowing which it is:
`UpcomingAgendaFilters.categoryIds` is an **allowlist** (empty = all) and
`CalendarFilterSheet._hidden` a **denylist** (empty = show all); the caller
inverts. **Unlike `CalendarDatePickerSheet.pickMulti` an empty result is not
collapsed to `null`** — empty is a real, meaningful state on both sides, and
swallowing it would make clearing the last row look like a dismissal. The date
sheet's collapse is the thing to not copy by reflex.

Above the same threshold both
[`agenda_filters_sheet.dart`](../lib/widgets/agenda_filters_sheet.dart) and
[`calendar_filter_sheet.dart`](../lib/widgets/calendar_filter_sheet.dart) swap
their per-category `FilterChip` `Wrap` for one shared `CategoryFilterTile`
(leading an overlapping cluster of up to three category colour discs, title
*All categories* or the first names plus *+N more*, trailing chevron) that
opens the sub-sheet. Below it they keep today's chips — short sets are
genuinely better as chips, one tap and no navigation, and a user on the nine
built-ins sees zero change.

Two things about that row are deliberate, both from a 2026-08-30 pass over
device screenshots. **It does not repeat the section label above it**: the
callers already head the section (*Categories* / *Event categories*), and a
card titled the same thing 35dp below was the one place in either sheet that
named itself twice — it read as a rendering bug. The label says what the
section is; the row's title line says what it is *set to*, and there is no
subtitle. And the **leading is a colour cluster, not `category_rounded`**:
every other category surface in the app identifies a category by a coloured
disc, so a lone monochrome glyph made this the one row that looked like
generic settings furniture. The cluster draws from the selection, or from the
whole offered set when `selectsAll` holds (they are all selected, so it is
honest), falling back to the glyph only when nothing is selected at all.
**No surface re-adds a chip row for the selection beneath the tile**: twenty
allowlisted categories would rebuild the exact wall the tile removes, the
subtitle already names them, and the agenda panel's removable
`Categories (N)` chip already undoes them (`restrictiveFilterCount` counts
categories as **one** restriction — that is the pattern, not a rounding
error). `CalendarFilterSheet` keeps its Select all / Clear all header buttons, so the
common "show everything again" reset never needs the sub-sheet. They are one
toggle on `allSelected` (`_hidden.isEmpty`), and their **asymmetry is
deliberate**: Clear all *unions* the visible ids into the denylist, so hiding
everything cannot accidentally un-hide an archived category already denied;
Select all *empties* the denylist outright, archived denials included, because
showing everything is exactly what it says — an archived category's events
already render on the grid in their own colour, and nothing here touches
`is_hidden`. The hazard the union guards is one-directional and has no mirror.
Making Select all subtract only the visible ids instead strands an archived
denial: `_hidden` never empties, the toggle never flips back, and the button
becomes a permanent no-op. (The union is in fact unreachable through the button
— Clear all only appears once `_hidden` is empty — but it is the correct
defensive shape and costs nothing.)

**Bulk selection in the picker (2026-08-30).** Multi mode carries a row under
the search field: `categoriesNSelected` over the whole selection on the left,
**Select all / Select none** on the right, each operating on the *listed* rows
— the filtered set while a query is live, since bulk-editing rows the search
has hidden would change what the user cannot see. Without it, narrowing fifty
categories to two costs forty-eight taps: the allowlist inversion opens every
row already checked, so the picker's very first state is a column of identical
ticked boxes with no count and no way out but one tap per row. Each button is
**disabled where it would be a no-op** (which is exactly Select all in that
opening state), or the enabled tint promises a change that costs a tap to
discover is absent. The agenda's own reset under the tile is worded as a
**verb** — `upcomingClearCategories` is *Show all categories*, not *All
categories*, which was byte-identical to `categoriesAllSelected`, the line the
tile shows when nothing is filtered; the same words sat twice within 100dp
meaning both "your current state" and "tap to return to that state".

Every one of these sheets also carries a `Divider` above its pinned footer.
Content previously bled under the button with no edge, divider or fade, so the
last row was simply sliced and nothing said the list continued.

**Each caller owns both halves of its own inversion.** The agenda's allowlist
seeds the sub-sheet with every offered id when `categoryIds` is empty (empty
already means "all", and the tile above says so — opening it unchecked would
show one state two contradictory ways), and collapses a result covering
everything on offer back to `{}` rather than freezing today's catalog into an
explicit list that would silently exclude every category created afterwards.
The calendar filter inverts its denylist the same way, in the same place. None
of this leaks into `pickMulti`, which stays semantics-free.

A sheet opening a sheet is established here (`EventEditorSheet` →
`CategoryPickerSheet`, `CategoryEditorSheet` → `IconPickerSheet`), and it
preserves `AgendaFiltersSheet`'s invariant: the sub-sheet returns into the
**local draft**, so nothing re-runs the agenda scan behind the sheet until
Apply.

---

## 3. Recurrence engine — [`RecurrenceRule`](../lib/models/recurrence_rule.dart)

A sealed-class hierarchy. Each subtype implements a pure
`bool occursOn(DateTime target, DateTime start, {bool retroactive = false})`
where both date arguments are date-only UTC. The table below describes the
default (`retroactive == false`) behaviour; see §3.3 for what the flag lifts.

| Rule                          | Semantics                                                              |
| ----------------------------- | ---------------------------------------------------------------------- |
| `OneTimeRecurrence`           | Occurs iff `target == start`.                                          |
| `DailyRecurrence(interval)`   | Occurs iff `target >= start && (target - start).inDays % interval == 0`. |
| `WeeklyRecurrence(weekdays, interval)` | Occurs iff `target >= start`, `weekdays.contains(target.weekday)`, and `(weekIndex(target) - weekIndex(start)) % interval == 0`. |
| `MonthlyRecurrence(interval)` | Occurs iff `target.day == start.day` and the whole-month delta is a multiple of `interval` (clamped — Feb 30 → no occurrence). |
| `YearlyRecurrence(interval)`  | Occurs iff `target.month == start.month && target.day == start.day` and `(target.year - start.year) % interval == 0` (Feb 29 in non-leap years → skip). |
| `WorkdaysRecurrence`          | Occurs iff `target >= start`, weekday is Mon–Fri, and **not** a public holiday. |
| `WeekendsRecurrence`          | Occurs iff `target >= start` and weekday is Sat/Sun.                    |
| `PublicHolidaysOnlyRecurrence`| Occurs iff `target >= start` and `PublicHolidays.isHoliday(target)`.    |

**Interval ("every N …").** `Daily`, `Weekly`, `Monthly`, and `Yearly` carry
an `interval` field (default `1`, asserted `>= 1`). `interval == 1`
short-circuits to the original behaviour. Weekly interval phase is counted on
a **fixed Monday-aligned grid** (epoch `2000-01-03`, an ISO Monday) rather
than from each event's start, so an A/B "every 2 weeks" split stays
phase-consistent regardless of the anchor's weekday. The fixed cadences
(`Workdays`, `Weekends`, `PublicHolidaysOnly`) have no interval. All math is
O(1) modular arithmetic on date-only UTC values — no DST hazard, no
allocation on the per-day render path.

### 3.1 Persistence shape

Rules serialize as `(ruleKind: String, rulePayload: String?)`. The payload is
a small JSON object that is **only written when it carries something**:

- `weekdays` — populated by `Weekly` (e.g. `{"weekdays":[1,3,5]}`).
- `interval` — written by any periodic rule **only when `> 1`** (e.g.
  `{"interval":2}`, or `{"weekdays":[1,4],"interval":2}` for an A/B split).

Decoding is defensive: a missing/`<1`/malformed `interval` falls back to `1`,
and legacy payloads (which never carried it) decode unchanged. New rule kinds
add a string constant to `CalendarEventService`'s `_kXxx` set and a case to
`_decodeRule` / `_ruleKind`.

The split-column representation (kind + JSON payload) is deliberately more
forgiving than a single JSON blob: corrupt payloads still let the rule kind
through, and adding a new kind — or a new payload field like `interval` — is a
no-migration change.

### 3.2 Until / `endDate` bound

Added in schema v11. Lives **on `CalendarEvent`, not `RecurrenceRule`**, because
it is orthogonal to every rule shape and would otherwise need to be wired into
each subtype's `occursOn`. The wrapper at `CalendarEvent.occursOn` keeps the
rule subclasses pure and easy to test.

UI rules:

- Editor only shows the "Ends on" picker when `_mode == recurring`.
- `firstDate` of the picker is clamped to the event's start date.
- If the user pushes the start past the existing end date, the end date is
  silently dropped (rather than producing an event with zero occurrences).
- `_onSave` writes `effectiveEnd = recurring ? _endDate : null`, so a
  one-time event can never carry a stale end date.

### 3.3 Scope / `retroactive` (schema v19)

By default a rule never fires before its anchor. `CalendarEvent.retroactive`
lifts that guard, so the rule's periodic phase extends backwards through time —
a yearly check-up added today also shows in every previous year. The editor
presents it as two chips under "Occurrences": **From this date on** (default)
vs **Every year** (yearly rules) / **Always** (everything else).

Like `endDate`, the flag lives **on `CalendarEvent`, not the rules** — it is
orthogonal to every rule shape. Unlike `endDate` it cannot be enforced purely
in the wrapper (the guard is inside each rule), so `occursOn` takes it as a
named parameter and each subtype's guard became
`if (!retroactive && day.isBefore(start))` via the shared `_beforeStart`
helper.

**Why the guard and not a back-projected anchor.** The tempting alternative —
leave the rules untouched and hand them a `start` shifted backwards by whole
periods — is wrong. `MonthlyRecurrence` compares `target.day == start.day`, so
reconstructing a day-31 anchor in a 30-day month rolls over into the next month
and corrupts the phase; a Feb-29 anchor rolls to Mar 1 in non-leap years. The
guard has no such failure mode: every phase test is already correct for a
negative delta, because Dart's `%` is Euclidean and `_weekIndex` floors toward
negative infinity by design.

Scope rules and interactions:

- Only rules with `supportsRetroactive == true` are affected. `OneTime` and
  `SpecificDates` have exact membership and return `false` for it, which is
  what makes the editor hide the chips for one-time events.
- `_onSave` writes `recurring && _retroactive`, mirroring the `endDate` guard,
  so a one-time event can never carry a stale `true`.
- `endDate` still clamps the forward side — a retroactive event is unbounded
  only backwards.
- **`.ics` export stays forward-only.** RFC 5545 cannot express occurrences
  before `DTSTART`, so `IcsSerializer._firstOccurrenceOf` deliberately queries
  the rule without the flag rather than emitting something no consumer could
  represent.
- The agenda scans forward from today, so retroactive occurrences never enter
  it; the day cache and `eventLoader` are unaffected (they already call
  `occursOn` per day).
- Backup keeps version 7: the column is additive and older backups import as
  `false`, which is exactly the behaviour those events had.

### 3.4 Occurrence count / `countOccurrences` + `countStyle` (schema v20–v21)

`CalendarEvent.countOccurrences` is a **display-only** flag: each occurrence
of a periodic rule carries a count label derived from the start date, shaped
by `CalendarEvent.countStyle` (`OccurrenceCountStyle`):

The two values differ in **exactly one thing — where counting starts** — and
the UI says so outright ("Count from 1" / "Count from 0"). Everything else
about them follows from that:

- **`numbered`** = count from 1 (default below yearly) — "Day 1" / "Week 3":
  the start day is occurrence one. Numbering is calendar-based, not
  sequence-based: an every-2-days rule reads "Day 1, Day 3, Day 5" and a
  Mon/Wed/Fri weekly rule labels all three sessions of a week "Week N" — the
  training-program reading.
- **`elapsed`** = count from 0 (default for yearly) — "0 years" / "26 years":
  the start day is zero, so a birth-date anchor makes every later occurrence
  the **age**.

Both render on the start day and both suppress only genuinely pre-start
(retroactive) days, so the origin really is the single difference — that
symmetry is what makes the choice explainable in a chip label. The editor's
live example shows the **first three occurrences** under the current
selection ("Day 1 · Day 2 · Day 3" against "0 years · 1 year · 2 years"), so
the origin is visible before saving rather than discovered on the calendar.

The default is **frequency-dependent** (`_defaultCountStyleFor`), and that
matters: a yearly counted event is an anniversary, and counting one from 1 is
off by one against how everyone reads a birthday — someone born in 2000 has
their 27th *occurrence* in 2026 but turns 26, so "Year 27" reads as a bug
even though it counts correctly. The editor tracks whether the user has
actually tapped a chip (`_countStyleTouched`); until they have, the style
re-resolves when the frequency changes — the same "only re-anchor an implicit
default" rule `_pickDate` applies to the weekday set. A saved event that was
already counting is treated as an explicit choice and never rewritten by the
editor; the one-off repair of rows written under the old flat `numbered`
default was done as a **v23 data migration** instead, scoped to yearly rules
(shorter cadences were already correct).

Mechanics:

- The math is `RecurrenceRule.elapsedPeriods(day, start)` — O(1) date
  arithmetic per rule (days diff / Monday-grid week index diff / month diff /
  year diff), `null` for rules without a periodic unit (one-time, specific
  dates, workdays, weekends, holidays-only). It never touches `occursOn`.
- Formatting is `RecurrenceFormatter.countLabel(event, day, l10n)` — the
  single entry point both surfaces use; it owns the flag check, the style
  switch and the ≤ 0 suppression (`eventElapsedDays/Weeks/Months/Years` ICU
  plurals, `eventNumberedDays/Weeks/Months/Years` unit labels).
- Surfaces: the count label **leads** the day-panel/agenda row subtitle
  ("Week 3 · Weekly · All day" — the count is the headline fact and trailing
  segments ellipsize first), and the detail sheet's next-occurrence chips
  append it ("Sat, May 10 · 30 years").
- Editor: a "Count occurrences" switch shown only for the periodic kinds
  (the `_kindSupportsInterval` set); when on, two style chips appear with a
  live three-sample example line ("Day 1 · Day 2 · Day 3") rendered from
  the same l10n keys, so the choice explains itself. `_onSave` writes
  `recurring && _kindSupportsInterval && _countOccurrences`, mirroring the
  `retroactive` guard. Picking the birthday built-in on a still-one-time
  event pre-fills counting **with the elapsed style** together with the
  yearly rule.
- `.ics` export ignores both fields (RFC 5545 has no equivalent) and backup
  keeps version 7 — additive columns; older backups import as off/numbered.
- v21 is a separate migration from v20 only because v20 had already run on
  devices when the style choice was added; **v23** likewise repairs data v21
  had already written (`count_occurrences = 1 AND rule_kind = 'yearly' AND
  count_style = 'numbered'` → `elapsed`). Both are cases of the same rule:
  never edit a migration that has shipped, add the next one.

---

## 4. Public-holiday subsystem

The calendar engine consults
[`PublicHolidays.isHoliday(day)`](../lib/constants/public_holidays.dart) for
two recurrence rules (`WorkdaysRecurrence`, `PublicHolidaysOnlyRecurrence`)
and also for visual rendering on calendar tiles.

### 4.1 Built-ins are computed, not stored (schema v22)

A profile's holidays are a **pure function of (profile, year)** — that is
what [`HolidaySeeds.forYear`](../lib/constants/public_holidays.dart) is, and
it always was; until v22 the app merely *ran* that function ahead of time and
persisted the results as rows for a rolling 6-year window.

Persisting derived data bought nothing and cost correctness: any year outside
the window had no movable feasts at all (Good Friday in 1991 or 2099 simply
did not exist), and a profile switch had to delete and re-seed rows to stay
honest. So v22 deleted the seeding pass. `PublicHolidays` now computes a
year on first touch and **memoizes** it (bounded at 12 years, cleared
wholesale — rebuilding a year costs microseconds, so an LRU would be more
bookkeeping than it saves), exactly the shape `FastingCalendar` already uses.

Every year in [`CalendarBounds`](../lib/constants/calendar_bounds.dart)
(1900–2100) now resolves fully, Easter-derived feasts included, at a cost of
one Easter computus plus ~15 date constructions per year touched — a month
view touches at most two. There is **no window setting to tune and no
performance cliff to warn about**; both would be configuration over a
non-problem.

Resolution order in `PublicHolidays.holidayOn`:

1. **Overrides** — the user's custom holidays (and any legacy stored
   built-in row) win, so a custom entry can sit on a date the profile
   already claims.
2. **Computed** — `HolidaySeeds.forYear(profile, year)`, unless the date +
   holiday name appears in the suppression set.
3. **Fixed-date fallback** — only while the service has not initialized
   (`_profile == null`), so tests and the first frame still render something
   sensible. Movable feasts are unavailable in that state by nature.

### 4.2 Legislative accuracy: validity years and substitute days

Holidays are law, not arithmetic, so a pure generator needs two corrections
that a naive "compute the date every year" pass gets wrong. Both live inside
`HolidaySeeds`; neither needs a schema change, a setting, or a network call.

**Validity years.** Each holiday created or moved by legislation carries an
inline `if (year >= NNNN)` guard, so browsing a past year does not show an
anachronism. Without them, extending the range to 1900 (§6.5) showed
Juneteenth in 1991 and German Unity Day in 1980. Covered: US (MLK 1986,
Uniform Monday Holiday Act 1971 for Presidents'/Memorial/Columbus,
Thanksgiving 1942, Veterans Day 1954, Juneteenth 2021), UK (New Year 1974,
Early May 1978, spring/summer bank holidays 1971), Germany (Unity Day 1990),
Romania (National Day 1990, Pentecost/Assumption 2008, St Andrew 2012,
Unification Day 2016, Children's Day 2017, Good Friday 2018). The guard sits
next to the date it governs so each region's history reads in one place.

This is a **best-effort curated set covering the clear cases**, not an
exhaustive legislative history — the 1971–1977 US move of Veterans Day to
October is knowingly not modelled, for instance. `generic` and `europe` are
deliberately unguarded: they are curated convenience sets rather than
jurisdictions, so dating them by statute would be false precision.

**Substitute days.** A holiday falling on a weekend earns a statutory day off
elsewhere, and the two rules differ by country, so `forYear` dispatches per
profile after building the base set:

- **UK** — moves *forward* to the next weekday that is not already a bank
  holiday. Order matters: Christmas takes the first free weekday and Boxing
  Day the next, which is what produces the Mon/Tue pair when Christmas falls
  on a Saturday (2021 → 27th and 28th) and the single Tuesday when it falls
  on a Sunday (2022 → 27th, because Monday is Boxing Day itself).
- **US** — Saturday shifts *back* to the Friday before, Sunday *forward* to
  the Monday after. A Saturday New Year is observed on 31 December of the
  **previous** year, so that date is emitted into the prior year's map.
- **Germany, Romania, generic, europe** — no statutory substitution; the day
  is simply lost when it lands on a weekend.

Both the real date and the substitute are emitted, because you want to see
Christmas on Christmas *and* see which weekday is actually off. They are
distinguished by `HolidayOccurrence.observed` → `PublicHolidayInfo.observed`,
which `PublicHolidays.labelOf` renders through the `publicHolidayObserved`
ARB key ("Christmas Day (observed)") — otherwise two identical rows in one
week would be unexplainable. Suppression keys on `(date, name_key)`, so a
substitute can be removed independently of the holiday itself.

### 4.3 The table holds only user deltas

`public_holidays` now stores exclusively what **cannot** be recomputed:

- **Custom holidays** — `name_key = 'custom'` (the `kCustomPublicHolidayKey`
  sentinel) with a non-null `custom_label` and `profile = 'custom'`, so they
  survive every profile switch. Indistinguishable from built-ins for
  recurrence and rendering.
- **Suppressions** — `suppressed = 1` rows (v17), the only durable record
  that a built-in was removed from one specific date.

The v22 migration deletes every other row (`suppressed = 0 AND name_key !=
'custom'`), which is lossless because each one is reproducible. `importData`
applies the same filter: plain built-in rows in an older backup are skipped
rather than restored, since importing them would pin a stale copy of some
other profile's holidays over the computed set. Backup stays **version 7** —
the export shape is unchanged, and a new backup restored into an older build
simply gets re-seeded by that build's seeder.

### 4.4 Removing and restoring a built-in

Removing a holiday (day-summary panel delete action →
`PublicHolidayService.removeOn`) hard-deletes custom rows and **writes a
suppression row** for the computed built-in on that date — with built-ins no
longer stored, that row is the only thing that can persist "not on this
date"; without it the next resolve would hand the holiday straight back.

Restoring (`restoreSuppressed`, backing the "Removed holidays" list in
Calendar Settings via `RemovedHolidaysSheet`, plus the day panel's Undo
snackbar) **deletes** the suppression row rather than clearing its flag: the
holiday itself is computed, so dropping the marker is what brings it back,
and clearing the flag would leave a stored duplicate of derived data behind.

Suppressions are keyed per `(date, name_key)`, so restoring one holiday on a
day that carries two does not resurrect the other. A profile switch deletes
the previous profile's rows including its suppressions — a day removed from
the German set says nothing about the Romanian one.

### 4.5 Religious fasting engine

[`FastingCalendar`](../lib/constants/fasting_calendar.dart) computes fasting
days for four traditions — **Orthodox, Catholic, Muslim, Jewish** — enabled
per user via toggles in Calendar Settings (`SettingsService
.getFastingTraditions`, CSV under `calendar_fasting_traditions`, empty = off,
unknown names dropped for forward compat, cleared by reset-to-defaults).

**Nothing is persisted beyond that setting.** Fasts are fully deterministic
from (year, tradition), so the engine mirrors `PublicHolidays`: a static
sync facade, `configure(traditions)` called from the calendar page's
settings load (no-op when unchanged), then `on(day)` / `isFastingDay(day)`
during builds. Years build lazily (O(365) per tradition, bounded cache of
12 year-maps) and every later lookup is an O(1) map hit — nothing heavy
ever runs inside a cell build or the `eventLoader` path.

The raw date math lives in
[`LiturgicalComputus`](../lib/utils/liturgical_computus.dart) — deliberately
**dependency-free** (no Flutter imports) so a plain `dart run` script can
assert it against externally known dates (it was validated against
2000–2038 Easters both computus, Ramadan 1445–1447, and the Hebrew calendar
anchors RH 5761/5784–5786, Yom Kippur, Pesach, the postponed Tzom Gedaliah
5785, 10 Tevet, Ta'anit Esther). It provides: Gregorian Easter
(Meeus/Anonymous), Orthodox Easter (Meeus Julian + century-aware Julian→
Gregorian offset, shared with `PublicHolidayService` which now delegates to
it), Fliegel–Van Flandern JDN↔Gregorian, the tabular ("Kuwaiti") Islamic
calendar (civil epoch JDN 1948440, ±1 day vs moon sighting — the standard
software caveat), and the full arithmetic Hebrew calendar (molad + all
dechiyot; every public fast is a fixed offset from Rosh Hashanah or from
Pesach, which is always RH(next year) − 163 because Nisan–Elul never vary).

Per-day output is a `FastingInfo(tradition, period, regime)`:

- **Periods** name the fast (Great Lent, Nativity Fast, Ramadan, Yom
  Kippur, …) — localized via sealed switch (`periodNameOf`), never `byKey`.
- **Regimes** are the day's rule: `strict` (post aspru), `oil` (dezlegare la
  vin și ulei), `fish`, `dairy` (Cheesefare), `penitential` (Catholic
  Lent/Advent weekdays), `daylight` (dawn-to-sunset: Ramadan, Jewish minor
  fasts), `full` (Yom Kippur, Tisha B'Av).
- Orthodox rules follow the common printed Romanian calendar: the four
  great fasts with their weekday patterns (Mon/Wed/Fri strict, Tue/Thu
  wine & oil, weekend dispensations), fish on Annunciation/Palm Sunday/
  Transfiguration/Entry into the Temple/St John, first week and Holy Week
  strict, the Dec 20–24 tightening, the three strict single days (Jan 5,
  Aug 29, Sep 14), Cheesefare Wed/Fri as dairy, year-round Wed/Fri fast
  suppressed in the harți weeks (Christmastide, Publican & Pharisee week,
  Bright Week, Trinity week). Apostles' Fast starts Pascha+57 and can
  vanish entirely in late-Pascha years.
- Jewish fasts carry their Shabbat deferrals (17 Tammuz / Tisha B'Av /
  Gedaliah → Sunday, Ta'anit Esther → Thursday).

**Display is configured per tradition**, not globally — Orthodox can tint
the cell in violet while Ramadan draws a green bar. The config model is
[`FastingAppearance`](../lib/models/fasting_appearance.dart), which owns
`FastingTradition`, `FastingDisplayStyle`, `FastingRowPlacement` and
`FastingTraditionStyle` (the same shape as `CalendarAppearance`: enums with
forward-compatible `fromName`, `Equatable`, `copyWith` with `clearX` flags
for the nullable overrides). Each tradition carries:

| Field | Meaning |
| --- | --- |
| `style` | `tint` (default) / `bar` / `strong` / `none` |
| `colorValue` | ARGB override, null = the shared `CalendarColors.fasting` violet |
| `iconKey` | `CalendarIcons` key, null = the tradition's built-in icon |
| `placement` | `first` / `beforeHolidays` / `afterHolidays` (default) / `last` |
| `titleOverride` | replaces the computed period name in the row, null = keep it |
| `description` | extra markdown line under the regime, null = none |

`titleOverride` replaces the period name **outright** (someone who types
"Post" wants it on every Orthodox day, not the specific fast's name) and is
also what the day bar's `semanticLabel` announces. `description` is handed to
`DaySummaryEntry.description`, so it renders through the same clamped
`MarkdownInlineText` path event descriptions use and inherits their rules for
free — money disabled, no tap recognizers, two lines with an ellipsis. Both
text fields normalize blank input to null inside `copyWith`, so clearing a
field *is* the reset and no `clearX` flag is needed for them.

`FastingRowPlacement` exists so the UI never exposes a raw priority — the
enum carries the `DaySummaryEntry.priority` / `DayBar.priority` it maps to
(10 / 120 / 160 / 260), keeping the band layout (events 0–99, holiday 150,
weekend 250) an implementation detail.

How each style reaches the screen:

- `tint` / `strong` — resolved by **`FastingCalendar.cellStyleFor(day)`**
  into a `FastingCellStyle(tint, numberColor)` and handed to
  `CalendarDayCell` as two plain nullable `Color`s. The cell knows nothing
  about traditions or styles, and the resolution (highest placement wins per
  slot; both slots can be filled by different traditions) lives in one
  place. Memoized in a bounded 512-entry day map so `defaultBuilder` never
  re-derives colours for ~42 cells a frame.
- `bar` — `FastingDayBarProvider` emits **one bar per tradition** that asked
  for it, in that tradition's colour at its placement. The check is per
  tradition, not a global gate.
- the day panel always gets one `FastingSummaryProvider` row per active
  tradition — configured icon, colour and placement — titled with the period
  and subtitled with the regime ("Postul Crăciunului · Dezlegare la pește").

Appearance is **display-only**: `configure()` drops just the cheap per-day
cell-style memo when it changes and never touches the computed year maps,
which only invalidate when traditions or the Orthodox scope options move.

Persistence is one key, `calendar_fasting_appearance`, holding a **JSON**
object keyed by tradition name. It started as a delimited
`tradition:style|argb|icon|placement;…` record, which was safe only while
every field was an enum name, an integer or an icon key — the moment free
text (title, description) entered, any separator the user typed would have
corrupted the row, and hand-rolled escaping is exactly the thing that
silently eats one person's data. `decode` still reads the delimited form
(detected by the leading `{`) so nothing written before the switch is lost.

Whatever the shape: every field degrades to its default independently,
unknown traditions are dropped, malformed JSON yields defaults instead of
throwing (a corrupt settings row must never keep the calendar from opening),
and when the key is absent the retired global `calendar_fasting_style` seeds
every tradition. Round-trip (including text carrying `;` `:` `|` `"` `\` and
newlines), legacy decoding, migration and junk-degradation were all verified
with a throwaway harness.

**Editing UX**: each enabled tradition gets an indented "Appearance" row
under its switch, summarising `style · placement`, opening
[`FastingStyleSheet`](../lib/widgets/fasting_style_sheet.dart). The sheet
applies **live** via `onChanged` (the settings page persists on every tap)
rather than gating behind Save — it is a settings surface, so dismissing
must never mean "discard". It leads with a preview showing both halves at
once: a sample day cell carrying the grid treatment next to the day-panel
row it produces, title/description included. Colour and icon reuse the app's
existing `ColorWheelDialog` / `IconPickerSheet`; the preview resolves its
icon from the sheet's own draft, because the engine only learns about a
change after the page has persisted and reconfigured it, and it renders the
description as plain text — pulling the markdown builder into a settings
sheet to show two lines is not worth the dependency.

The two text fields debounce their `onChanged` by 400 ms (discrete controls
still write through immediately) so typing a description does not queue one
settings write per keystroke, and the pending write is flushed in `dispose`
— leaving inside the debounce window must not lose the last keystrokes. The
same shape as the agenda search field in `CalendarBottomPanel`.

**Orthodox scope option** (shown only while Orthodox is enabled):

- *Multi-day fasts* (`calendar_fasting_orthodox_great_fasts`, default on) —
  turning it off drops the four great fasts, the strict single days and
  Cheesefare, leaving only the weekly rule, which then applies year-round.

**The personal schedule** ("My practice", `FastingScheduleSheet`, shown while
**any** tradition is enabled) is one `FastingSchedule` persisted as JSON under
`calendar_fasting_schedule`:

- *Weekdays* — default Wednesday+Friday, but any set works (some keep only
  Wednesday, some add Monday) and clearing them all disables the weekly rule.
  The harți (fast-free) weeks still suppress whatever days are chosen.
- *Weekday scope* (2026-08-22) — the exact mirror of the month scope.
  `weeklyOnly` (default, and everything that shipped before it) gates only the
  year-round weekly rule, so Great Lent keeps its Thursdays; `allFasts` gates
  every mark, so a Wed/Fri practice keeps Great Lent on Wednesdays and Fridays
  only. Applied in the same `_buildYear` `merge` closure beside the month
  probe, one set probe per produced entry. Subtract-only like everything else
  here: it removes days, never invents one, and `forceDates` still wins on a
  weekday that is turned off.
- *Months* — which months the practice is kept in, default all twelve.
- *Month scope* — `weeklyOnly` (default) gates only the weekly rule, so a
  great fast still shows in a month the weekly fast is not kept in;
  `allFasts` gates every mark, other traditions included. Applied inside
  `_buildYear`'s `merge` closure, so it costs one set probe per produced
  entry and never a second traversal.
- *Exception dates* — `skipDates` (never marked) and `forceDates` (always
  marked, emitted as `FastingPeriod.personalFast` attributed to the first
  enabled tradition). Applied last, in `_applyExceptions`, by walking the
  date sets rather than the year map; each is capped at 200 and the two are
  kept disjoint, force winning.

The schedule may **subtract** from a tradition's own weekly rule but never
**invent** days it does not have: dropping Friday silences the Catholic
year-round abstinence, while adding Monday must not fabricate a Catholic
Monday abstinence. Lent/Advent Fridays and Good Friday are seasonal, not
weekly, and survive either way.

Migration: an absent `calendar_fasting_schedule` falls back to the retired
`calendar_fasting_weekdays` CSV, which is read but never written again. That
CSV's **absent** (traditional default) vs **empty string** (deliberate "none")
distinction is resolved in `SettingsService.getFastingSchedule`, which passes
the raw value — `''` included — as `legacyWeekdayCsv`; `FastingSchedule.decode`
treats `null` and `''` differently and must keep doing so.

---

## 5. Persistence layer

### 5.1 Schema (v14)

#### [`CalendarEvents`](../lib/database/tables/calendar_events_table.dart)

| Column              | Type     | Null | Notes                                                                |
| ------------------- | -------- | ---- | -------------------------------------------------------------------- |
| `id`                | TEXT     | PK   | UUID v4.                                                             |
| `title`             | TEXT     | NN   | ≤ 120 chars enforced in UI.                                          |
| `category`          | TEXT     | NN   | Stores enum `name`, decoded with fallback to `other`.                |
| `start_date`        | INTEGER  | NN   | Epoch ms. Date-only UTC by convention.                               |
| `all_day`           | INTEGER  | NN   | Boolean. Write-time mirror of `time == null`; ignored on read.       |
| `icon_key`          | TEXT     | YES  | Optional icon override.                                              |
| `rule_kind`         | TEXT     | NN   | `oneTime` / `daily` / `weekly` / `monthly` / `yearly` / `workdays` / `weekends` / `holidaysOnly`. |
| `rule_payload`      | TEXT     | YES  | JSON; carries `weekdays` (weekly) and/or `interval` (when > 1).      |
| `end_date`          | INTEGER  | YES  | **v11**. Inclusive Until bound (epoch ms).                           |
| `start_minute`      | INTEGER  | YES  | **v11**. Time-of-day start (minutes since local midnight).           |
| `duration_minutes`  | INTEGER  | YES  | **v11**. Optional event duration in minutes.                         |
| `description`       | TEXT     | YES  | **v12**. Free-form markdown notes; length is a UI setting, not a schema constraint (§6.6). Acts as the **template** when per-occurrence descriptions are on. |
| `note_id`           | TEXT     | YES  | **v14**. Optional link to a workout note (`notes.id`).               |
| `retroactive`       | INTEGER  | NN   | **v19**. Boolean, default 0. Lifts the rule's pre-start guard (§3.3).|
| `count_occurrences` | INTEGER  | NN   | **v20**. Boolean, default 0. Occurrences carry a count label (§3.4). |
| `count_style`       | TEXT     | NN   | **v21**. `numbered` / `elapsed` — label shape; column default `numbered`, editor default is frequency-dependent (§3.4). |
| `created_at`        | INTEGER  | NN   | Epoch ms (UTC).                                                      |
| `updated_at`        | INTEGER  | NN   | Epoch ms (UTC).                                                      |

#### [`PublicHolidaysTable`](../lib/database/tables/public_holidays_table.dart)

| Column         | Type     | Null | Notes                                                  |
| -------------- | -------- | ---- | ------------------------------------------------------ |
| `date`         | INTEGER  | PK   | Epoch ms at UTC midnight. Composite PK with `name_key`. |
| `name_key`     | TEXT     | PK   | Built-in enum name or `custom`.                        |
| `profile`      | TEXT     | NN   | **v13**. Owning `HolidayProfile.name`, or `custom`.    |
| `custom_label` | TEXT     | YES  | Required iff `name_key == 'custom'`.                   |
| `suppressed`   | INTEGER  | NN   | **v17**. Boolean; marks a built-in removed from a date. |

Since **v22** the table holds only user deltas — custom rows and
suppressions (§4.3). Built-ins are computed, never stored.

### 5.2 Migrations

[`DatabaseMigrations`](../lib/database/migrations/database_migrations.dart)
follows the project rule that migration SQL is **frozen at the migration's
moment in time** — never relies on the live Drift declaration. This avoids
regressions when columns are added later.

Calendar-relevant steps:

- **v9 → v10**: Creates `calendar_events` and `public_holidays` with raw
  `CREATE TABLE` and adds the calendar indexes.
- **v10 → v11**: Adds three nullable columns
  (`end_date`, `start_minute`, `duration_minutes`) via `ALTER TABLE … ADD
  COLUMN`. Idempotent: introspects `PRAGMA table_info(calendar_events)` and
  skips any column already present.
- **v11 → v12**: Adds the nullable `description` column (same idempotent
  `PRAGMA table_info` guard).
- **v12 → v13**: Holiday-profile support (rebuilds `public_holidays`); not a
  `calendar_events` change.
- **v13 → v14**: Adds the nullable `note_id` column (same idempotent guard).
  `NULL` preserves the historical "no linked note" semantics, so existing
  rows are unchanged.

Fresh installs use `m.createAll()` from the live Drift declaration, which
already includes every column above — no migration runs. The recurrence
`interval` needed **no migration**: it is encoded inside the existing
`rule_payload` JSON.

### 5.3 [`CalendarEventDao`](../lib/database/daos/calendar_event_dao.dart)

Thin Drift DAO: `getAll`, `upsert`, `deleteById`, `deleteAll`. No
recurrence-aware queries — recurrence math is always done in Dart against
the in-memory cache.

### 5.4 [`CalendarEventService`](../lib/services/calendar_event_service.dart)

Singleton (registered with `DatabaseLifecycle` so it resets when the user
switches DBs). Responsibilities:

- **Load on init** — pulls all rows once into `List<CalendarEvent> _cache`.
- **Synchronous reads** — `events` getter returns the unmodifiable cache so
  `CalendarBloc.eventsForDay` can expand recurrences with no async hops. The
  bloc additionally **memoizes** the per-day result (see §6.1), so each
  distinct day is scanned at most once per event-set / filter generation.
- **Mutations** — `upsert` and `deleteById` go through the DAO and then
  patch the in-memory cache so the calendar UI sees the change instantly.
- **Date-only normalization** — `startDate` and `endDate` are forced through
  `_dateOnlyUtc` on every write so equality / ordering is timezone-stable.
- **Backup parity** — `exportData()` and `importData()` mirror the row shape
  for inclusion in the app-global backup (see §7).
- **Rule serialization** — kind/payload codec, isolated in this service so
  the rest of the app stays in domain types.

### 5.5 [`PublicHolidayService`](../lib/services/public_holiday_service.dart)

Companion singleton:

- **Seeds** the 6-year window on first launch and on every subsequent launch
  via `insertIfMissing`.
- **Publishes** a `Map<DateTime, PublicHolidayInfo>` to
  `PublicHolidays._cache` plus the inclusive `(minYear, maxYear)` window.
- **Mutates** via `addCustom` (writes `name_key=custom` rows) and
  `removeOn(date)` (suppresses any holiday on that day).
- **Backup parity** — `exportData()` / `importData()` round-trip every row
  shape verbatim (see §7).

---

## 6. UI surfaces

### 6.1 Calendar page

Backed by `table_calendar 3.2.0`. Tile rendering consults
`PublicHolidays.holidayOn` for holiday badges and
`CalendarBloc.eventsForDay(day)` to draw event chips.
`CalendarBloc.eventsForDay` is synchronous and **memoized**: the first call
for a day iterates the cached event list and calls `event.occursOn(day)`,
then stores the result in a bounded per-day map (`_dayCache`, cap 512
entries — cleared wholesale on overflow). The cache is invalidated **only**
by the handlers that change the inputs to the expansion —
`LoadCalendarEvents`, `CreateCalendarEvent`, `UpdateCalendarEvent`,
`DeleteCalendarEvent`, and `ChangeHiddenCategories`. Day-selection, focus,
and format changes deliberately keep the cache warm, so the common case
(tapping around a month, toggling month/2-week/week) is an O(1) map lookup
per cell instead of an O(N) recurrence scan. The same cached path also feeds
the bottom day-summary panel, so there is a single recurrence-expansion code
path (the old uncached `CalendarPageLoaded.selectedEvents` getter was
removed).

**Header** (`headerTitleBuilder`, chevrons still table_calendar's). Three
controls share one row between the chevrons:

- the **month title opens
  [`MonthYearPickerSheet`](../lib/widgets/month_year_picker_sheet.dart)** —
  see below. Its wheels carry a day too, so a pick is a full date: the page
  dispatches `SelectCalendarDay` (focus **and** select), moving the panel
  below with it, and opens the sheet on the current `selectedDay`.
- the **Today button** stays the original plain, unfilled icon button,
  positioned to the left of the title.
- the **month net** (`Δ`, money-ledger sum for the focused month) sits after
  the title. Today, title, and net form one cluster centered as a block via
  `mainAxisAlignment.center` — the title is not dead-center of the full
  header, matching the pre-existing layout feel.

The default chevron padding/margin is overridden to 40dp touch targets
(table_calendar's default claims 64dp each, a third of a phone's width for
two arrows the user can also swipe). Only the title text is `Flexible` with
an ellipsis under pressure — the Today button and the net stay at their
intrinsic size.

#### [`MonthYearPickerSheet`](../lib/widgets/month_year_picker_sheet.dart)

A full-date picker for jumping the calendar — distinct from
`CalendarDatePickerSheet` (§6.5), which is the grid used for event date entry.
One screen, no drill-down (a day → month → year drill was built here once and
rejected outright), with two input modes behind a toggle pinned top-right:

- **Wheels** (default): three `ListWheelScrollView`s side by side — day |
  month | year (the dd/mm/yyyy order, so both modes read the same way) — that
  scroll up/down independently, so a flick crosses days, months or decades
  without leaving the screen. `Apply` commits the centred rows. The **day
  wheel is bounded by the month** (`_daysInMonth`, `day 0` of next month —
  leap-aware); when the month or year moves the day is clamped back inside it
  (`_clampDayToMonth`: Jan 31 → Feb → 28/29) and the day wheel is realigned by
  a post-frame `jumpToItem`, because its child count shrinks in the same
  build. Kept intentionally quiet after an over-designed version was rejected:
  one faint `surfaceContainerHighest` band marks the selected row, a
  `ShaderMask` fades the top/bottom edges so it reads as a wheel and not a
  clipped list, and the only accent is the selected label's colour.
- **Typed**: a single text field, canonical form `dd/mm/yyyy` (the hint), with
  forgiving parsing (`_parse`). Separators and order are free-form:
  `15/08/2026`, `15.8.2026`, `2026-08-15` all give the 15th (a 4-digit year on
  either end fixes d/m/Y vs Y/m/d — the month is the middle number). Shorter
  forms work too: `08/2026` keeps the wheel's day, `15 august 2026` /
  `15 aug` read the day next to a named month, a bare `2026` keeps month+day,
  a bare number `>12` is taken as a day. Impossible days (`31/02`) clamp to
  the month length. Unparseable input and out-of-range years surface as field
  errors instead of silently doing nothing.

`Apply` commits either mode; `Today` moves the wheels to the current date
(animated) rather than closing, so it composes with a manual tweak. The
mode-toggle icon shows a keyboard in wheel mode and `calendar_month` in typed
mode (a `filledTonal` button — the earlier `view_day` icon was rejected).
Month names come from `intl` + `toBeginningOfSentenceCase` (locales like
Romanian spell them lowercase), never an ARB matrix. The mode switch is
wrapped in `AnimatedSize`, because typed mode is shorter than the wheels and a
fixed height would overflow with the keyboard up; the keyboard inset is read
from the **sheet's** context, not the caller's, since only that one rebuilds
when the keyboard opens.

### 6.2 Day list

Tapping a date opens a list of that day's events. Each tile is colored by
category, optionally overridden with a custom icon. When fasting traditions
are enabled (§4.4) the list also carries one violet row per tradition naming
the fast and the day's rule. The whole bottom panel sits inside a
`SafeArea(top: false)` so its last rows clear the device's system
navigation bar instead of rendering underneath it.

Rows carry the event's **description** below the scheduling line, rendered as
markdown and clamped to two lines with an ellipsis (`MarkdownInlineText`, §6.6),
plus a small notes icon next to the title when one exists. The agenda inherits
this by construction — both surfaces render `EventSummaryProvider` entries, and
that sharing is deliberate.

Tapping a row — in the day panel **or** the timeline, which render the same
day and so must agree — opens the **read-only**
[`EventDetailSheet`](../lib/widgets/event_detail_sheet.dart):
title, category, date/time, recurrence (with scope), priority, the fully
rendered description, the linked-note button, and the next 5 occurrences.
Editing is one button away: `EventDetailAction.edit` opens the full editor
sheet and `.editDescription` opens a dedicated full-screen sheet for just
that field (§6.6 and the 2026-08-31 addendum) — both reopen this sheet on
return, so a follow-up glance costs no extra tap. `.skipOccurrence` cancels
the occurrence with Undo, and opening the linked note routes through the
page's existing resolver.
"Read-only" has one exception: description checkboxes on **single-occurrence**
events toggle in place and write back through `onEventChanged` (§6.6).

### 6.3 [`EventEditorSheet`](../lib/widgets/event_editor_sheet.dart)

A bottom-sheet form (`heightFactor: 0.92`), organized **category-first**
into three `_GroupHeader` zones (accent-colored label + divider; the
per-field `_SectionLabel`s stay inside each zone):

**What** (`eventSectionWhat`):
1. **Type** — category picker (`CategoryPickerSheet`), deliberately the
   very first control: picking a category tailors the rest (the birthday
   built-in pre-fills yearly recurrence). This is also why the title field
   lost its autofocus — a keyboard popping open would bury the tile the
   flow starts with.
2. **Title** — single-line `TextField`, `maxLength: 120`.

**When** (`eventSectionWhen`):
3. **Repeat mode** — segmented control `oneTime` / `recurring`, leading the
   zone: it decides everything the zone renders below it (date chips vs
   start date + recurrence config), so it sits above what it switches — in
   its old spot below the date and time sections, toggling it mutated
   content *above* the control, which read as if nothing happened.
4. **Date(s)** — `CalendarDatePickerSheet` (§6.5), bounded by
   `CalendarBounds`: fixed wide bounds, **not** the old ±20-year
   slide around the current date, because a birthday's start is the birth
   year and the occurrence-count age (§3.4) depends on it being real. The
   Until picker keeps the start date as its lower bound. One-time
   events edit their whole date set in one multi-select pass; recurring
   events pick a start date, then frequency chips, interval stepper, weekly
   weekday chips, occurrence-scope chips (§3.3), the count-occurrences
   switch (§3.4, periodic kinds only), and the optional Until date — one
   contiguous recurrence block under the toggle.
5. **Time** — all-day switch, start/end pickers, closing the zone (shared
   by both modes).

**Details** (`eventSectionDetails`):
6. **Description** — markdown source in a real `ModernEditorWrapper` /
   re_editor surface, live-rendered Obsidian-style by the note editor's own
   `MarkdownEditorSpanBuilder` (see §6.6), with a `count / limit` counter
   above it and an expand icon that opens the same text full-screen in
   `EventDescriptionSheet` (§6.6, 2026-08-31 addendum) — shown in preview
   mode too, since expanding is itself an edit action. The eye/pencil
   preview toggle survives only for users who turned live rendering off.
   Money is disabled throughout (see §6.6).
7. **Icon** — icon picker with reset-to-default action.
8. **Color / priority / linked note** — appearance override, P1–P5 chips,
   note link.

**(if editing) Delete** — destructive button with a confirmation dialog,
last in the scroll.

Header: one leading icon + centered title + save in the same row — no
detached bottom action bar, and never two leading icons. The icon is cancel
(`close`) normally; opened from the detail sheet's edit loop it is
**replaced** by `back` instead (`showBack`, §6.2, 2026-08-31), since the two
discard identically with no dirty tracking in this sheet and a second icon
would only mark where the user lands. Secondary whole-form actions —
Delete, Save-as-template — stay out of the header and sit at the bottom of
the scroll body.

`_canSave` requires a non-empty title and, for weekly, at least one weekday.

### 6.4 Validation rules currently enforced by the editor

- Title trim non-empty.
- Weekly weekday set non-empty.
- Until date ≥ start date (clamped via `firstDate`).
- Start date moving forward past Until silently clears Until.
- The multi-date picker cannot confirm an empty set (Save is disabled), so a
  one-time event always keeps at least one date.

### 6.5 [`CalendarDatePickerSheet`](../lib/widgets/calendar_date_picker_sheet.dart)

The in-app replacement for `showDatePicker`, so date entry happens on the same
grid as the rest of the calendar. Two modes:

- `pickSingle` → `DateTime?`; tapping a day confirms immediately.
- `pickMulti` → `Set<DateTime>?`; days toggle, a footer shows the count with
  Clear / Today, and Save returns the edited set. Never returns empty.

It renders through `CalendarDayCell` / `CalendarDayBars` with the user's
`CalendarAppearance` (week start, accent, today style, week numbers), so it
cannot drift from the real grid, and it reuses the same collision-free row
height formula. An optional `dayLoad` callback draws a neutral "busy" bar on
days that already carry events — the calendar page passes
`CalendarBloc.eventsForDay`, which is the memoized O(1) lookup, so the picker
issues **no** extra queries.

This sheet picks **days**. Jumping the calendar to another month/year is a
different job with a different surface —
[`MonthYearPickerSheet`](../lib/widgets/month_year_picker_sheet.dart) (§6.1),
which the header's month title opens (`_openMonthYearJump`), exactly like the
calendar page's own header. In single mode its Apply confirms the
wheeled/typed date outright (the wheels carry a full date; re-tapping it on
the grid would be redundant); in multi mode it only jumps the grid there —
day toggling stays a grid gesture so a navigation intent can never edit the
set. Do **not** re-inline month/year *stages* into this sheet itself: that
was tried and turned a date-entry surface into a navigation maze. Linking
out to the dedicated jump surface is the sanctioned composition.

The appearance is **passed in** (page → editor sheet → picker), not re-read:
`getCalendarAppearance()` is eight sequential settings reads, and resolving it
after the first frame visibly re-lays-out the grid because week start and row
height both move. The page already holds a current copy and refreshes it when
returning from settings. The colour palette threads the same way (page →
bottom panel → rows) for the same reason plus staleness: a panel-local load
would happen once in `initState` and never see an edit.
`CalendarAppearance.showRecurrenceLabels` (a Calendar Settings switch,
default on) rides the same object and threads page → bottom panel →
`EventSummaryProvider` / `AgendaListView`: off, row subtitles drop the
repeat-pattern segment ("Daily", "Every 2 weeks", …) — for timed routines it
reads as redundant next to the time. Count labels (§3.4) and times stay.

Its mode enum is `CalendarDatePickerMode` — **not** `DatePickerMode`, which
`material.dart` already exports; the collision compiles inside the declaring
file and breaks any file importing both.

The multi mode deliberately knows nothing about *why* the dates matter (it
takes a set, returns a set). That is what lets the same surface later drive
per-occurrence skip dates without a UI rewrite.

#### Navigable range — [`CalendarBounds`](../lib/constants/calendar_bounds.dart)

**1900-01-01 … 2100-12-31**, one constant shared by the grid
(`_CalendarTable._firstDay/_lastDay`), both day pickers and the month/year
jump wheel. Single source of truth on purpose: a date the user can anchor an
event on must also be a date they can browse to, and the two drifting apart
is what made a 1991 birth year unreachable while the age count depended on
it.

The **1900 floor is the computus domain floor**, not a guess: the Julian
calendar's lag behind the Gregorian became 13 days in 1900 (12 through the
1800s), and that 13 is exactly what
`LiturgicalComputus.julianToGregorianOffset` returns for the 1900–2099
window, degrading to a flat 13 below it. Flooring at 1900 means every
Orthodox-Easter-derived holiday and fasting date stays correct instead of
silently landing a day off. Do not lower it without fixing that function.

Range width is **free at runtime**, which is why the old narrow windows
bought nothing:

- `TableCalendar` pages months through a lazy `PageView`; only the visible
  month is built (2412 months in range, ~1 built).
- The year wheel is a `ListWheelChildBuilderDelegate` — 201 rows, built as
  they scroll into view.
- `FastingCalendar` computes a year on first touch (O(365) of O(1) date
  math) and memoizes it, bounded at 12 years.
- `PublicHolidays.holidayOn` answers years outside the seeded window
  (current year + 5) from a **static fixed-date map** — one map probe, no
  database, no seeding. Browsing 1991 shows its fixed holidays (Christmas,
  New Year…) and no Easter-derived ones, exactly as it already did for any
  past year inside the old 2000 floor.

### 6.6 Markdown in descriptions

Descriptions are stored as **raw markdown source** and rendered on demand.
Nothing pre-rendered is persisted or cached in the database.

- **Rows** (day panel, agenda) use
  [`MarkdownInlineText`](../lib/widgets/markdown_inline_text.dart): the same
  `LineBasedMarkdownBuilder` as the preview — there is one grammar in this app
  and this adds no second one — with display-only adjustments. Headings render
  at body size via the new `LineMarkdownStyle.flattenHeadings`, blank lines are
  dropped and only the first 3 lines are kept, and **every tap callback is
  null**, which is what keeps the builder from allocating a single
  `TapGestureRecognizer` and makes the spans inert, cacheable and safe to drop.
  A process-wide memo (128 entries, oldest-inserted evicted first) is keyed on
  the raw source and invalidated wholesale when the render config
  (`brightness`, `fontSize`, colour, `palette.source`, `primary`) changes. The
  **hit path allocates nothing** — this runs in `build` for every visible row
  on every scrolling frame, so the config is compared field-by-field instead of
  through a composed key string, and the line-collapsing pass only runs on a
  miss.
- **Detail sheet** (and the editor's fallback preview) use
  `SimpleMarkdownPreview` — full fidelity, no flattening.
- **The editor sheet's description is a real re_editor surface.** It builds a
  `ListAwarePasteController` over a `CodeLineEditingController` whose
  `spanBuilder` is a sheet-owned `MarkdownEditorSpanBuilder`, hosted in the
  note editor's `ModernEditorWrapper` (`showScrollIndicator: false`). That is
  what makes live rendering, tap-to-toggle checkboxes, list continuation, Tab
  indent, ghost runs and the selection toolbar behave identically in both
  places without a second implementation. The whole stack is created and
  destroyed with the sheet; a ≤ few-dozen-line description makes the span
  builder's incremental line index and LRU memos effectively free. The global
  **live markdown rendering** setting is honoured, and a late-resolving
  setting is applied with `configureColors` + `forceRepaint()` — **never** by
  remounting the editor, which crashes re_editor's controller-delegate handoff
  mid-initialization (the same rule the note editor documents for money
  config). The editor box is height-bounded (120–260 px) because a
  `CodeEditor` owns its own scroller and cannot be unbounded inside the
  sheet's `SingleChildScrollView`; taking focus scrolls it into view, since a
  `CodeEditor` is not an `EditableText` and nothing does that automatically.
- **`EventDescriptionSheet` (2026-08-31) reuses that exact stack full-screen**,
  away from the 120–260 px box and the form's own `SingleChildScrollView` —
  two nested scrollers fighting a drag is what made writing there feel bad,
  not any gap in markdown capability. The editor is `Expanded`, the sheet's
  only scrollable. Two entry points re-resolve which text they are editing
  rather than carrying a payload, so a quick edit and a checkbox tick can
  never target different places: the editor sheet's expand icon (seeded
  from the **active scope only** — `_scope` stays behind in the form, which
  keeps the sheet pure and the copy-on-write logic in one place) and the
  detail sheet's description-card pencil (`EventDetailAction
  .editDescription`). Its markdown bar is **permanently docked, not
  focus-gated** like the inline field below — the description is the whole
  screen, so a stable footer beats a vanishing one — which is why its
  `max(viewInsets.bottom, viewPadding.bottom)` clearance wraps the **whole
  sheet** rather than a scrollable, the `CalendarFilterSheet` shape of that
  rule. Money stays disabled **by omission**: neither `ModernEditorWrapper`
  nor the span builder constructor takes a money parameter here, so never
  add one by copying the note editor's wiring. See the 2026-08-31 addendum
  for the full mechanics (quick-edit routing, the back-button reopen loop,
  the blank-vs-reset distinction).
- **The markdown bar appears on description focus**, below the sheet's scroll
  view (so the form never shifts), reduced to `splitEnabled: false`, no
  settings / reorder, and undo+redo+paste as its only utility buttons.
  Shortcuts come from the app-wide `MarkdownBarBloc`'s active profile, with
  **counter-bound shortcuts filtered out** — `{c1}` resolves against a note
  context an event does not have. Ghost / colour-slot shortcuts route through
  the shared
  [`MarkdownShortcutInserter`](../lib/controllers/markdown_shortcut_inserter.dart),
  extracted from the note editor so both surfaces keep one implementation.
- **Checkboxes toggle only where "checked" has one meaning.** In the editor
  sheet, tapping a task box edits the buffer and persists on Save like any
  other keystroke. In the read-only detail sheet, tapping is enabled when
  `event.rule is OneTimeRecurrence` (the tick edits the event directly) **or**
  per-occurrence descriptions are on (the tick materialises `widget.day` and
  leaves every other day alone) — a repeating event with the setting off is
  the one case left with no unambiguous target, since the description is one
  shared string and a checked box would read as checked on every occurrence.
  Those events keep inert boxes; a one-line caption
  (`eventDescriptionTickAllOccurrences`, 2026-08-31) renders under the
  description **only when it actually contains a task box**, pointing at the
  quick-edit pencil (§6.2) and per-occurrence descriptions as the way to
  affect one day instead of the whole series — otherwise the dead boxes
  would be the only unresponsive thing left on a sheet that is read-only
  apart from them. The task-box test goes through
  `MarkdownListSyntax.parse(line)?.kind == MarkdownListKind.task`, the
  shared grammar, never a second regex, and only runs in that inert case.
  Detail-sheet toggles update local state immediately and coalesce
  into **one** `UpdateCalendarEvent` after 600 ms (flushed on close, on
  routing to edit, and in `dispose` so a drag-dismiss never loses a tap),
  because every write invalidates the bloc's day cache. The sheet renders and
  rewrites the **same trimmed string**, since the builder reports absolute
  source offsets for the `[ ]` / `[x]` bracket.
- **Description length is a setting, enforced by refusing to save.**
  `SettingsKeys.eventDescriptionLimit` (default 2000, slider 500–10000 in
  steps of 500, under Calendar Settings → Events, included in reset-to-
  defaults) replaces the old hardcoded `TextField(maxLength: 2000)`, which
  re_editor has no equivalent for. It is **never** enforced by truncation —
  the description is markdown the user typed, and dropping its tail silently
  is worse than refusing. Over budget: the counter above the field turns red,
  a line explains why, and Save is disabled. A **grandfather rule** keeps the
  guard from locking anyone out: a description is also allowed at any length
  it already had when the sheet opened (`_initialDescriptionLength`), so
  lowering the limit blocks *growth*, not editing. The getter/setter clamp to
  the slider bounds, so a corrupted value can never make every event
  unsavable. Both the counter and the Save button track the controller
  through `ListenableBuilder`s rather than keystroke-wide `setState` — but via
  the sheet's `_descriptionRevision` relay, **never the controller directly**:
  `_CodeEditorState.initState` wraps the controller in its own delegate and
  that `delegate =` setter calls `notifyListeners()` synchronously *while the
  framework is building*, so any builder mounted above the editor throws
  "setState() called during build" on the first frame. The relay is a
  `ValueNotifier<int>` that defers a mid-frame notification to a post-frame
  callback; keystrokes arrive outside the frame and take the fast path. Since
  v24 **each description scope carries its own budget and its own
  grandfather** (`_initialTemplateLength` / `_initialDayLength`), and
  `_canSave` checks both — reading only the live controller would let
  over-limit day text through while the template view is on screen.
  `EventDescriptionSheet` (2026-08-31) takes the limit and the grandfathered
  length as plain parameters (`SettingsService.getEventDescriptionLimit()`
  and the seed's own length, read at open time), so the same rule holds one
  level removed from the form.
- **Descriptions can be per-occurrence (v24; opted into per event since
  v28).** `CalendarEvent.perOccurrenceDescriptions` — an editor switch above
  the description field; the v24 global setting is gone (see the v28
  addendum) — turns the event's `description` into a **template**: a day with no row of its own
  renders the template, and the first edit or tick on a day materialises a row
  in `calendar_event_occurrences` seeded from it (copy-on-write). The table
  holds **only user deltas**, exactly like `public_holidays` since v22, so a
  daily event costs zero rows until it is touched.
  - **One resolution entry point**: `OccurrenceDescriptions.descriptionFor(event, day)`
    (`lib/constants/occurrence_descriptions.dart`). Never resolve a description
    for a day any other way, or the template fallback drifts between the day
    panel, the agenda, the detail sheet and search.
  - **The gate is the event's flag plus `rule is OneTimeRecurrence`, and
    nothing else.** An event
    firing on one day has nothing to separate; a `SpecificDatesRecurrence` is a
    list of distinct occasions and *does* participate. Never gate on the
    editor's `_RepeatMode`, which files specific-dates under `oneTime`.
  - **A row that exists always wins, including when empty.** `overrideFor`
    returns non-null (possibly `''`) for a present row and `null` only for a
    missing one — that is what keeps a deliberately blanked day blank instead
    of falling back. "Reset this day" **tombstones** the row (since v28); it
    never writes `''`. This also makes the notes-icon badge per-day-correct
    for free. The quick-edit sheet's Done follows the same rule (2026-08-31
    addendum): emptying a per-occurrence description writes `''`, a
    deliberate blank that still beats the template, never a tombstone —
    that stays the editor's "reset this day" alone.
  - **Reversible in both directions.** Turning the setting on moves nothing;
    turning it off leaves rows dormant rather than deleting them. Rules that
    change so a day no longer occurs keep their row — a stored delta is the
    only durable record of a deliberate act. Deleting an event cascades
    (one transaction in `CalendarEventService.deleteById`/`deleteAll`).
  - **Static facade published by the service, not a page.** `EventOccurrenceService`
    publishes the cache at `getInstance()` — the
    `PublicHolidayService` shape, deliberately not `FastingCalendar`'s, whose
    post-first-frame `configure` would render templates for one frame and then
    flip every row on a cold start into the calendar. `reset()` must clear the
    singleton **and** the facade.
  - **Agenda search needs two passes.** `EventAgenda._matches` runs in the
    candidate pre-filter, *before* the day is known, so it is a deliberate
    **superset** test (title OR template OR *any* override); `_matchesOnDay`
    then narrows per day inside the scan. Testing only the superset would emit
    every occurrence of an event whose hit lives on one day.
  - **Writes skip the day cache.** `SetOccurrenceDescription` /
    `ClearOccurrenceDescription` bump `CalendarPageLoaded.occurrenceRevision`
    and deliberately do **not** call `_invalidateDayCache()` — that cache
    answers "which events occur on this day", and description text is not an
    input. (Ticking a box used to wipe all 512 entries via the whole-event
    update; it no longer does.) The revision is load-bearing twice over: the
    state is `Equatable`, so an otherwise-identical copy would be dropped, and
    `AgendaListView`'s identity-based row memo would keep serving stale text.
    `UpcomingAgendaView` forwards it but must never rescan on it.
  - **Editor scope control**: a `SegmentedButton` ("All days" / "This day")
    above the description, shown only when `initialEvent != null && occurrenceDay != null &&
    enabled && rule-has-many-occurrences`. **One controller throughout** —
    only its text is swapped, with the inactive scope buffered in a plain
    `String`. Swapping controllers would orphan `ModernEditorWrapper`'s
    listener (it binds in `initState` and has no `didUpdateWidget`), the span
    builder and the search controller, and drag re_editor through a delegate
    handoff nothing else in this app exercises. `clearHistory()` after every
    swap is mandatory: `set text` runs as a revocable op, so without it undo
    pulls the *other* scope's text into the active one and Save persists it.
    Flipping the form to one-time hides the control and calls
    `_syncScopeToRule`, which parks the day text unwritten — never merge an
    occurrence's text into the template. The sheet never persists: it reports
    `(occurrenceDay, occurrenceDescription)` on `EventEditorSaved` and the page
    dispatches, event write first.
- **Money is always disabled** in descriptions (`MoneyDisplayConfig.disabled`).
  A ledger balance is a per-note concept; a `$+ 50` line in an event
  description would render a balance derived from nothing, so those lines stay
  literal text.
- The colour palette threads from `SettingsService.getColorPalette()` through
  the calendar page / bottom panel, so `{name:text}` runs show the user's
  custom colours. It is value-equal on its persisted `source`, which is what
  makes it a legal cache-key component.

---

## 7. Backup & restore

The app-global backup is owned by
[`BackupService`](../lib/services/backup_service.dart). It serializes every
persisted store into a single JSON document with a `version` number.

**Backup version 4** (introduced when user-creatable categories were added)
adds a `calendarCategories` array alongside the existing `calendarEvents` and
`publicHolidays`. Categories are imported **before** events on restore so each
event's `categoryId` resolves. A v3 (or earlier) backup imports cleanly — the
missing `calendarCategories` key just leaves the seeded built-ins in place.

Each category row gained an additive `isHidden` boolean with schema v33 and
**no backup version bump** — an archive written before the flag existed cannot
describe a hidden category, so its absence correctly restores everything
visible (§2.3). It is read by type test rather than a cast, so a junk value
costs the flag rather than the whole row.

**Backup version 3** includes:

```jsonc
{
  "version": 3,
  "calendarEvents": [
    {
      "id": "…", "title": "…", "category": "gym",
      "startDateMs": 1717113600000,
      "allDay": true, "iconKey": null,
      "ruleKind": "weekly", "rulePayload": "{\"weekdays\":[1,3,5]}",
      "endDateMs": null,
      "startMinute": null, "durationMinutes": null,
      "createdAtMs": 1717100000000, "updatedAtMs": 1717100000000
    }
  ],
  "publicHolidays": [
    { "dateMs": 1735689600000, "nameKey": "newYear", "customLabel": null },
    { "dateMs": 1735776000000, "nameKey": "custom",  "customLabel": "Birthday" }
  ]
}
```

### 7.1 Round-trip discipline

- **Calendar events** mirror the row shape exactly. Reserved
  `startMinute` / `durationMinutes` are written even though application
  code doesn't set them — so a future version that introduces time-of-day
  events can still import an old backup without losing data.
- **Public holidays** mirror the row shape exactly. Custom rows survive
  verbatim. Built-ins are also dumped, but the seeder will re-fill any
  missing built-in for the seeded window on next start.

### 7.2 Backward compatibility on import

`BackupService.importFromJson()` reads new keys with `data['…'] as List?`,
so v1/v2 backups (no `calendarEvents` / `publicHolidays`) load cleanly and
leave existing calendar/holiday data in place. A v3 backup loaded by an
older binary simply ignores the unknown keys.

### 7.3 Behavior the user should know

- Restoring a v3 backup **deletes all** existing calendar events and
  holidays first, then inserts the backup contents — same destructive
  pattern used by other restore paths.
- After restore, the public-holiday seeder runs again on next start and
  re-adds any built-in row missing from the seeded window. **A built-in
  the user had deleted will come back after restore.** This is a known
  limitation; fixing it requires a tombstone column.

---

## 8. Concurrency & threading

- All database operations go through Drift, which serializes I/O on a
  background isolate.
- The in-memory caches (`CalendarEventService._cache`,
  `PublicHolidays._cache`) are mutated only on the UI isolate after a write
  resolves, so there is no read/write race.
- `CalendarBloc.eventsForDay` is synchronous and called from build methods.
  It writes into `_dayCache` during build, which is safe: Dart is
  single-threaded so a build and a bloc event handler never interleave, and
  the cached lists are `List.unmodifiable(...)`.

---

## 9. Localization

All user-visible strings live in the three ARB files
([app_en.arb](../lib/l10n/app_en.arb),
[app_de.arb](../lib/l10n/app_de.arb),
[app_ro.arb](../lib/l10n/app_ro.arb)).

Calendar-relevant key families:

- `eventCategory*` — category labels.
- `recurrence*` — rule kind labels, the formatted weekday list, the
  interval-aware summaries (`recurrenceEveryDays/Weeks/Months/Years`,
  `recurrenceEveryWeeksOn`) and the stepper strings
  (`recurrenceIntervalLabel`, `recurrenceUnit*`, `recurrenceInterval{In,De}crement`).
- `publicHoliday*` — named built-in holidays.
- `eventTitle`, `eventType`, `eventDate`, `repeatMode`, `repeatOnce`,
  `repeatRecurring`, `frequency`, `weekdays`, `weeklyDaysHint`, `startsOn`,
  `pickCategory`, `pickIcon`, `iconLabel`, `iconCustom`, `iconDefault`,
  `resetToDefault`.
- **v11 additions** — `eventUntilLabel`, `eventUntilNone`, `eventUntilHint`,
  plus the time-of-day strings (`eventAllDay`, `eventStartTime`,
  `eventEndTime*`, `eventCrossesMidnight`).
- **v12 additions** — `eventDescription`, `eventDescriptionHint`.
- **v14 additions** — `eventLinkedNote`, `eventLinkNoteHint`,
  `eventLinkedNoteMissing`, `eventOpenLinkedNote`, `eventRemoveNoteLink`.

The interval summaries use ICU `plural` so the `=1` form collapses to the
plain label ("Weekly") while `other` reads "Every N weeks"; Romanian adds the
`few` form. Plural placeholders must stay intact across all three ARBs.

After editing ARBs, re-run `flutter gen-l10n` to refresh
`AppLocalizations`.

---

## 10. Reserved / forward-compat surfaces

### 10.1 `start_minute` / `duration_minutes` (shipped)

Reserved in schema v11 and **now in active use**. The time-of-day path:

- [`EventTime`](../lib/models/calendar_event.dart) value object holds
  `startMinute` (minutes since local midnight, `[0, 1440)`) and an optional
  `durationMinutes` (`>= 1`; may exceed the remaining day to cross midnight).
- `CalendarEvent.time` is the single source of truth; `allDay` is derived as
  `time == null` and `all_day` is a write-time mirror used only for SQL.
- `_eventToCompanion` / `_rowToEvent` round-trip `start_minute` /
  `duration_minutes`; backup carries them too.
- The editor sheet shows a start/end time section whenever "All-day" is off.

### 10.2 `allDay`

Derived, not stored as the source of truth: `time == null`. The `all_day`
column (present since v10) is kept in sync on write purely so future SQL
filters can use it without decoding `time`.

---

## 11. Known limitations

| Limitation                                                         | Impact   | Mitigation                                                                             |
| ------------------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------- |
| No skip-this-occurrence (exceptions)                                | Medium   | Would need an `event_exceptions(event_id, date)` table; checked in `occursOn`. The multi-date `CalendarDatePickerSheet` (§6.5) is already the UI for it. |
| Retroactive events export forward-only to `.ics`                    | Low      | RFC 5545 has no pre-`DTSTART` occurrences; the clamp is deliberate (§3.3).            |
| `.ics` exports the template, never per-occurrence descriptions       | Low      | A **scope call, not a format limit**: RFC 5545 supports it via a second `VEVENT` with the same `UID` plus `RECURRENCE-ID`, and `EXDATE`/`RDATE` already prove per-day components are cheap here (§6.6). |
| No "mark done" / completion log                                    | Medium   | Would need a `completions(event_id, date)` table; surfaces as a check on the day card. |
| Linked note opens read-through only                                 | Low      | The link is one-way (event → note); a note does not list events that reference it.     |
| Movable feasts have no out-of-window fallback                      | Low      | Acceptable; users only see seeded window.                                              |
| No reminders / notifications                                       | Medium   | Requires platform plugin work; intentionally deferred.                                |
| Recurrence math has no automated test coverage                     | Medium   | Pure, deterministic logic; high-value target for unit tests (interval phase, Feb-29, day-31 skips). |

---

## 12. File map (quick reference)

| Concern                  | Path                                                                              |
| ------------------------ | --------------------------------------------------------------------------------- |
| Domain model             | [lib/models/calendar_event.dart](../lib/models/calendar_event.dart)               |
| Category model           | [lib/models/calendar_category.dart](../lib/models/calendar_category.dart)         |
| Category cache facade     | [lib/constants/calendar_categories.dart](../lib/constants/calendar_categories.dart) |
| Category service          | [lib/services/category_service.dart](../lib/services/category_service.dart)        |
| Category table / DAO       | [lib/database/tables/calendar_categories_table.dart](../lib/database/tables/calendar_categories_table.dart), [lib/database/daos/calendar_category_dao.dart](../lib/database/daos/calendar_category_dao.dart) |
| Category UI                | [lib/widgets/category_editor_sheet.dart](../lib/widgets/category_editor_sheet.dart), [lib/pages/calendar_categories_page.dart](../lib/pages/calendar_categories_page.dart), [lib/widgets/category_picker_sheet.dart](../lib/widgets/category_picker_sheet.dart) |
| Recurrence rules         | [lib/models/recurrence_rule.dart](../lib/models/recurrence_rule.dart)             |
| Occurrence override facade | [lib/constants/occurrence_descriptions.dart](../lib/constants/occurrence_descriptions.dart) |
| Occurrence override service | [lib/services/event_occurrence_service.dart](../lib/services/event_occurrence_service.dart) |
| Occurrence table / DAO   | [lib/database/tables/event_occurrences_table.dart](../lib/database/tables/event_occurrences_table.dart), [lib/database/daos/event_occurrence_dao.dart](../lib/database/daos/event_occurrence_dao.dart) |
| Holiday enum + facade    | [lib/constants/public_holidays.dart](../lib/constants/public_holidays.dart)       |
| Drift table (events)     | [lib/database/tables/calendar_events_table.dart](../lib/database/tables/calendar_events_table.dart) |
| Drift table (holidays)   | [lib/database/tables/public_holidays_table.dart](../lib/database/tables/public_holidays_table.dart) |
| DAO (events)             | [lib/database/daos/calendar_event_dao.dart](../lib/database/daos/calendar_event_dao.dart) |
| DAO (holidays)           | [lib/database/daos/public_holiday_dao.dart](../lib/database/daos/public_holiday_dao.dart) |
| Schema constants         | [lib/database/migrations/database_schema.dart](../lib/database/migrations/database_schema.dart) |
| Migrations               | [lib/database/migrations/database_migrations.dart](../lib/database/migrations/database_migrations.dart) |
| Calendar indexes         | [lib/database/migrations/database_indexes.dart](../lib/database/migrations/database_indexes.dart) |
| Service (events)         | [lib/services/calendar_event_service.dart](../lib/services/calendar_event_service.dart) |
| Service (holidays)       | [lib/services/public_holiday_service.dart](../lib/services/public_holiday_service.dart) |
| Backup integration       | [lib/services/backup_service.dart](../lib/services/backup_service.dart)           |
| Editor UI                | [lib/widgets/event_editor_sheet.dart](../lib/widgets/event_editor_sheet.dart)     |
| Category icons & colors  | [lib/constants/calendar_icons.dart](../lib/constants/calendar_icons.dart), [lib/constants/calendar_colors.dart](../lib/constants/calendar_colors.dart) |
| L10n                     | [lib/l10n/app_en.arb](../lib/l10n/app_en.arb), [lib/l10n/app_de.arb](../lib/l10n/app_de.arb), [lib/l10n/app_ro.arb](../lib/l10n/app_ro.arb) |

---

## Addendum (schema v15–v18): panel system, agenda, timeline, `.ics`, priority scale

Written 2026-08. Everything in this section shipped after the v14 snapshot
above; where the two disagree, this section wins.

### Bottom panel system

The area under the grid is now a mode-switched panel owned by
[lib/widgets/calendar_bottom_panel.dart](../lib/widgets/calendar_bottom_panel.dart):

- **`CalendarPanelMode`** ([lib/models/calendar_panel_mode.dart](../lib/models/calendar_panel_mode.dart)):
  `day` (the original day summary), `timeline`, `upcoming`. Persisted by name
  (`calendar_panel_mode`, forward-compatible fallback to `day`).
- `CalendarBottomPanel` owns the mode **and** the agenda filters *below* the
  page, so agenda keystrokes rebuild only the panel subtree — never the
  `TableCalendar` grid. It loads its persisted state once in `initState`;
  nothing on the settings page edits it, so it does not participate in the
  page's reload-on-return path.
- **Expand toggle** (in the mode bar): collapses the grid to zero height via
  `AnimatedSize` on the page so the panel can take the whole screen.
  Deliberately transient — restoring a hidden calendar across app opens
  would read as "the calendar disappeared".

### Upcoming agenda (search across events)

- Pure scan module [lib/utils/event_agenda.dart](../lib/utils/event_agenda.dart):
  `occurrencesInRange` expands recurrences over a clamped range
  (`maxRangeDays = 366`) using the same `CalendarEvent.occursOnUtcDay` as the
  bloc's day cache (the allocation-free hot-path variant of `occursOn`, which
  requires an already date-only UTC day); **never runs inside `eventLoader`**.
  Before the day loop it **prunes candidates** whose `[startDate, endDate]` span
  cannot intersect the window and **buckets one-time events by day** (so they
  cost zero `occursOn`), leaving only real candidates in the O(days ×
  candidates) scan — `SpecificDatesRecurrence` is the one rule left unpruned
  because it has no pre-start guard. Every survivor is still validated through
  `occursOnUtcDay`, so pruning only ever drops non-occurrences.
  `holidayDaysInRange` walks the same resolved range; `compareWithinDay` is the
  **single comparator** for same-day event order (also used by
  `EventSummaryProvider`, with `DaySummaryResolver.resolve` made stable so the
  order survives).
- Filters are one value object,
  [lib/models/upcoming_agenda_filters.dart](../lib/models/upcoming_agenda_filters.dart)
  (range preset / custom range / priority set / query / holidays + fasting
  toggles / event-type / **category allowlist** / collapse-recurring /
  collapse-fasting / follow-selected-day), persisted
  via `SettingsService.getUpcomingAgendaFilters` / `saveUpcomingAgendaFilters`.
  The query write is debounced 500 ms and flushed on dispose. **Empty priority
  set means "all"** — the filter off, never "nothing matches" (the category
  allowlist `categoryIds` works the same way: empty = every category, sorted-CSV
  codec). An elapsed custom range is dropped on load.
- **Category allowlist**: a chip section inside the filters sheet, multi-select
  over `CalendarCategories.all` (read on every build so a database switch cannot
  leave it stale), with an "All categories" reset. Applied in the scan's
  candidate pre-filter (`categoryIds.isNotEmpty && !contains`), **composed on top
  of** the inherited calendar-global `hiddenCategoryIds` — both apply, so a
  globally-hidden category stays hidden even if allowlisted. O(events), same tier
  as the priority/hidden checks; a stale allowlisted id (deleted category) is
  harmless since no event carries it.
- **Collapse recurring** (`collapseRecurring`, off by default): a switch in the
  filters sheet that, when on, shows each recurring event **once** — its next
  in-window occurrence — instead of one row per occurring day. Applied as a
  **post-filter** on the scan's `result` (two passes: tally per recurring id,
  then keep the first-seen occurrence carrying that tally as
  `EventOccurrence.occurrenceCountInWindow`; one-time events untouched), so
  `occursOn` counts are unchanged. The row's recurrence label ("Daily",
  "Weekly") carries the cadence and a "N× in window" badge says what it stands
  in for. Being an opt-in toggle, it collapses *all* recurring events
  (specific-dates included), not just high-frequency ones — the toggle is the
  escape hatch. See
  [upcoming-agenda-dense-recurrence-roadmap.md](upcoming-agenda-dense-recurrence-roadmap.md).
- **Event presentation** (`eventDisplay`, an `AgendaEventDisplay` of
  `everyOccurrence` / `perEvent` / `summary`, **`everyOccurrence` by default**,
  2026-08-23): the events layer's twin of `fastingDisplay`, replacing the
  `collapseRecurring` bool for the same reason — three mutually exclusive
  presentations, where a second flag would have encoded "collapse *and*
  summarize". Persisted by name under `calendar_upcoming_event_display`; when
  absent the retired `calendar_upcoming_collapse_recurring` boolean is read
  once (`true` → `perEvent`, `false` → `everyOccurrence`) and never written
  again. Condensing the events layer is **entirely opt-in** — an install that
  never touched it opens on exactly the rows it always had.
  - **`perEvent`** is the shipped collapse: the post-filter described above,
    one row per recurring event carrying `occurrenceCountInWindow`.
  - **`summary`** is one card per **category** — a category is to events what a
    tradition is to fasting, the thing that gives a row its colour, icon and
    identity. `EventAgenda.categorySummariesOf` folds the scan's own output
    into one `EventCategorySummary` per category (its occurrences, the count of
    **distinct** events behind them, first/last day), so it is a **post-pass**
    costing **zero** `occursOn` calls and can only ever describe occurrences the
    scan — and its filters, and the search query — already produced. The scan
    runs uncollapsed in this mode (`collapseRecurring: false`), because the card
    wants both numbers and the collapse pass would throw the occurrence tally
    away. Categories are ordered by first in-window occurrence, matching the
    time ordering of everything else in the agenda.
  - The card's subtitle leads with **distinct events** (a daily event across
    ninety days is one event, not ninety), adds the occurrence tally only when
    it exceeds that count, then the range: *"12 events · 47× in window ·
    Aug 23 – Sep 21"*. `AgendaEventSummaryRow` is not an `AgendaEntryRow`, so
    the entry counts exclude it like its two siblings, and in summary mode
    `buildAgendaRows` walks an **empty occurrence cursor** — the cards are a
    fold of the same list, so leaving the rows in would show everything twice.
- **Summary cards sort on `(priority, insertion index)`, never priority alone.**
  `List.sort` is not stable in Dart and cards legitimately share a band — every
  event category sits in the event band (0), two fasting traditions share 160 —
  so a bare priority sort let identical input reshuffle between rebuilds. Events
  lead, then the holiday card (150), then fasting (160), matching the day panel.
- **The drill-down can edit (2026-08-23).** `AgendaDayListEntry.onEdit` is an
  optional trailing action: event rows open the editor with it, while a holiday
  or fasting day has nothing to open and leaves it null, which is also what
  keeps those rows free of an empty action strip. The sheet **resolves an
  intent rather than running it** — `Future<({DateTime? focusDay, VoidCallback?
  edit})?>` — so the editor opens after the sheet has closed instead of stacked
  on top of it, the same contract `EventDetailSheet` follows. That keeps the
  sheet dumb: still no facade reads, and its one string (the edit tooltip) is
  passed in.
- **Fasting presentation** (`fastingDisplay`, an `AgendaFastingDisplay` of
  `everyDay` / `periods` / `summary`, **`periods` by default**): a
  `SegmentedButton` in the filters sheet's Display section, shown only when
  `FastingCalendar.isEnabled`. It replaced the `collapseFasting` bool on
  2026-08-23 — three mutually exclusive presentations of one thing, where a
  second bool stacked on the first would have encoded "collapse *and*
  summarize". Persisted by name under `calendar_upcoming_fasting_display`;
  when that key is **absent** the retired `calendar_upcoming_collapse_fasting`
  boolean is read once as a fallback (`true` → `periods`, `false` →
  `everyDay`) and never written again, so no configuration resets on update
  and no migration pass was needed.
  - **`periods`** is the shipped collapse, structurally different from
    collapse-recurring — fasting days never enter the event scan, and a Lent is
    a *run of one period*, not a repeated id. `EventAgenda.fastingRunsInRange`
    groups the in-window days **per (tradition, period)** — never by the
    boolean `isFastingDay`, which is wrong in both directions: a period the
    personal weekday/month scope sparsified would shatter into one-day rows,
    and two different periods that happen to touch would fuse into one span. A
    **multi-day** period (`greatLent`, `apostlesFast`, `dormitionFast`,
    `nativityFast`, `cheesefareWeek`, `lent`, `advent`, `ramadan` — the ones
    whose days can legitimately be sparse) bridges a gap of up to **7 days**;
    everything else, the year-round weekly fasts included, keeps strict
    contiguity, because bridging the weekly rule would fuse a whole window into
    one meaningless span. Each run's edges are then walked **outward past the
    window** under the same gap rule (capped at `maxRangeDays` *steps* per
    direction, via the memoized `FastingCalendar.on` — never `occursOn`), so a
    clipped period still reports its true extent. `FastingRun.dayCount` counts
    the days actually **marked**, not the calendar distance between the edges —
    for a contiguous run they agree, for a sparse one only the count is honest.
    `buildAgendaRows` emits one row per run on its first in-window day, taking
    the provider entry matching the run's tradition (entries are keyed
    `fasting:<tradition>`, and several runs may open on the same day) with its
    subtitle swapped for "Nov 15 – Dec 24 · 40 days"; a run of one marked day
    keeps the day's regime instead.
  - **`summary`** is one card for the whole window, **per enabled tradition**
    (not per fast — a window holding Lent *and* the weekly rule would otherwise
    be right back at several cards). `EventAgenda.fastingSummariesInRange`
    walks the window once, accumulating one `FastingSummary` per tradition:
    the weekday set actually marked, first/last marked day, the marked-day
    count, and the distinct span periods present in first-seen order. Every
    number is **window-scoped** — unlike a run, which reports a period's true
    extent because it *is* the period, a summary describes "fasting in this
    window", and claiming days outside it would make the card disagree with the
    list it summarizes. Traditions with no marked day produce nothing, and the
    result follows `FastingTradition` declaration order (matching
    `FastingCalendar.on`). `buildAgendaRows` emits the cards **before the first
    month/day header** as `AgendaFastingSummaryRow`s — deliberately *not*
    `AgendaEntryRow`s, so the panel's "N entries" count leaves them out with no
    extra logic: a card summarizes entries rather than being one. The entry is
    synthesized in the agenda layer (icon/colour/description/priority from the
    tradition's `FastingTraditionStyle`, exactly as a run row resolves them),
    with the title preferring `titleOverride`, then the window's single named
    fast, then the tradition's name. The subtitle is three fragments joined by
    `' · '`: the weekday pattern (all 7 → `recurrenceDaily`, Mon–Fri →
    `recurrenceWorkdays`, Sat–Sun → `recurrenceWeekends`, else abbreviated
    locale weekday names joined with `', '` — Monday-first, no conjunction,
    whose placement is locale-dependent), the span (exact `rangeLabel` up to
    **62 days**, a `monthRangeLabel` beyond it), and `upcomingFastingSpanDays`.
    Tapping the card focuses its first in-window day.
  - **`everyDay`** is the uncollapsed listing, one row per marked day.
  - The query filter is handed to the run walk **and** the summary scan, so
    neither can claim days the search excluded. `fastingDisplay` stays out of
    `restrictiveFilterCount` and the summary-chip row for the same reason
    `collapseRecurring` does: it condenses rows, it never hides content.
- **Holiday presentation** (`holidayDisplay`, an `AgendaHolidayDisplay` of
  `everyDay` / `summary`, **`everyDay` by default**, 2026-08-23): the two-value
  twin of `fastingDisplay`, with no `periods` analogue because a holiday is a
  single day and has no run to collapse into. A second `SegmentedButton` under
  the fasting one in the filters sheet's Display section — **ungated**, since
  holidays are always available where fasting waits on `FastingCalendar
  .isEnabled`. Persisted by name under `calendar_upcoming_holiday_display`; a
  new axis rather than a replacement, so unlike the fasting key it has no
  legacy value to fall back on and no migration.
  - **No scan of its own.** `_recomputeHolidays` is untouched: the days are
    already resolved, query-filtered and ascending, so `summary` is a pure
    *rendering* choice over the same list. `holidayDisplay` in the view's
    `_rowsFor` memo key is the whole mechanism — `didUpdateWidget` needs no
    branch for it, and flipping the control costs zero `occursOn` calls.
  - In `summary` mode `buildAgendaRows` walks an **empty** holiday cursor (so
    no day header or entry row is emitted for a holiday-only day) and builds
    one `AgendaHolidaySummaryRow` from the same `holidayDays` list. Icon,
    colour, key and priority mirror `PublicHolidaySummaryProvider` exactly;
    the title is the existing `upcomingShowHolidays` ("Holidays") and the
    subtitle is `"<upcomingHolidayCount> · <rangeLabel(first, last)>"`.
- **Summary cards sort by `DaySummaryEntry.priority`**, not by a hardcoded
  order: the public holiday sits at 150 and fasting defaults to
  `FastingRowPlacement.afterHolidays` (160), so the holiday card leads — and a
  tradition the user placed `first` (10) outranks it, exactly as it does in the
  day panel. One ranking rule for both surfaces instead of two.
- **The drill-down** (`agenda_day_list_sheet.dart`, 2026-08-23) is shared by
  both summary cards: an `IconButton` on the card's right (`onShowAll`,
  `upcomingShowAllDays`) opens `AgendaDayListSheet`, which lists every day the
  card stands for and pops the tapped one; the view routes it back through
  `onDaySelected`, already tagged `CalendarSelectionSource.agendaRow` by the
  panel, so choosing a day never re-anchors the list it came from. Rules:
  - **Its scope is the card's scope** — the agenda window. A sheet reaching
    further would contradict the number the user just tapped. This is also why
    `FastingSummary` carries `days`: re-walking the window in the sheet would
    drop the scan's `dayFilter` and quietly disagree with `dayCount`. The two
    are the same list by construction (`days.length` *is* the count).
  - **The sheet is deliberately dumb** — no `PublicHolidays`, no
    `FastingCalendar`, no `AppLocalizations`. It renders a pre-resolved
    `AgendaDayList` (the card's own title + subtitle, plus `AgendaDayListEntry`
    rows), which is what lets one sheet serve both cards and a third source
    later. The entry builders live beside `_fastingSummaryEntry` in
    `agenda_list_view.dart`, and are called **on press**, never per frame.
  - Row titles differ per source on purpose: a holiday list leads with the
    **name** (every row is a different holiday, `labelOf` carrying the
    "(observed)" suffix) and a fasting list with the **date** (every row
    belongs to the same fast, so only the date varies). Both dates go through
    the existing `AgendaListView.dayHeaderLabel`, inheriting its locale cache
    and its Today/Tomorrow labels; the fasting subtitle reuses
    `FastingSummaryProvider` filtered to the tradition, exactly as
    `_fastingEntries` does for run rows.
- **Three independently-suppressible layers.** The sheet presents them as three
  peer toggles — **Events / Holidays / Fasting** — with All / Recurring /
  One-time as a `SegmentedButton` *under* Events. The model underneath is
  unchanged: one mutually-exclusive `AgendaEventType` axis where **Events off ⇔
  `none`**, applied in the scan's candidate pre-filter (`recurring` =
  `rule is! OneTimeRecurrence`, so specific-dates counts as recurring; `none`
  short-circuits the event scan to empty, which is how "upcoming holidays
  without events" is expressed). The `upcomingEventTypeNone` ARB key is gone —
  the state is now reached by switching Events off, and the *summary* chip for
  it reads `upcomingEventsHidden` ("No events"). Holidays and fasting are day
  annotations toggled independently and interleaved by `buildAgendaRows`'
  three-cursor ascending merge (`EventAgenda.fastingDaysInRange` mirrors
  `holidayDaysInRange` and reuses `FastingSummaryProvider`). The **fasting chip
  is hidden** unless a tradition is configured (`FastingCalendar.isEnabled`),
  and the priority + category sections hide while Events is off. Both annotation
  scans respect the text query (matched against their localized labels).
- **The window starts today, unless `followSelectedDay` is on** (default off).
  The anchor is **panel-owned state** (`_CalendarBottomPanelState._agendaAnchor`
  → `UpcomingAgendaView.anchorDay`), not `CalendarPageLoaded.selectedDay`,
  because the selection and the window are two different things. `_syncAnchor`
  holds every rule: following off ⇒ the anchor is today (which also picks up a
  date rollover on the next rebuild); no `previous` ⇒ resolve from scratch
  (filters loaded, or the toggle just flipped on); an
  `CalendarSelectionSource.agendaRow` selection **never** re-anchors; anything
  else follows a selection that actually changed. A custom range still overrides
  the anchor entirely, and the rescan stays guarded (`anchorChanged =
  !hasCustomRange && anchor moved`), so an anchor move under a pinned range
  costs nothing. Not persisted: reopening starts from today. The three
  wall-clock reads that must **stay** on `now()` — the picker's initial range,
  the Today/Tomorrow row headers, and `withoutElapsedRange` — are not anchor
  material.
- **`SelectCalendarDay` carries a `CalendarSelectionSource`**
  ([lib/models/calendar_selection_source.dart](../lib/models/calendar_selection_source.dart)):
  `grid` (a day cell), `agendaRow` (a row in the agenda) or `navigation`
  (initial load, "today", the month/year picker). Required on the event, so a
  new dispatch site has to decide rather than silently inheriting a default that
  would make the agenda re-anchor on its own rows again. It rides on
  `CalendarPageLoaded.selectionSource` and is **excluded from both
  `sameGridInputs` and `samePanelInputs`** — nothing renders from it, so
  re-selecting the same day from a different surface must not repaint 42 cells;
  a source change that matters always arrives with a `selectedDay` change, which
  both tests already catch.
- **The anchor rescan stays cheap and unsurprising** (2026-08 regression fix,
  [calendar-anchor-perf-regression-2026-08.md](calendar-anchor-perf-regression-2026-08.md)):
  a query-only change debounces the scan ~200 ms (the field stays live); an
  anchor-driven rescan is synchronous and scrolls the agenda to the top so the
  tapped day becomes the first row; and the panel's `BlocBuilder` uses
  `CalendarPageLoaded.samePanelInputs` (every input **except** `focusedDay` /
  `format`), so month paging no longer rebuilds the panel or re-runs the scan —
  paired with `_onChangeFocusedDay`'s no-op guard against the page-settle emit.
- **Filter chrome lives in a sheet, not the panel** (2026-08-22 redesign,
  [upcoming-agenda-redesign-roadmap.md](upcoming-agenda-redesign-roadmap.md)).
  [agenda_filters_sheet.dart](../lib/widgets/agenda_filters_sheet.dart) holds
  Period / Show / Priority / Categories / Display, edits a **local draft** and
  returns it on Apply (never live-applies — that would rescan behind the sheet);
  its Reset restores every sheet-owned field but **preserves `query`**, which
  the sheet does not own. Inline the panel keeps only: the search field, a
  `Badge.count` on the tune button, one horizontally-scrolling row of removable
  summary chips, and the header line. `filtersExpanded` and its settings key are
  retired (the orphaned stored value is inert; no migration).
- **Summary chips show only what is *narrowing* the list** — custom-or-non-default
  window, event type, priorities, categories. `UpcomingAgendaFilters
  .restrictiveFilterCount` is the single definition the badge and the chip row
  share. Layer additions (holidays, fasting) and the collapse switches are
  deliberately excluded: they add or condense rows, so they can never answer
  "why is this missing", which is the question the row exists for. Each chip's
  body opens the sheet and its "×" (tooltip `upcomingRemoveFilter`) resets that
  one filter.
- **The Period axis is one mutually-exclusive choice across six chips**
  (2026-08-29): the three rolling presets (`UpcomingAgendaFilters.rangePresets`
  = 7 / 30 / 90 days counted forward from the anchor), two calendar-year
  windows, and Custom. The year windows are
  `AgendaPeriodMode { rollingDays, wholeYear, restOfYear }` on the filters
  model — an enum rather than more `rangePresets` entries because they are
  *anchored*, not counted: `wholeYear` is 1 Jan – 31 Dec of the anchor's year
  and **reaches into the past on purpose** (a birthday in March is still
  findable in August, which is what the mode exists for), `restOfYear` runs
  from the anchor to 31 December. `presetWindow(anchor)` derives both on every
  read rather than storing dates, so unlike a pinned custom range neither can
  go stale — there is no `withoutElapsedRange` equivalent to write. A year is
  at most 366 days, exactly `EventAgenda.maxRangeDays`, so `resolveRange` never
  clips December off a window the header claims to show, and the scan gains no
  new worst case (a query already reached 366 days). Picking a year chip clears
  any pinned range; picking a preset returns to `rollingDays` and keeps its
  `rangeDays`, so dropping the year view returns to the rolling window the user
  last chose. Persisted by name in `calendar_upcoming_period_mode`; an absent
  key is `rollingDays`, which is what every existing install meant.
  `AgendaFiltersSheet.periodModeLabel` is shared with the panel's summary chip
  so the sheet and the chip that undoes it cannot name a window differently.
  In `didUpdateWidget` the anchor-driven rescan is suppressed while `wholeYear`
  is active and the anchor stays inside its year — the window did not move, so
  a grid tap must not pay for a 365-day rescan.
- **The Custom period chip is an `InputChip`** whose delete "×" (tooltip
  `upcomingClearRange`) clears the range back to the anchored preset window; the
  "×" shows only while a range is active. `showCheckmark: false` keeps the
  `date_range` avatar as the chip's identity instead of swapping in a checkmark.
  It now lives in the sheet's Period section, labelled with the active range.
- **The header line carries the anchor chip.** While the anchor drives the
  window and sits off today (`!hasCustomRange && anchorDay != today`), an
  `InputChip` reads `upcomingAnchorFrom` ("from Aug 25") and its "×"
  (`upcomingResetAnchor`) returns the window to today. With `followSelectedDay`
  off the anchor is always today, so the chip never appears.
- Text matching folds case *and* diacritics through the note search's
  `normalizeForSearch`, so "sarbatoare" finds "Sărbătoare" here exactly as in
  note search. Holiday labels match localized.
- Rendering: [lib/widgets/upcoming_agenda_view.dart](../lib/widgets/upcoming_agenda_view.dart)
  (controlled; owns nothing persistent) over
  [lib/widgets/agenda_list_view.dart](../lib/widgets/agenda_list_view.dart)
  (row list memoized on input identity + locale; holiday days interleave so a
  holiday-only day still gets a header; rows reuse `EventSummaryProvider`, so
  agenda and day panel cannot drift). `AgendaRow` has **three** variants:
  `AgendaMonthHeaderRow` (emitted only when the built rows span ≥ 2 months, with
  `showYear` when the window crosses one), `AgendaDayHeaderRow`, and
  `AgendaEntryRow` (carrying `occurrenceCount`). **Every entry row is an
  `_AgendaCard`** — the roomier `Card` + accent-stripe + `ListTile` +
  `CircleAvatar` layout, holidays and fasting included (those get
  `trailing: null`, having no event to edit or open). Two restylings were tried
  on 2026-08-22 and both reverted: a denser card interior, and slim tinted
  annotation rows for the `entry.event == null` entries. The bigger card is the
  intended look on every row type — do not restyle without asking. All four
  `DateFormat` skeletons the agenda uses are cached per locale on
  `AgendaListView` (`rangeLabel`, `anchorLabel`, `monthLabel`,
  `dayHeaderLabel`) — never construct one per row. Note `buildAgendaRows` now
  formats dates for a collapsed fasting span, so a bare unit test of it must
  `initializeDateFormatting` first; in the app the localization delegates
  already have.

### Day timeline

[lib/widgets/day_timeline_view.dart](../lib/widgets/day_timeline_view.dart) +
pure layout [lib/utils/day_timeline_layout.dart](../lib/utils/day_timeline_layout.dart):
the only surface rendering `EventTime.durationMinutes`. Overlapping events
pack into side-by-side columns **per overlap cluster**; all-day events pin to
a chip strip above the grid; a "now" line shows on today. Blocks use
`colorValue ?? category.color` (the `EventDayBarProvider` rule). All vertical
placement goes through one `_offsetOf` helper so gridlines, blocks and the
now-line cannot drift.

### `.ics` export

[lib/utils/ics_serializer.dart](../lib/utils/ics_serializer.dart) →
`ImportExportService.exportCalendar` → `ExportCalendarRequested` on
`ImportExportBloc` → `shareExport`. Floating local time (the app stores no
timezone); `DTSTART` moves to the first *real* occurrence so `BYDAY`/interval
phase can't drift; workdays emit `BYDAY=MO..FR` + `EXDATE`s for holidays;
holidays-only and specific-date sets emit `RDATE`s; expansions bounded by
730 days. `ExportFormat` was deliberately **not** extended (it would leak
into note-format pickers); `.ics` is registered with `sweepStaleExports`.
Entry point: calendar app-bar overflow menu.

### Priority scale (v18): 1 is highest

- Stored priorities read like **P1..P5 — lower number = higher priority**.
  The v18 migration flips existing rows (`p -> 6 - p`) inside the upgrade
  transaction, flips the persisted agenda priority filter, and folds the
  retired `calendar_upcoming_min_priority` threshold key into
  `calendar_upcoming_priorities`.
- **Backup version is now 7**; backups < 7 carry the old 5-is-highest values
  and are flipped on import in `BackupService.importFromJson`.
- Display lives in one place:
  [lib/constants/event_priorities.dart](../lib/constants/event_priorities.dart)
  (`iconFor`: double-up / up / drag-handle / down / double-down;
  `labelOf`: Highest..Lowest). The editor picks priority with icon+label
  ChoiceChips (the numeric stepper died with the flip — a "+" that lowers
  priority cannot be made unambiguous); the agenda's filter chips carry the
  same icons; agenda row badges show the label for non-Normal priorities.
- Ranking sites all agree: `EventAgenda.compareWithinDay` (ascending),
  day bars / day summary map `event.priority - kMinEventPriority` into the
  0-is-top band, and the `.ics` `PRIORITY` maps 1→1, 3→5, 5→9 (RFC 5545
  shares the 1-is-highest direction).

### Navigation fix that lives here

Opening an event's linked note (and last-location restore) now passes
`NoteRepository.noteToMetadata(row)` to the editor, so the title bar shows
the real note title instead of "New note".

## Addendum (schema v26): presence tracking

Recurring events can opt in to **presence tracking** (`tracks_presence`, v26
additive column; editor switch at the end of the When section, shown when
the rule has many occurrences, save mirror `recurring && flag` like
`retroactive`'s). A missed day is one live row in `calendar_event_absences`
— PK `{event_id, day}`, plus the five notes/folders CRDT columns, stamped in
`EventAbsenceDao` (`db.generateHlc()`, `db.deviceId`, read-then-write
`version + 1`). Un-marking **tombstones** the row; re-marking resurrects it
with `created_at` intact — a last-writer-wins element set, cloud-ready from
birth (cloud-sync phase-02 — now **v31** — wires transport; absences
**sync**, and since v28 per-occurrence descriptions do too).

- **One read entry point**: `EventPresence`
  (`lib/constants/event_presence.dart`) — `appliesTo(event)` is
  `tracksPresence && rule is! OneTimeRecurrence` (specific-dates
  participates), `isMissed(eventId, day)` is an O(1) probe safe inside
  `DayBarProvider.barsFor`. Published by `EventPresenceService` (the
  `EventOccurrenceService` shape minus the global flag — opt-in is per
  event); `reset()` clears the singleton **and** the facade.
- **Presence is render-only.** It never changes `occursOn`, the bloc's day
  cache, `EventAgenda` scans, `countOccurrences` labels, or `.ics`.
  `SetOccurrenceMissed` / `ClearOccurrenceMissed` bump `occurrenceRevision`
  and never `_invalidateDayCache()`.
- **Display**: `CalendarMissedDisplay` (`faded` | `hidden`) on
  `CalendarAppearance` (`SettingsKeys.calendarMissedDisplay`, default
  `faded`, Calendar Settings → Events, in reset-to-defaults). Grid bars fade
  with `CalendarColors.missedEventAlpha` or are skipped before consuming a
  `maxDayBars` slot; the agenda (mode in its row-memo key; a day whose only
  occurrence is hidden loses its header, though the panel-level count still
  counts hidden occurrences) and the timeline (all-day chips included,
  filtered before layout) follow the setting; the **day summary panel always
  shows missed rows, faded** — it is the toggle surface. Marking: a trailing
  `IconButton` on presence-tracked day-panel rows (replaces the chevron), or
  the Present/Missed `SegmentedButton` in the detail sheet (immediate write
  + haptic, no debounce).
- `DaySummaryEntry` carries `presenceTracked` / `missed` (both in `props` —
  the agenda's identity-based row memo depends on them).
- **Backup**: additive `eventAbsences` key — live rows only, no CRDT fields
  (backups are not a sync channel; `importAbsence` regenerates identity
  while preserving `createdAt`/`updatedAt`), no version bump, and the same
  absent-key-with-present-`calendarEvents` clear rule as occurrences.
- Since v27, a single-event delete tombstones the event and bulk-tombstones
  its absences in one transaction; occurrence descriptions are still
  hard-deleted (device-local), and bulk wipes stay hard.
- Design record: `docs/presence-tracking-roadmap.md`.

## Addendum (schema v27): `calendar_events` CRDT + agenda/detail fixes

`calendar_events` carries the five CRDT columns since v27 — with
`DEFAULT ''` on `hlc_timestamp`/`device_id` (an `ALTER TABLE` on a populated
table demands a default; the migration backfills real identity in one
`UPDATE` bound to `generateHlc()`/`deviceId`, and every write path stamps,
so `''` never survives a write). Layering is unchanged: the domain
`CalendarEvent` has no CRDT field; everything lives in `CalendarEventDao`.

- `upsert` — read-then-write: miss → `version 1`; hit → fresh HLC/device,
  `version + 1`, `createdAt` masked, and **explicit `isDeleted: false` +
  `deletedAt: null`** — an id-reusing restore over a tombstone must
  resurrect, never update an invisible row. `importData`'s hard wipe stays
  hard forever as the second belt.
- Single-event delete = `softDeleteById` (the `softDeleteNote` shape) +
  `EventAbsenceDao.tombstoneForEvent` (bulk, one shared HLC) + the
  occurrence cascade (hard here; tombstoning since v28), in one transaction.
  `deleteAll` and import wipes stay hard — "Delete all events" promises
  permanence; cloud-sync phase-02 (now **v31**) owns the synced-wipe
  decision and needs only `owner_id` + transport.
- `reassignCategory` — one `customUpdate`: `version = version + 1`, one
  shared HLC, `Variable<DateTime>` binds, `AND is_deleted = 0`.
- `getAll()` filters `is_deleted = 0` behind the now-**partial**
  `idx_calendar_events_start_date`; the migration `DROP`s the full index
  first (`IF NOT EXISTS` would strand upgraders on the full one). One
  filtered read path → grid, panels, agenda, timeline, backup export and
  `.ics` agree for free. A real v26→v27 migration test pins the backfill,
  the index swap and idempotence.

Agenda: rows are built once by the pure top-level `buildAgendaRows`
(`agenda_list_view.dart`; pure *given* the `EventPresence` /
`OccurrenceDescriptions` facades — memos over it must key
`occurrenceRevision`). `UpcomingAgendaView` owns the six-key memo and
derives the panel header count from the `AgendaEntryRow`s it renders —
exact in hidden mode, counting visible entries (holiday entries
individually). `AgendaListView` is a stateless renderer of `rows`. The day
summary panel's count is deliberately unchanged — it always shows missed
rows, so its count already matches its screen.

Detail sheet: the date row shows the opened occurrence day (`widget.day`;
the presence toggle directly beneath marks that date), and a label-less
`Icons.event_repeat_rounded` row — `eventDetailsSeriesStart`, "Repeats
since {date}" — follows the recurrence-pattern row for recurring events
whose series anchor differs.

Design record: `docs/calendar-cloud-readiness-roadmap.md`.

## Addendum (schema v28): per-event description scope + occurrence CRDT

The v24 global per-occurrence-descriptions setting is gone. Each recurring
event carries `per_occurrence_descriptions` (default 0, the
`tracks_presence` twin): on, the event keeps a separate description per day
with its own description as the template; off, one shared description
updates everywhere. The v28 migration converted intent settings-driven —
exactly when the stored value of the frozen literal
`'event_per_occurrence_descriptions'` was `'true'`, every live repeating
event was flagged on (`WHERE rule_kind != 'oneTime' AND is_deleted = 0`),
so a global-ON user saw zero change; the `SettingsKeys` constants and the
service's whole flag half (`enabled`/`setEnabled`/`_readEnabled` and the
post-import re-reads) are deleted, and the settings-page entry is gone.

- **The gate lives in the facade**: `OccurrenceDescriptions.appliesTo` =
  `event.perOccurrenceDescriptions && rule is! OneTimeRecurrence`. Because
  `descriptionFor` calls it, the detail sheet, day-panel badge, agenda
  narrowing and both row surfaces followed the flag with no widget edits.
- **The editor reads its draft, never the saved row**: `_scopeGateOpen`
  (= rule-has-many-occurrences && the sheet's `_perOccurrenceDescriptions`
  state) gates `_scopeControlVisible`, `_resolveOccurrenceOutcome` and
  `_syncScopeToRule`'s early-out. The switch sits in Details directly above
  the description field; flipping it off mid-edit parks the day text
  exactly like flipping to one-time, and Save mirrors `recurring && flag`.
- **`calendar_event_occurrences` carries the five CRDT columns** (the
  second populated-table conversion: `DEFAULT ''` identity + one-statement
  backfill). `EventOccurrenceDao` is the `EventAbsenceDao` shape plus
  `description`: `getActive`, read-then-write `upsert` (explicit
  `isDeleted: false` + `deletedAt: null` on the update branch — re-writing
  a reset day resurrects its row, `created_at` intact), `tombstone`
  (= "reset this day"), `tombstoneForEvent`, `importOccurrence` (fresh
  identity, audit timestamps preserved); the hard variants serve
  wipes/import only.
- **A single event delete tombstones all three tables** — event, absences,
  occurrences — in one transaction, one statement each.
- **Backups**: the flag rides the event map additively; version stays 7.
  Pre-v28 backups restore with every flag off and rows dormant — the flag
  was never in the settings allowlist, and an archive that never carried
  intent is not mined for it; enabling an event restores its imported day
  texts.
- Phase-02 (renumbered **v31**) syncs occurrences —
  `keyLastEventOccurrenceHlc = 'last_event_occurrence_hlc'`, delta feeds in
  the notes shape.

Design record: `docs/description-scope-roadmap.md`.

---

## Addendum (schema v29): event templates

Reusable presets: everything an event needs **except a date**. Applying one to
a day stamps out a `CalendarEvent` anchored there.

- **A separate entity from categories, deliberately.** A category is a
  taxonomy — one row per kind of thing — while a user wants several presets
  inside one ("Push day" and "Leg day" both under Gym). Folding defaults into
  `calendar_categories` would cap that at one preset per category forever.
- **`calendar_event_templates`** (PK `id`) carries category, `rule_kind` /
  `rule_payload`, `start_minute` / `duration_minutes`, description, icon,
  colour, `tint_icon`, priority, `retroactive`, `count_occurrences` /
  `count_style`, `tracks_presence`, `per_occurrence_descriptions`,
  `sort_order`, audit timestamps and the five CRDT columns **from birth** (the
  v27 retrofit priced the alternative: five ALTERs plus a backfill; a table
  that starts empty gets the shape for free, with no `DEFAULT ''` deviation).
- **`name` doubles as the stamped title** — no `title` column. Categories set
  the one-label precedent; a separate column is additive later.
- **No `note_id`**: a linked note is per-instance, and stamping one note onto
  many events would break the money ledger's per-(day, note) attribution.
- **Nullable means "defer to the default at apply time"**, and only where
  `null` already means that on the event: `icon_key`, `color_value`,
  `start_minute` / `duration_minutes` (null time = all-day, which is why there
  is **no `all_day` column**), `description`, `rule_payload`.
- **`SpecificDatesRecurrence` collapses to one-time on capture** — absolute
  dates are meaningless in a template.
- **`EventTemplate.buildEvent` clears the repeat-only flags for a one-time
  rule** (`retroactive`, `countOccurrences`, `tracksPresence`,
  `perOccurrenceDescriptions`), matching the editor's own save guards.
- **No index**: the read path is one `getAll()` into memory at startup over a
  table of dozens of rows (the v24 occurrences precedent).
- **`RecurrenceCodec`** (`lib/models/recurrence_rule_codec.dart`) is now the
  one encoding of a rule into `rule_kind` / `rule_payload`;
  `CalendarEventService` delegates to it. Two hand-written copies would drift
  the first time a rule kind is added, and a template that encodes `weekly`
  differently from an event is a rule that silently changes meaning when
  applied.
- **Two entry points, and only two.** Primary: **long-press a day cell** →
  `EventTemplatePickerSheet` → **immediate create** plus an Undo snackbar,
  because the two things that normally need confirming — title and date — are
  already decided. When the rule does not fire on the pressed day (a weekly
  template whose weekday set excludes it) the snackbar names the day it will
  actually land on instead of letting it look like nothing happened. Secondary:
  **"Save as template"** at the bottom of the event editor's scroll body, above
  Delete — the inline header keeps one leading icon (`close`, or `back` on
  the detail-sheet reopen loop, 2026-08-31 — see §6.3) | title | Save.
- **Backups**: additive key `eventTemplates`, version stays 7. Strand rule
  keyed to **categories**, not events: an absent key alongside a present
  `calendarCategories` clears the table, because the category import just wiped
  the id space templates point into. Imported after categories.
- `ImportExportService.archiveVersion` stays **1** — the notes `.zip` carries
  no calendar data.

## Addendum (schema v30): skip this occurrence

Cancelling a single occurrence of a recurring event. **Not** the same thing as
marking one missed, and the difference is the whole design:

| | missed (v26) | skipped (v30) |
| --- | --- | --- |
| gate | `tracksPresence` opt-in | any recurring event |
| layer | rendering | **membership** |
| `occursOn` | still true | **false** |
| day cache | must **not** invalidate | **must** invalidate |
| revision | `occurrenceRevision` | **`membershipRevision`** |
| `.ics` | exports as an occurrence | exports as an `EXDATE` |

- **A new table, not a `status` column on `calendar_event_absences`.** A
  discriminator would make "a live row means missed" — the invariant three
  surfaces and the backup strand rule are built on — conditional on every
  reader remembering to filter it. The roadmap's floated `status` column
  remains available *within* the absence table for partial/late.
- **The filter lives in `CalendarEvent.occursOn`, and only there.** That is the
  one choke point the day cache, `EventAgenda`, `monthNetFor`, the detail
  sheet's upcoming chips and the date pickers already go through, so a skip
  reaches all of them without any of them knowing skips exist. Reading a static
  facade from the model layer follows the precedent `RecurrenceRule.occursOn`
  already set with `PublicHolidays`.
- **This is the deliberate inverse of the hidden-category filter**, which is
  render-time only, forever: hiding a category changes what you are looking at,
  cancelling an occurrence changes what is there. Both rules must stay stated
  side by side.
- **The `OneTimeRecurrence` gate** keeps a stale row from ever hiding a
  one-time event — cancelling its only occurrence is a delete, offered
  separately.
- **`membershipRevision` cannot ride `occurrenceRevision`.** That revision
  contractually means "the overlay changed, do **not** rescan";
  `UpcomingAgendaView` forwards it into its row memo but never re-runs its
  scan on it. A skip must rescan. It is also load-bearing for the emit itself:
  after a skip `allEvents` is value-equal, so without a bump `Equatable` drops
  the state and the grid keeps drawing an occurrence that no longer exists.
- **Counts are unaffected**, and correctly so: `RecurrenceFormatter.countLabel`
  is elapsed-*period* arithmetic from `startDate`, so a cancelled Week 3 leaves
  Week 4 as Week 4. This mirrors decision 3 of the presence roadmap.
- **`markSkipped` also clears any absence mark on the day** — an occurrence
  that does not exist cannot have been missed, and leaving the mark would
  resurface it the moment the skip is undone.
- **`.ics` needs explicit handling.** `IcsSerializer` queries `event.rule`
  directly so it can drop `retroactive`, which drops the skip filter with it.
  Three sites: `_firstOccurrenceOf` skips cancelled days so `DTSTART` is always
  real; `_exceptionDates` emits an `EXDATE` per cancelled day **only for rules
  that actually emit an `RRULE`** (`_hasRrule`); `_additionalDates` filters
  cancelled days out of the `RDATE` list, since an RDATE that is also an EXDATE
  is noise.
- **UI, two entry points, both routed through the page** so persistence stays
  on one path: "Skip this day" in the detail sheet (returns
  `EventDetailAction.skipOccurrence`, page dispatches with Undo — the sheet
  cannot write, because the occurrence it describes is about to stop existing),
  and a **"Skipped days"** `_PickerTile` in the editor's When zone (editing +
  recurring only) opening `CalendarDatePickerSheet.pickMulti`. The sheet stays
  write-free: `EventEditorSaved.skippedDays` (null = untouched) is diffed
  against the facade by `calendar_page.dart`.
- **`pickMulti` gained `allowEmpty`** (default false, preserving its contract).
  Skips are the first caller where an empty set is legitimate — clearing it is
  how the user restores every occurrence.
- **Backups**: additive key `eventSkips`, version stays 7, standard event-keyed
  strand rule. Getting this wrong is worst of the three: a stale skip does not
  render a wrong colour, it **hides** occurrences of whatever event later takes
  the id. Same reason `EventSkips.resetCache()` in the reset contract matters
  more here than for presence.

## Addendum: day-cell tint layers

The day cell's background is now a general, settings-driven **tint layer**
system rather than a single hardcoded fasting wash.

- `CellTintProvider` / `CellTintResolver`
  (`lib/services/cell_tint_resolver.dart`) mirror `DayBarProvider` /
  `DayBarsResolver`, including the purity contract: `tintFor` runs for every
  visible cell on every rebuild, so static facade probes only — no I/O, no
  BLoC, no recurrence expansion.
- The cell paints at most one **wash** plus one **edge stripe**, both arriving
  with alpha already applied. `CalendarDayCell` stays a dumb painter and never
  learns which source won.
- **Event tint**: exactly one event contributes — the top one by
  `EventAgenda.compareWithinDay`, the same event the panel lists first.
  Averaging a day's colours yields a hue no event on it actually has. Colour
  follows the day-bar rule (`colorValue ?? category.color`) and ignores
  `tintIcon`, like every other grid surface. **Alpha encodes priority**
  (`CalendarColors.eventTintAlphaByPriority`, P1 strongest) — that is the whole
  point of the feature, so the ramp must stay monotonic.
- A missed occurrence keeps the wash it won but fades by `missedEventAlpha`; a
  hidden one cannot claim it at all.
- **Conflict is a user setting**, `CalendarTintConflict { eventWins,
  fastingWins, both }`. Under `both` the winner paints the wash and the
  runner-up a 3px left stripe at `CalendarColors.cellEdgeAlpha` — two stacked
  washes blend into a third colour belonging to neither source. A non-uniform
  `Border` cannot carry a `borderRadius`, hence the `Stack`.
- **Off by default** (`calendar_event_tint`): it repaints most cells on a busy
  calendar and competes with the marker strip the user already reads.
- Adding a source (holiday, money, training block) is implementing
  `CellTintProvider` and picking a band in `CellTintResolver.defaults` — no
  call site changes.

## Addendum: presence adherence, and calendar perf

- **Adherence stats** ship as a pure util, `PresenceAdherence.compute` — see
  the addendum in `docs/presence-tracking-roadmap.md`.
- **`monthNetFor` moved into `CalendarBloc`** and is memoized per month, paired
  with `NoteMoneyLedgerService.revision`. It used to be an un-memoized O(all
  events) scan running from `headerTitleBuilder` on every grid rebuild. The
  revision pairing is load-bearing: the ledger's per-note change stream
  rewrites entries **outside** every handler that invalidates the day cache.
- **`EventDayBarProvider` now sorts by `EventAgenda.compareWithinDay`** and
  `DayBarsResolver.resolve` uses the stable insertion-index sort
  `DaySummaryResolver` already had. Equal-priority stripes previously fell back
  to the resolver's `event:<uuid>` tie-break, so the grid and the day panel
  disagreed about which event was on top. **Visible change**, intended.
- `_buildDayCell` no longer calls `DateTime.now()` and `accentOr` per cell (42×
  a frame); both are hoisted into the grid build. The bar and tint resolvers
  are memoized on `_CalendarViewState`.
- `CalendarColors.moneyPositive` / `moneyNegative` replace the literals
  duplicated across three money surfaces, and `category_editor_sheet.dart` now
  reads `CalendarColors.swatchPalette` instead of its own copy.

## Addendum (2026-08-24): keyboard-aware grid, agenda card layout

- **The soft keyboard collapses the month grid to a week.** Typing in the
  agenda search field used to leave the agenda invisible: the grid is the
  non-flexible child of the page `Column`, so the `Expanded` bottom panel
  absorbed the entire keyboard shrink. The grid now renders
  `CalendarFormat.week` while the keyboard is up. This is an **ephemeral
  render-time override** — no `ChangeCalendarFormat` is dispatched, so
  `CalendarBloc.state.format` stays the user's pick and the filter sheet keeps
  showing it.
- **The body does not resize for the keyboard.** The page `Scaffold` sets
  `resizeToAvoidBottomInset: false`, so the `Column`'s constraints never
  change when the keyboard opens and overflow is structurally impossible —
  the keyboard covers the bottom of the panel, and the grid's week-collapse
  progressively reveals agenda content above it. The compensation lives in
  `CalendarBottomPanel.build`, which reads `MediaQuery.viewInsetsOf` once and
  threads `bottomInset` into all three panel modes as extra bottom padding on
  their scrollables (agenda sliver padding, day-summary list, timeline
  scroll), so scroll extent grows and everything stays reachable. The FAB
  intentionally gets no inset handling: it sits behind the keyboard, where it
  was unusable anyway. A short-screen regression test pumps every frame of
  the collapse and restore — stepped and ramped, both directions — asserting
  no overflow; it goes red if the resize flag is flipped back.
- **`_KeyboardInsetProbe` still sits above the `Scaffold`.** Its original
  reason was that `ScaffoldState.build` strips the bottom inset from the
  body's `MediaQuery` whenever `resizeToAvoidBottomInset` is true — a read
  below it saw `0` forever, and the first implementation silently did
  nothing. With resize now off, body-level reads work (the panel uses one),
  but the probe stays: it reads the inset in `didChangeDependencies` and
  publishes it as a `ValueNotifier<double>` so the **grid** subtree gets its
  week-collapse signal without depending on `MediaQuery` at all, and the
  probe's `build` returns `child` unchanged so an inset frame never rebuilds
  from the top. (It published a thresholded `bool` until the 2026-08-25
  coupling work below; `didChangeDependencies` always fired once per inset
  frame, and the `> 0` comparison was the only thing throwing the fraction
  away.)
- **The keyboard rebuilds the panel's padding, never its scan.** An inset
  frame rebuilds `CalendarBottomPanel` and its mode child (the padding is
  live), but `sameGridInputs` / `samePanelInputs` are untouched and the
  agenda's `_rowsFor` memo absorbs the rebuild. Tests assert
  `CalendarEvent.debugOccursOnCalls == 0`, `identical` `AgendaListView.rows`
  across a show+hide, and `DaySummaryResolver.debugDefaultsBuilds == 0`.
- **`onFormatChanged` is nulled while collapsed** — table_calendar's own way
  to disable the vertical-swipe format gesture — so a swipe cannot rewrite the
  chosen format even when the user was already on week.
- **One animation, not two.** The page's own 250 ms `AnimatedSize` (which
  exists for `_panelExpanded`) goes unstable once the child resizes on
  consecutive layouts and from then on tracks it 1:1 — exactly one frame
  diverges. A test pins `<= 1` divergent frame, so a future change layering a
  second real tween fails loudly. Which animator *is* the one changed on
  2026-08-25; see below.
- **Agenda cards no longer clip their date range.** `_AgendaCard` wrapped its
  `ListTile` in `IntrinsicHeight` so the 4px category stripe could stretch.
  `_RenderListTile.computeMinIntrinsicHeight` measures title/subtitle at the
  **full** tile width, ignoring the leading `CircleAvatar` and the trailing
  icon strip, so the tile got a tight height that `performLayout` — which lays
  text out at `tileWidth - titleStart - adjustedTrailingWidth` — then
  exceeded; `size = constraints.constrain(tileSize)` clamped it back and
  `Card`'s `Clip.antiAlias` sliced the wrapped second line in half. The stripe
  is now a `Positioned(left: 0, top: 0, bottom: 0, width: 4)` strip in a
  `Stack` behind the tile, which stretches without constraining it.
- **Summary subtitles put the date range on its own line.** `secondaryLine`
  renders the range as a separate ellipsized `Text` instead of joining it into
  the `' · '` string, with
  `isThreeLine: description != null || range != null`. Both lines carry
  `maxLines: 1` + `TextOverflow.ellipsis` as a safety net. Tests must assert
  the pieces (`'2 holidays'`, `'Aug 15 – Nov 1'`), never the old joined
  string.
- **Which test protects which half.** The two range-line tests in
  `test/widgets/agenda_summary_card_layout_test.dart` pass *even with the
  `IntrinsicHeight` put back*, because both subtitle lines are `maxLines: 1`
  and so can no longer wrap — Part B alone hides the symptom for summary
  cards. Only a **wrapping description** (`MarkdownInlineText`, `maxLines: 2`)
  still grows the tile and re-triggers the clip, which is what
  `'a wrapping description grows the card instead of clipping'` covers. It was
  verified by reintroducing the bug and watching exactly that test go red. If
  the stripe/`Stack` structure is ever refactored, that is the test to trust.

## Addendum (2026-08-25): keyboard-coupled grid motion

The collapse above worked but read as robotic, for two structural reasons:
`table_calendar`'s inner `AnimatedSize` ran it on `Curves.linear` (the package
default the page never overrode), and the `> 0` inset threshold meant the grid
could not begin expanding until the keyboard had **finished** leaving — about
250 ms of keyboard followed by 200 ms of grid, one after the other. The fix is
not a curve override: the page now owns the animation and drives it from the
keyboard's own per-frame inset.

- **`KeyboardInsetTracker`** (`lib/utils/keyboard_inset_tracker.dart`) is a
  pure state machine fed one inset per frame. It emits a `collapsed` flag and
  a `progress` fraction, and owns direction, peak tracking, peak learning and
  jump detection. It has its own unit suite; nothing about it needs a widget.
- **The collapse flag is asymmetric, and that is the whole point.** It flips
  true on the first *rising* frame and false on the first *falling* one, so
  the grid starts giving space back while the keyboard is still on screen.
  Waiting for zero is what serialized the two animations.
- **`KeyboardCoupledSize`** (`lib/widgets/keyboard_coupled_size.dart`) is a
  `RenderShiftedBox` modelled on Flutter's `RenderAnimatedSize`. It animates a
  **gap** added to the child's natural height rather than tweening between two
  sizes.
- **The child is never given a bounded height.** This is the constraint that
  shapes the whole design: `table_calendar` divides a bounded height across
  its rows (`calendar_core.dart`'s `constrainedRowHeight`), so wrapping it in
  a `SizedBox` whose height shrinks squashes all six weeks into an accordion
  instead of showing fewer of them. The box sizes and clips itself; the child
  lays out at whatever height it wants.
- **Continuity is measured, not computed.** When the child's height changes
  between layouts the gap is seeded to `oldChildHeight + oldGap -
  newChildHeight`, so the painted height is unchanged across the frame the
  format flipped, and then relaxes to zero. Because it reads the child rather
  than reimplementing the package's row-count formula, the same mechanism
  covers month↔week, the filter sheet's format toggle, the vertical-swipe
  gesture, and 4/5/6-row month swipes — which previously tweened on the
  package's 200 ms linear curve and now use the house one.
- **Coupled progress is `inset / peak`.** The hide path divides by the peak
  this cycle actually observed. The show path has no peak of its own yet, so
  it borrows the one **learned from the previous completed cycle this app
  run** (not persisted — a settings key for this would be over-engineering).
- **Three fallbacks to a timed 250 ms `easeOutCubic` tween**, because coupling
  is only honest when there is motion to couple to: the first keyboard of an
  app run (no learned peak), an inset that arrives or vanishes in a single
  frame (Android < 30 does not animate it), and a coupled transition that has
  been idle for 150 ms — an IME panel swap, a resume with the stuck inset
  `main.dart` unfocuses against, or a learned peak that overshoots the real
  one and would otherwise strand the grid part-collapsed.
- **`formatAnimationDuration` is 1 ms, never `Duration.zero`.** Zero looks
  like the obvious way to silence the package's animator, but a zero-duration
  `AnimationController` publishes its end value *synchronously* from inside
  `RenderAnimatedSize.performLayout`, which then re-dirties itself mid-layout
  and throws. 1 ms completes on the next frame with no such edge. The cost is
  that the child's resize lands one frame after the format flip, which the
  gap absorbs.
- **Reduce motion snaps.** `MediaQuery.disableAnimationsOf` zeroes the gap on
  any child resize. Note the page's outer `AnimatedSize` is Flutter's own and
  does **not** honour that setting, so the reduce-motion test asserts on
  `KeyboardCoupledSize` rather than on the outer box.
- **Tests.** `test/utils/keyboard_inset_tracker_test.dart` covers the state
  machine; the widget suite gained a `rampKeyboard` helper (the old helpers
  step the inset 0→320 in one frame, which is now precisely the API < 30
  fallback and stays tested as such) plus coupled show/hide, both fallbacks
  and reduce motion. The headline hide test asserts the grid grows while the
  inset is still non-zero and lands **exactly** on the month height by the end
  of a 160 ms ramp — inside the 250 ms fallback, so arriving exactly is what
  proves the motion was inset-driven. Both coupled tests were watched go red
  against the restored `> 0` threshold before being kept.

## Addendum (2026-08-25): sheets and the system navigation bar

`showModalBottomSheet(useSafeArea: true)` reads like it protects both edges. It
does not — the route wraps the sheet in `SafeArea(bottom: false)`, so the top
is guarded and the bottom deliberately is not. A sheet is anchored to the
bottom edge of the screen, so its content runs underneath the gesture pill or
the three-button bar, and the last row of a scrollable is what vanishes.

Five sheets already worked around this individually. An audit found **six more
that did not**: `EventDetailSheet` (reported: the description and occurrence
chips), `AgendaDayListSheet`, `CalendarDatePickerSheet`, `FastingScheduleSheet`,
`FastingStyleSheet` and `RemovedHolidaysSheet` — each carrying a `const`
bottom padding of 16–24 px, which is less than a nav bar and, being `const`,
structurally incapable of responding to one.

- **The rule, now uniform:** pad by
  `max(viewInsets.bottom, viewPadding.bottom)` — the keyboard inset or the
  system inset, whichever is larger. `viewPadding` rather than `padding`
  because the latter is already net of the keyboard, and the two cases are
  mutually exclusive in practice.
- **Where it goes:** onto the **scrollable's** bottom padding, so content still
  scrolls the full height of the sheet and simply gains room to clear the bar.
  Wrap the **whole sheet** in a `Padding` only when a fixed footer sits below
  the scroll view, where the footer itself is what must clear the bar —
  `CalendarFilterSheet` (Cancel/Apply) and `CalendarDatePickerSheet` (the
  multi-select count and Clear button).
- **`MonthYearPickerSheet` is the exception and is already correct**: a real
  `SafeArea` inside the sheet plus a route-level `viewInsets` padding for typed
  mode. Equivalent result, so it was left alone.
- **Test:** `test/widgets/sheet_bottom_clearance_test.dart` asserts the resolved
  padding responds to a faked 48 px nav bar, and that it stays at the designed
  value with no nav bar (the clearance is additive, not a floor). Verified by
  restoring the `const` padding and watching it go red.

Not covered here, and still unpadded: `MoneyDetailSheet`, `MoveHistorySheet`,
`NoteMatchListSheet` and `BarSwitcherSheet` — outside the calendar, so outside
this pass.

## Addendum (2026-08-24): the event search grammar

Supersedes the scope described under "Upcoming agenda (search across
events)" above: search was a **single folded needle** matched by substring
against event title and descriptions only. Category, dates and multi-word
queries did not work. The folding behaviour described there is unchanged —
it is still the note search's `normalizeForSearch`.

- **The grammar is its own pure module**,
  [lib/utils/event_search_query.dart](../lib/utils/event_search_query.dart).
  `EventSearchQuery.parse(raw, {localeName})` splits on whitespace, folds each
  token **once**, dedupes into `terms` (a repeated word is one constraint)
  capped at `maxTerms = 30` and addressed by an `int` bitmask, then groups them
  into `clauses` that each carry an optional `EventSearchDate`.
  `parse('')` returns the `const empty`: no allocation, `satisfied` trivially
  true, so an empty query costs exactly what it did before.
- **Match semantics.** An occurrence of event `E` on day `D` matches iff
  **every** clause is satisfied. A clause is satisfied when *either* all its
  text terms appear as substrings of `E.title`, `E`'s description resolved for
  `D`, or `E`'s localized category label — a term may be answered by a
  different field than its clause-mate — *or* the clause carries a date that
  matches `D`. So `aug 26` returns everything on Aug 26 **plus** anything whose
  text contains both "aug" and "26"; `gym aug 26` requires both clauses.
- **Dates never go through `DateTime.tryParse`** — its rollover is the same
  hazard [fasting_schedule.dart](../lib/models/fasting_schedule.dart) warns
  about. Month names come from `DateFormat.MMMM(locale).dateSymbols` (MONTHS,
  STANDALONE, SHORT and STANDALONESHORT), folded, punctuation-stripped, matched
  by unique ≥3-character prefix and cached per locale; day+month parses in both
  orders (`aug 26`, `26 aug`, German `26. august`); ISO `2026-08-26` is
  validated by a UTC round-trip. Bare numbers (`26`), bare years (`2026`),
  two-letter fragments and impossible dates (`2026-02-30`, `feb 30`, `aug 44`)
  all degrade to plain text rather than silently narrowing the window.
- **`EventAgenda` stays context-free.** It never takes `AppLocalizations`;
  the view resolves a `Map<String, String>` of category id → localized label
  and passes it in. A `Set` of *matched* ids — the obvious first design —
  cannot express **which** term a category answered, which is exactly what AND
  semantics needs, so the map is the right shape. Labels are folded once per
  scan, never per event or per occurrence.
- **The hot loop did not get slower.** Per-event state is one
  `_EventQueryMatch`: `base` (title | category), `template` folded **only** for
  the bits `base` left open — so a title hit still costs no description fold,
  the 4.1 invariant — plus `varies` and `always`. `matchesQuery` is one map
  lookup and an `always` short-circuit per (event, day), and a live
  per-occurrence override still **replaces** the template contribution,
  empty included. The 4.1 budget test
  (`test/utils/event_agenda_description_fold_test.dart`) passes with its
  **original** numbers; only its `scan()` helper changed, to wrap the raw
  string in `EventSearchQuery.parse`.
- **Parsed once per rescan.** `_syncQuery()` is a no-op while text and locale
  stand still, so all three recompute paths can call it. `_recompute()` moved
  from `initState` into `didChangeDependencies` behind
  `_refreshSearchCatalog()` (locale + `CalendarCategories.revision`), so mount
  still runs exactly one scan, a keyboard or theme dependency change rescans
  nothing, and a category renamed behind the panel's back is now picked up.
- **All three layers agree.** Holiday and fasting filtering run the *same*
  clause test against their own localized labels instead of the private
  `contains` calls they each used to carry.
- Date narrowing is a per-day post-check, like `collapseRecurring` — it costs
  **zero** extra `occursOn` calls, and there is a guard asserting that.
- `CalendarEvent.titleFold` was deliberately **not** re-purposed as a
  diacritic-folded field: it is lowercase-only *and* load-bearing as
  `compareWithinDay`'s sort key, so a second derived field would allocate for
  every event ever constructed to save one fold per event per already-debounced
  scan.

## Addendum (2026-08-25): agenda search — coverage, reach, language, typos

The grammar above was sound; what it was *pointed at* was not. Reported as
"searching `fast` works but `lent` and `orthodox` find nothing", the
investigation found four independent causes, only one of which is about string
matching:

1. **Coverage.** The scan folded `title | category label | description` and
   nothing else, while rows *display* recurrence patterns, times / "All day",
   priority words, regime names, "Public holiday", and summary cards titled
   "Holidays" / "Orthodox". The one field beyond title/description that *was*
   searchable — the category label — is never rendered on an event row, the
   exact inverse of what a user expects.
2. **Reach.** Search filtered the days already in the window and never looked
   past it. English `fastingGreatLent` **is** "Great Lent", so `lent` was never
   a string problem: Great Lent is in February and the default window is 30
   days. Search was a filter, not a finder.
3. **Language.** The same period is "Fastenzeit" / "Postul Paștelui". Typing
   `lent` under `ro` could never work against visible text alone.
4. **Typos.** `orthodx` matched nothing, with no recovery affordance.

Plus two outright defects: `_fastingMatches` folded
`titleOverride ?? periodName`, mirroring the display's `??` — so **renaming a
period made it unsearchable** — and `traditionNameOf` was folded nowhere
despite being the summary card's own title.

The governing principle now: **if a row displays a piece of text, typing that
text finds the row.**

- **The searchable-text seam.** `occurrencesInRange` takes an optional
  `String Function(CalendarEvent)? labelTextOf`, invoked **at most once per
  candidate event** and only when title+category have not already settled the
  query. Fold order is `base` → **labels** → `template`, so a recurrence-label
  hit costs no description fold. `EventAgenda.debugLabelFolds` mirrors
  `debugDescriptionFolds` for pinning that budget. `EventAgenda` stays
  `AppLocalizations`-free: the closure is built by the view, exactly as
  `categoryLabels` already was.
- **`AgendaSearchText.forEvent`** (`lib/services/`) composes precisely what
  `EventSummaryProvider._subtitleFor` renders — recurrence pattern (with the
  "· also before" suffix), time or "All day", priority word above the default.
- **`countLabel` is deliberately excluded.** "Week 3" / "26 years" is a
  function of `(event, day)`, so folding it would break the `always`
  short-circuit that both the description-fold and `occursOn` budgets depend
  on. This is the one place the principle is knowingly not met.
- **Auto-widen.** A non-empty query with no pinned custom range scans
  `EventAgenda.maxRangeDays` (366) instead of `filters.rangeDays`. This is what
  actually fixes `lent`. A pinned custom range still wins — that is an explicit
  instruction, and so is a calendar-year window — widening that one would push
  it *forward* off the year the user asked for, losing the months the search
  most needs. The header renders `_resolved`, so it reports the widened window
  honestly with no extra work, and the debounce budget test moves from
  `0`-then-`30` to `0`-then-`366`.
- **Annotation parity.** `_fastingMatches` folds the override **and** the
  period name (OR, never `??`), the regime, the tradition name, and the style
  description. `_recomputeHolidays` folds `dayBarPublicHoliday` and the
  `upcomingShowHolidays` card title once per scan, not per day.
- **Hidden localized keywords**, following the settings search's proven
  `swipeKeywords` pattern: `FastingCalendar.traditionKeywordsOf` and
  `searchKeywordsOf` (nullable — minor periods carry none) return
  comma-separated synonyms that are matched but never rendered, each locale
  carrying the *other* languages' terms. That is what makes `lent` find
  "Postul Paștelui".
- **"Did you mean" on zero results.** `FuzzyRank` (`lib/utils/fuzzy_rank.dart`)
  is the vocabulary bar's 4-tier scorer — prefix › word-start › substring ›
  ordered subsequence — extracted unchanged and now shared, with
  `VocabularyMatcher` delegating to it (its existing tests are the proof of
  behaviour preservation). On an empty result only, it ranks a catalogue of
  loaded titles, category labels, enabled traditions and their periods, and the
  window's holidays, offering the top three as chips that replace the query.
  Kept strictly separate from the filtering grammar, which stays exact
  substring: fuzziness suggests, it never decides what matches.

## Addendum (schema v34): day rail markers

The cell wash picks **exactly one** event per day, deliberately — averaging a
day's colours yields a hue that belongs to no event on it. That is fine for a
day with one presence-tracked commitment and useless for a day with three,
which is precisely the shape recurring commitments (gym, physio, language
class) take. The **day rail** is a second channel that is multi-source by
construction: a vertical rail on the left edge of the cell, one mark per
commitment, each mark carrying whether it was kept. Design record:
[day-rail-markers-roadmap.md](day-rail-markers-roadmap.md).

### Schema

`calendar_events.show_in_day_rail INTEGER` — **nullable, no default**, the
schema's first nullable bool. Migration `_migrateV33ToV34` is the usual
`PRAGMA table_info` guard + `ALTER TABLE`, with **no backfill**: NULL is a
meaningful value, not a missing one. `ImportExportService.archiveVersion`
stays **1** and the backup version stays **7** — the column is additive, and an
older archive imports as NULL, which is the pre-feature behaviour exactly.
`calendar_event_templates` deliberately did **not** get the column: a
template-created event defaults to NULL = auto, which is already right.

### Membership: one predicate, three states

`eventInDayRail` (`lib/services/day_rail_resolver.dart`) is **the** definition,
read by both the rail provider and the bar provider's exclusion:

```dart
event.rule is! OneTimeRecurrence && (event.showInDayRail ?? event.tracksPresence)
```

- `NULL` (default, and every pre-v34 row) — **auto**: presence-tracked
  recurring events are in, nothing else. No event changed behaviour.
- `true` — force in. The recurrence guard is part of the predicate, so a
  one-time event can never enter the rail whatever the column says.
- `false` — force out.

The editor's control is a three-way `SegmentedButton` (Auto / Always / Never)
inside the same `_ruleHasManyOccurrences` gate as the presence switch — the
predicate excludes one-time rules, so offering the choice there would be
offering a no-op. Auto persists as **NULL**, via `copyWith`'s
`clearShowInDayRail` flag; a plain `copyWith` cannot express "set this nullable
field back to null", and writing `false` instead would freeze today's auto
answer into an explicit one.

### The third provider chain

`DayRailProvider` / `DayRailResolver` mirror `DayBarProvider` /
`DayBarsResolver` and `CellTintProvider` / `CellTintResolver`, purity contract
included: `marksFor` runs for every visible cell on every rebuild, so static
facade probes only. One provider ships, `EventDayRailProvider`.

- **Model.** `DayRailMark` = `DayBar` plus `bool missed`, same field names, so
  the two provider suites share fixture builders. It shares the `event:<uuid>`
  keyspace on purpose — the mark that survives the cap is then the same event
  that wins the wash.
- **Ordering.** Events arrive pre-sorted by `EventAgenda.compareWithinDay`;
  the provider never re-sorts, and `resolve` is `DayBarsResolver.resolve`'s
  body with the type changed — `putIfAbsent` dedup, stable priority sort with
  the insertion-index tie-break.
- **The resolver does not cap.** `CalendarDayRail` caps, exactly as
  `CalendarDayBars` does, and additionally clamps the visible count against its
  measured height at paint time so a short row can never overflow.
- **Missed.** `CalendarMissedDisplay` is reused with no rail-specific setting.
  `hidden` is filtered at the **top** of the per-event loop, before any add, so
  a hidden miss never consumes a rail slot. `faded` dims by
  `CalendarColors.missedEventAlpha` and, in `dot` style, additionally draws the
  mark hollow. Missed state also rides the mark's `semanticLabel`
  (`calendarRailMarkMissedLabel`, "{title}, missed") — colour is never the only
  carrier.

### A rail event leaves the bottom strip — but only while the rail renders

`EventDayBarProvider` gains `final bool railActive` (default `false`) and skips
events for which `eventInDayRail` is true. Each channel then means one thing —
rail = recurring commitments and whether you kept them, bars = everything else
today — and it frees the `maxDayBars` slots tracked events used to burn, which
is the second face of the same complaint. `railActive` is threaded from
`DayBarsResolver.defaults` and comes from
`appearance.dayRailStyle != DayRailStyle.none`, so **turning the rail off never
silently drops events from the grid**.

### Geometry, and where it lives in the cell

**Reworked 2026-09-01 — the unified edge lane.** The rail shipped with two
parallel lanes in the cell's left gutter and went unused because that read as
clutter; `line` now lives *in* the tint edge stripe's lane and the stripe
becomes the lane's bottom band. The design record is the addendum at the end of
[day-rail-markers-roadmap.md](day-rail-markers-roadmap.md); this is the running
behaviour.

**`line` — the edge lane.** `CalendarDayCell.edgeLaneLeft` (1.5) /
`edgeLaneWidth` (3) / `edgeLaneInset` (5.5). Those are the tint stripe's own
numbers (`left: 0, top: 4, bottom: 4, width: 3` inside the tinted container's
1.5px margin) restated in **cell** coordinates, because the rail is positioned
by the outer `Stack`, which has no margin. The two must agree to the pixel or
the lane splits in half the moment a fasting day also carries marks.

**`dot` — the inset lane, unchanged.** `CalendarDayCell.railLeft` (5),
`top: 4`, width 5. A 5px circle (1px of it spent on the hollow missed outline)
cannot be drawn 3px wide, so that style cannot share the stripe's lane and the
cell goes on drawing the stripe itself.

Three consequences of the move, all `line`-only:

- **The chip stops shrinking.** The edge lane ends at 4.5 and a 34px chip's
  leftmost point is 8.71 at 360dp (5.86 at 320dp), so `chipDiameterFor` is
  `railStyle == dot ? railChipSize : chipSize`. The rail's default style no
  longer costs the day number 4px on every cell.
- **The lane gets the whole row.** The bottom marker strip insets 6px, so it
  never reaches the edge lane — `line` takes `rowHeight - edgeLaneInset * 2`
  (~51px) where the inset lane still owes the strip its clearance
  (`rowHeight - 8 - stripHeight`, ~38px). `CalendarDayCell.railLaneHeight` is
  the one definition of both, shared by the grid and the settings preview.
- **The fasting stripe becomes `CalendarDayRail.baseColor`**, taking an **equal
  half** of the lane (`baseShare` = 0.5, via `baseBandFor`) while the marks
  subdivide the other half. Equal because the two are one question each — "is
  this a fasting day" and "what is on it" — and neither is a sub-answer of the
  other; hierarchy is carried by **weight** instead, the band at
  `CalendarColors.cellEdgeAlpha` (0.55) against marks at full alpha. It is
  **not a slot**: capacity is computed against the marks' half, so a fasting day
  never shows one fewer commitment than the same day without a fast. With no
  marks at all it takes the whole lane and is pixel-identical to the stripe it
  replaces. Exactly one of the cell and the rail draws that colour — the cell's
  `Positioned` stripe survives only while `railStyle != line` — and it reaches
  the rail **unfaded**, so the lane's outside-month fade applies once.
- **`DayRailBasePosition { bottom, top }` picks which end it takes**
  (`CalendarAppearance.dayRailBasePosition`, key
  `calendar_day_rail_base_position`, default `bottom` — commitments lead,
  reading downward from the day number). The setting **moves the split, never
  resizes it**, and the marks keep their priority order within their own half at
  either end; reversing them with the band would make the rail's first mark
  denote a different event depending on a purely visual choice. With no band the
  marks take the whole lane, so the setting can never cost a day that has no
  fast. Its settings row is revealed on all three preconditions —
  `dayRailStyle == line`, `eventTint`, `tintConflict == both` — because that is
  exactly when a band exists to place.

The rail still cannot join the tint `Stack` (that one is built only when the day
is tinted, and the lane needs cell coordinates). `CalendarDayCell.build` wraps
whatever the cell turned out to be in an **outer** `Stack`, now when
`railStyle != none && (railMarks.isNotEmpty || laneBase != null)` — the second
clause matters: without it, switching the rail on would delete the fasting cue
from every day that carries no marks. An untinted day with no marks stays the
single bare `Align` it has always been.

`_rowHeight` is unchanged — the rail is vertical. Capacity depends on the lane
height, which the caller passes (no `LayoutBuilder`), and `CalendarDayRail`
clamps the visible count against it: at the 44px usable height of a 52px
minimum row, `dot` fits five.

### Styles, cap, overflow

`DayRailStyle { none, line, dot }`, default **`none`** — opt-in like
`eventTint`, `highlightWeekends` and `showWeekNumbers`; no first-run nudge, no
conditional default. `line` is **one unbroken bar**: colour bands butted against
each other with no gap, dividing the lane height, and only the lane's two outer
ends rounded (1.5px radius, carried on the first and last band rather than by a
`ClipRRect`, which would cost a clip layer on a 42-cell path). A low-contrast
band outlines **the whole lane** through one `Container(foregroundDecoration:)`,
because a per-band border would draw a horizontal hairline at every boundary —
the separated look the single bar exists to avoid. `dot` is stacked 5px circles
with 3px gaps, centred, unchanged.

`calendar_max_day_rail_marks` is its **own** setting (1–5, default 3), not a
share of `maxDayBars` (1–6): different geometry, different capacity, different
content. It is clamped in the setter *and* the decoder. Overflow renders
`n - 1` marks plus a neutral `onSurfaceVariant` last mark — for `line`, a full
band at `cellEdgeAlpha`: it lost the half-height cue when the bands closed up,
and stepping it back to the base band's weight gives the lane exactly two levels
of emphasis (marks at full alpha, everything that is context behind them at
0.55). For `dot`, a smaller hollow dot. The exact `+N` goes into
the **semantics label only**; there is no room beside a 3px rail to draw a
number, which makes that label the only place the count exists at all.

### Accessibility

One merged `Semantics(container: true)` over `ExcludeSemantics(child: strip)`,
never a node per mark — mirroring `CalendarDayBars`. A day therefore announces
at most two marker nodes (rail, bars), each meaningful; the problem that
motivated the merge was per-sliver *unlabelled* nodes, not labelled merged
ones. The two cannot share one node: the strip is built in table_calendar's
`markerBuilder` and the cell in `cellBuilder`, separate subtrees.

### Perf

A third per-day output memo, `_railOutputCache`, beside `_barsOutputCache` and
`_tintOutputCache`, cleared by the same `_outputGeneration` record — which
gains a `railResolver` identity field. The rail renders inside the cell, so it
resolves in `_buildDayCell` beside the tint lookup, not in `markerBuilder`
where the bars do. With the rail off the resolver is not called at all.

Rail **style** and **max** are paint-side widget parameters, deliberately not
resolver inputs, so changing either repaints without dropping the mark caches.
`_resolverFor`'s memo key gained `railActive`, because the bar exclusion above
changes how that resolver is constructed.

### Shared contrast helper

`MarkerContrast` (`lib/utils/marker_contrast.dart`) now owns the 1.6:1 ratio,
the bounded luminance memo and `outlineFor`, extracted from `CalendarDayBars`
and consumed by both marker surfaces. It was retuned once already (2026-08-23,
ratio not delta); a second copy would silently keep the version that was wrong.

### Settings surface

Calendar settings → Appearance, with the marker options rather than the tint
options: a `SegmentedButton` for the style; revealed when the style is not
`none`, the capacity slider; and revealed on all three of `line` + `eventTint` +
`tintConflict == both`, the `DayRailBasePosition` `SegmentedButton`.
`_AppearancePreview` composes its sample cells by hand, so it was extended
manually — the "overflowing" sample carries one mark over the cap and a missed
one, because faded-and-hollow is the part that cannot be pictured from the
setting's copy, and the two tinted samples carry rail marks, so under those same
three conditions the preview is already showing the split the position row
moves.

### Known gap (pre-existing, not introduced here)

`BackupService._exportSettings` is a hardcoded allowlist with **zero**
`calendar_*` entries, so no calendar appearance setting round-trips through a
JSON backup today — the rail's two keys included. Matching the existing
behaviour is correct for this feature; closing the gap is its own change.

## Addendum (2026-08-31): editing event descriptions

The editor sheet's description was a `ModernEditorWrapper` bounded to
120–260 px **inside** the form's own `SingleChildScrollView` — two nested
scrollers fighting one drag, which is what made writing there feel bad. Not
a markdown-capability gap: the description already rendered through the same
`MarkdownEditorSpanBuilder` the note editor uses, at full syntax parity. The
fix is a dedicated full-height sheet that gives the editor the only
scrollable on screen, reached from two places that previously had none or
only the full form.

### `EventDescriptionSheet` — pure text-in/text-out

[`lib/widgets/event_description_sheet.dart`](../lib/widgets/event_description_sheet.dart),
`FractionallySizedBox(heightFactor: 0.92)`:

```dart
static Future<String?> show(
  BuildContext context, {
  required String initialText,
  required String heading,
  required int limit,
  required int grandfatheredLength,
  String? scopeCaption,
  MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
})
```

Returns the edited text, `null` when cancelled. It never touches a service,
never persists, and knows nothing about scope, occurrences or events — the
caller resolves which text it is and dispatches the result. Header:
`[✕] <event title over "Description"> [Done]` — stacked, not a
`title · Description` breadcrumb, because a phone leaves ~180 dp between the
close icon and Done and a one-line breadcrumb ellipsises away the half that
names the sheet; stacked, the event title truncates and the label never does,
and the pair still fits inside the row's existing button height. Below it a
**height-reserved status band** carries the optional scope caption on the left
and the live `eventDescriptionCount` on the right (red + w600 over budget);
over budget `eventDescriptionTooLong` takes the caption's slot rather than
adding a row. The band reserves two `bodySmall` lines, scaled with the user's
text size, so that swap never resizes the editor — a status line that reflows
the text under the caret at exactly the moment the user is fighting the limit
is the worst time to move it. The editor fills the rest of the height with
**no border** (see below); the markdown bar docks at the bottom.

- **The bar is permanently docked, not focus-gated** — the editor sheet
  gates its inline bar on focus so the form never shifts, but here the
  description is the entire content, so a stable bar beats a vanishing one.
  It is the same reduced bar as the editor sheet's: `splitEnabled: false`, no
  settings/reorder, undo+redo+paste, counter-bound shortcuts filtered
  (`s.effectiveCounters.isEmpty`), shortcuts through
  `MarkdownShortcutInserter` + `ShortcutApplier` inside `runRevocableOp` with
  a post-frame `makeCursorVisible()`.
- **Because the bar is a fixed footer, the clearance wraps the whole sheet.**
  `max(viewInsets.bottom, viewPadding.bottom)` pads the sheet itself rather
  than a scrollable — the `CalendarFilterSheet` variant of the rule §6.6 and
  the hard rules describe, not the scrollable-padding one every other
  calendar sheet uses.
- **The editor carries no border, deliberately.** A bounded 120–260 px field
  inside a form earns an outline; a full-height writing surface does not — it
  reads as a form field, nests a box inside the sheet's own box, and spends
  horizontal room on a sheet whose entire purpose is room. The note editor,
  this app's other full-height editor, has no border either. The editor's own
  `AppSpacing.lg` text padding does the insetting; the 4 dp outer pad exists
  only to line that 16 dp up with the sheet's 20 dp gutter.
- **Traps carried over from the editor sheet's inline field, all
  load-bearing**:
  `ListAwarePasteController(delegate: CodeLineEditingController(spanBuilder:))`;
  `clearHistory()` after the seeding write; a `ValueNotifier<int>` relay
  (`_revision`) with post-frame deferral instead of any `ListenableBuilder`
  on the controller directly — the bar's undo/redo enablement rides that
  relay too, not just the counter and Done; a late-resolving setting applied
  with `forceRepaint()`, never a remount.
- **Money is disabled by omission, and that is worth stating as a rule of
  its own**: there is no money parameter on `ModernEditorWrapper` or on the
  span builder constructor here. The builder defaults to
  `MoneyDisplayConfig.disabled` and stays there only as long as nobody calls
  `configureMoney` on it. Copying the note editor's money wiring into a
  description surface is exactly how that invariant gets broken.
- **The palette arrives already resolved** — the page holds a current copy —
  and is applied with `configureColors` in `initState`; unlike the editor
  sheet there is no late colour swap to repaint for, only
  `liveMarkdownRendering` resolves async.
- **It focuses the editor itself in a post-frame callback.**
  `ModernEditorWrapper` hardcodes `CodeEditor(autofocus: false)` with no
  parameter to change it, and a `CodeEditor` is not an `EditableText`, so
  nothing focuses it automatically.
- **Deliberately no placeholder text.** `eventDescriptionHint` was never
  wired to anything — it is an unused ARB key — and there is no hint
  mechanism on a `CodeEditor`; rendering one needs a hand-aligned overlay,
  and a misaligned placeholder is worse than none.

### Entry point A — the detail sheet's quick edit

[`lib/widgets/event_detail_sheet.dart`](../lib/widgets/event_detail_sheet.dart):

- `EventDetailAction` gains `editDescription` (now `edit`, `editDescription`,
  `openNote`, `skipOccurrence`). It carries **no payload** on purpose: the
  page re-resolves which text is being edited using exactly the rule a
  checkbox tick uses, so a quick edit and a tick can never write to
  different places.
- The affordance is a pencil `IconButton` on the **description card's own
  header row**, not the sheet header (which stays
  `close | centred title | Edit`) — a fourth control up there would say
  nothing about which field it opens. It keeps a full 48 dp tap target with a
  20 dp glyph rather than going `visualDensity: compact`: this app is used
  one-handed mid-session, so the *icon* carries the light weight, not the
  target. The gaps around that label row are trimmed (16→8 above, 4→0 below)
  to give back what the button's own padding already contributes — otherwise
  "Description" sits in a visibly looser band than "Next occurrences", which
  is the same kind of label.
- The empty state changed: the old inert `eventDetailsNoDescription` text
  ("No notes for this event") is replaced by a **tappable row** reading
  `eventDescriptionAdd` ("Add description") that fires the same action, filled
  with the same tonal wash the populated description card uses so it reads as
  that card waiting to be filled rather than as a disabled input — which is
  what a bare outline on a full-width row looks like. (A dashed border would
  say it better still; Flutter has none and the app has no painter for one.)
  `eventDetailsNoDescription` is now an unused ARB key, left in place.
- A new caption, `eventDescriptionTickAllOccurrences`, renders under the
  description when the task boxes are inert (repeating event, per-occurrence
  descriptions off, §6.6) **and** the description actually contains a task
  box — with editing gone from this sheet the dead boxes were otherwise the
  only unresponsive thing on it; it doubles as discovery for the v28 switch.
  The task-box test goes through
  `MarkdownListSyntax.parse(line)?.kind == MarkdownListKind.task` — the
  shared grammar, never a second regex — and only runs in the inert case.
- A new parameter, `pendingOccurrenceDescription` (`String?`), mirrors the
  editor sheet's: the page reopens this sheet in the same turn it dispatches
  an occurrence write, so reading the facade would still show pre-edit text.
  It beats `OccurrenceDescriptions.descriptionFor` when set, and the caller
  drops it once `OccurrenceDescriptions.appliesTo` goes false, so a dormant
  row can never render as if it were the template.

### Entry point B — expand from the editor sheet

[`lib/widgets/event_editor_sheet.dart`](../lib/widgets/event_editor_sheet.dart):

- The description header row gains an expand `IconButton`
  (`Icons.open_in_full_rounded`, `eventDescriptionExpand`), shown in preview
  mode too — expanding is itself an edit action and always opens the
  editing surface.
- Seeded from `_descriptionController.text` — **the active scope only**. The
  `_scope` control stays behind in the form and the sheet never sees it,
  which is what keeps the sheet pure and the two-buffer copy-on-write logic
  in exactly one place (§6.6). `grandfatheredLength` is the active scope's
  own (`_initialDayLength` / `_initialTemplateLength`); the caption reuses
  `eventDescriptionScopeThisDayHint` / `eventDescriptionScopeAllDaysHint`.
- On return: `text = result; clearHistory();` inside a `setState` — the
  active scope's buffer *is* the controller, so there is nothing to mirror;
  `clearHistory()` for the same reason a scope swap needs it (§6.6). Cancel
  changes nothing. **The expanded sheet does not save the event** — it edits
  the in-flight controller and the form still saves; nothing about
  `_resolveOccurrenceOutcome`'s copy-on-write contract changes.

### Navigation — back button and the reopen loop

- `EventEditorResult` gains a third sealed variant, `EventEditorBack`,
  alongside `EventEditorSaved` / `EventEditorDeleted`.
- `EventEditorSheet` gains `final bool showBack` (default `false`), set only
  on the detail-sheet path. **Back replaces close rather than joining it** —
  the header stays one leading icon (§6.3's `close | title | Save` shape is
  structurally unchanged; only the leading icon and its tooltip, `l10n.back`
  vs `l10n.cancel`, differ). Back and close **discard identically** — there
  is no dirty tracking in this sheet — so two adjacent buttons differing
  only in where you land is a distinction too fine for a second icon.
- A `PopScope` (net-new here) maps the Android system back gesture to the
  same `EventEditorBack`, only while `showBack` holds. Drag-dismiss bypasses
  `PopScope` entirely and still pops `null`, which closes the whole
  stack — the deliberate escape hatch out of the loop.
- `calendar_page.dart`'s `_openDetailSheet` is now a **loop**: `edit` and
  `editDescription` re-enter it; `openNote`, `skipOccurrence`, a delete, and
  dismissing the sheet all exit. `_openEditorSheet` now returns
  `Future<EventEditorResult?>` instead of `Future<void>` (it still dispatches
  everything itself; only the loop reads the value) and gained `showBack`;
  of its five callers, only the detail-sheet path passes `showBack: true`.
- Two static rules on the page are worth stating as invariants:
  - **`_pendingAfterSave`** decides what the day's text is for the reopened
    sheet. `null` once `OccurrenceDescriptions.appliesTo(saved)` goes false
    (the row went dormant, the template governs again); the previous
    pending when the editor left the table alone (`occurrenceDay == null`);
    otherwise `result.occurrenceDescription ?? saved.description ?? ''` —
    because a non-null day paired with a **null** description is a reset
    that *deleted* the row, so the day now follows the template, and
    carrying stale text there would show text the user just deleted.
  - **`_occurrenceSurvives`** decides whether `day` still has an occurrence
    after the save. The form can move the date, change the rule, pull in
    `endDate`, or cancel that very day from its own skip picker; reopening
    on any of those would describe an occurrence that is gone. It reads the
    skip set **from the result** (`result.skippedDays?.contains(day)`)
    rather than from `EventSkips`, because the skip dispatch is async and
    the facade may not carry it yet, then falls back to
    `saved.occursOn(day)`. `CalendarBloc.eventsForDay` is the wrong call
    here — it applies the hidden-category filter and would report a
    filtered-out event as gone.

### Quick-edit routing (`_quickEditDescription`)

- Seeded from the **raw** text —
  `pending ?? OccurrenceDescriptions.descriptionFor(...) ?? ''`, or
  `event.description ?? ''` — never the detail sheet's trimmed render, so an
  unedited Done can compare equal.
- **An unchanged Done writes nothing.** On a day with no row of its own it
  would otherwise materialise one identical to the template, forking that
  day forever; on the event it would bump `version` and the HLC for nothing.
- Per-occurrence goes through `SetOccurrenceDescription`; otherwise
  `UpdateCalendarEvent` with `clearDescription: edited.isEmpty` — the same
  two branches a checkbox tick uses.
- **Emptying a per-occurrence quick edit writes `''` — a deliberately
  blanked day — and is not a reset.** The row stays and keeps winning over
  the template; returning to the template is what the editor's "reset this
  day" (which tombstones, §6.6) is for. This is the one place the two
  operations are easy to confuse, so it is worth stating plainly here too.
- No scope picker, deliberately: a per-occurrence event edits *this day*
  here, and its template only in the full editor — which is what the
  caption under the field says out loud.
- The limit comes from `SettingsService.getEventDescriptionLimit()` read at
  tap time; the grandfathered length is the seed's own length, so the text
  is always confirmable at a length it already had (§6.6's grandfather
  rule, one level removed from the form). Cancel is never disabled.

### Localization

Six new keys, present in en/de/ro: `eventDescriptionEdit`,
`eventDescriptionAdd`, `eventDescriptionExpand`, `eventDescriptionDone`,
`eventDescriptionAppliesAllOccurrences`, `eventDescriptionTickAllOccurrences`.
Reused as-is: `eventDescription`, `eventDescriptionCount`,
`eventDescriptionTooLong`, `eventDescriptionScopeThisDayHint`,
`eventDescriptionScopeAllDaysHint`, `back`, `close`.

### Unchanged, and it has to stay that way

The detail sheet stays read-only apart from checkbox toggling — no editor is
mounted in it. Checkbox gating (§6.6) is untouched.
`OccurrenceDescriptions.descriptionFor` stays the one resolution entry
point. A present occurrence row always wins, including when empty, and
"reset this day" tombstones rather than writing `''`. Occurrence writes bump
`occurrenceRevision` and never invalidate the day cache.
`SimpleMarkdownPreview.onCheckboxTap` stays `null` on read-only surfaces.

## Addendum (2026-09-01): folding the calendar settings page

The page had grown to five cards and 22 rows, twelve of them in Appearance
alone, and there is no jumping between them — reaching Events means scrolling
past every appearance control. Two changes, one shared and one local.

### Sections fold, and remember it

[`lib/widgets/settings_section_list.dart`](../lib/widgets/settings_section_list.dart)
grew an optional fold. `SettingsSectionData` takes an `id`; `SettingsSectionList`
takes `collapsedSections` (a `Set<String>` the page owns) and
`onToggleSection`. A section folds only when it has an `id` **and** the list was
given a callback, so `controls_settings_page`, `developer_options_page` and
`sync_settings_page` render byte-identically — they pass neither.

Three invariants worth keeping:

- **A fold may never swallow a search hit.** While `query` is non-empty every
  surviving section renders open and drops its chevron. The stored fold is not
  touched, so it returns when the query is cleared. A row that matched but sat
  inside a shut card would make the search field lie.
- **A folded section builds nothing below its header** — not `Opacity`, not
  `Offstage`, not `AnimatedCrossFade` (which builds both children and would
  keep `_AppearancePreview` and every slider alive). The point is to stop
  paying for the rows, not just to hide them.
- **The `id` is persisted, so it is frozen.** Never derive it from the
  localized title or from the list index; renaming or reordering a section
  must not reopen a card the user shut.

Chrome: the header becomes an `InkWell` clipped to the card's top corners,
with `Semantics(button: true, expanded: …)`, a chevron on `AnimatedRotation`
(0 → 0.5 turns, 180 ms) and — **only while shut** — a muted
`settingsSectionCollapsedCount` ("4 options"), because a folded title alone
says nothing about how much is behind it. The body sits in an `AnimatedSize`
(180 ms, `easeOutCubic`, `alignment: topCenter`) so the cards below slide
rather than jump.

Persistence is `SettingsKeys.calendarSettingsCollapsedSections`
(`calendar_settings_collapsed_sections`, CSV of ids) through
`SettingsService.getCalendarSettingsCollapsedSections` /
`set…`. It is deliberately **not** in `_calendarPageKeys` or
`_calendarAppearanceKeys`: it changes nothing the calendar draws, and the
grid's pre-first-frame bulk read should not carry a settings-page view
preference. `_resetToDefaults` clears it — the page ships open, and leaving a
card shut after a reset hides rows the user just asked to see restored. Ids:
`calendar`, `categories`, `appearance`, `fasting`, `events`.

### Rows moved to the section they belong to

- **Section order** is now Calendar → **Categories** → Appearance → Fasting →
  Events. What the calendar *is* comes before how it *looks*; categories used
  to sit behind a dozen appearance rows, a long way down for the one row that
  opens a page of its own.
- **Event templates** moved from Categories to **Events**, first row. A
  template is a saved event, not a category — it only ever lived next to the
  categories row because both navigate. Its `addFromTemplate` keyword moved
  with it, so settings search is unchanged.
- **Missed events (faded / hidden)** moved from Events to **Appearance**,
  between the day-bar cap and the day-rail rows. It is a drawing rule for the
  markers above it and the rail below it — both resolvers read
  `EventPresence.isMissed` — not a property of an event, and it is read
  together with the two rows it now sits between.

Nothing else changed: no setting gained or lost a key, no default moved, and
every row keeps its title, description and keywords, so a saved search still
finds what it found before.

### Tests

[`test/widgets/settings_section_fold_test.dart`](../test/widgets/settings_section_fold_test.dart)
— nine cases over the shared widget: open/shut rendering including the intro,
the count only while shut, toggling reports the id, a fold never swallows a
search hit, no chevron while filtering, the fold returns when the query
clears, and both "cannot fold" paths (no callback, no `id`).
