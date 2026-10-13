# Calendar overview — the List mode rework (2026-10-11)

**Status: IMPLEMENTED 2026-10-12, uncommitted.** Slices 0–7 and the fix pass are in the tree (64 files): `dart analyze lib test tool test_driver` clean, the whole `flutter test` `+7524 ~8 -1` (7317 before the rework; the one failure the known Windows-only `host_devices_test` case), `untranslated.txt` `{}`, the benchmark green under `--tags benchmark --run-skipped`, `qa flows calendar` 23 / 24 with `23_overview_list` green end to end on the Pixel_9_Pro emulator (the one red, `19_fasting_schedule`, predates this rework), `qa errors` clean. D1–D11 were delegated to the lead by the owner on 2026-10-11 ("take any decisions using fable and implement using whatever you see fit"); the recommended option (A) stands for each. The owner reviews and commits; the next session that opens this record corrects this line from `git log`.
Written on a clean tree at `ae98d62` from a read of the overview page, the
store, the index, the rows, the Tier 3 day list and the scan, plus one
independent read-only review of the list mode's performance and behaviour
(Opus 5.5, 2026-10-11; its findings are §1.3). The mock is
**"Overview List Mock"** — https://claude.ai/artifact/GpAs4MTkY1Vc4gY9wyBhnq —
one board of the list (light at rest, dark while scrubbing), one of the
period picker, strips of the view menu, the options sheet and the "Per
event" rows, an audit of every component against the language, and the
decisions of §2 as the owner will answer them. Where the mock and this
record disagree, **this record wins**. Line numbers in §5 are from
`ae98d62`; re-grep every one before editing. This is also Tier 4's overview
item of `docs/calendar-language-adoption-roadmap.md` (its §3 "Tier 4 —
pages", item 3): the page's rows and its last `CategoryFilterTile` reader
move onto the language here, so that master's §9 table gets this record's
status line.

**Revision 2 (2026-10-11, same day).** The owner looked at the first mock and
found the list's period nav — a centered two-line "Mar 15 – Jun 20, 2026 /
212 entries · 7 missed" between two chip rows — out of place, and asked that
every component respect the UI rework's concepts. Revision 2 removes the
nav and both chip rows from list mode: the period is a `FormMenuRow` in the
filter group (the agenda filters' own Period row), the count is the group's
caption, the modes join the title's view menu as the calendar's formats do,
and the list options go one level down behind the bar's tune button. D5, D7
and D8 were re-asked and D11 added; nothing else changed.

Contents: §0 How to run this · §1 Why · §2 Decisions · §3 The spec · §4
Behaviour · §5 Facts from the tree · §6 Slices · §7 Definition of done · §8
Deferred · §9 Ledger.

## 0. How to run this

The implementing session runs on **Opus 5.5 at high**; it loads
`anta-context`, `ui-language`, `calendar-events`, `calendar-ui`, `ui-revamp`,
`verify`, `l10n`, `delegation` and, for slice 7, `qa-emulator`. It reads this
record **by section** — the slice's part of §3, §4.1 whole, the slice's lines
of §5 — never end to end. One `implementer` per slice (default effort;
`effort: medium` for slices 1 and 6, which the record fully specifies), one
`reviewer` after slice 7 briefed with §3, §4.1 and the diff, one `qa-runner`
for the device pass, `explorer` for any re-grep wider than a file.
`fable-max` only if the owner names it. Never two writers on one file; never
start a slice with anything red; do not commit — the owner reviews the tree
and commits, and the next session that opens this record corrects the status
line from `git log` first.

The gate after **every** slice (`verify`): `dart analyze lib test` clean
(`tool test_driver` added when the QA tool changed); the **whole**
`flutter test` green in one run — slice 0 records the baseline count in §9
before it adds anything; on Windows the known failure is
`test/qa/host_devices_test.dart` "MacosDevice locate reads the product name
from AppInfo.xcconfig" (note it, never touch it); a `sqlite3.dll` lock crash
is transient, rerun; `flutter gen-l10n` run and `untranslated.txt` equal to
`{}` whenever an ARB changed; §4.1 re-read against `git diff`. Never run
`flutter test` beside a QA `flutter run` (`qa kill-run` first).

This machine is Windows 11: the wrapper is `tool\qa\qa.cmd`, the emulator
`Pixel_9_Pro` (boot cold on "Lost connection to device"), there is no
`python`, and **file edits go through Read, Edit and Write only** — never
`perl -i` or `sed -i`, whatever a harness note says. Repo files are CRLF.

## 1. Why

### 1.1 The ask (owner, 2026-10-11)

"Revamp the List View Mode of the Overview Mode. Make the list a lot more
useful — a date picker that lets you select ranges, and more things that help
with a huge list view. Performance may be okay, but review it deeply, suggest
new things and improve on others. Use any models." Then, on the first mock:
the period nav looked out of place, and every component must respect the UI
rework's concepts. The overview's list is the page's log view: every
occurrence of the chosen categories, dated, and the owner's own use is a
training log that grows by a row or more a day for years.

### 1.2 What the list is today

`CalendarOverviewPage` (`lib/pages/calendar_overview_page.dart`, 1005 lines,
2026-09-26): a raw outlined `TextField` for the search · `CategoryFilterTile`
(an avatar cluster) · a `SegmentedButton` Year / Month / List · the body. In
list mode the body is the year nav (`AgendaPeriodNav`: ◄ `2026` with its
count · the Today slot · ►, the title opening `MonthYearPickerSheet`) over a
`ListView.builder` of `AgendaDayListRowView` rows — month separators as a
primary-coloured label with a divider, day headers as `titleSmall` text with
a count, entries as `ListTile` + `CircleAvatar`, a missed entry under
`Opacity`. The unit is a **calendar year**: `_recompute` asks the
`AgendaMonthStore` for the year's twelve months in one run and flattens them
with `buildAgendaDayListRows`. The year and the search are session-only; the
allowlist and the mode persist (decision F of 2026-09-26). A row tap calls
`AppNavigator.toCalendarOccurrence`. The day list sheet (Tier 3, 2026-10-03)
already renders the same row model in the language; the page's rows were
left for Tier 4.

What a long log runs into: no range (a year, or nothing), no way to see
"everything" or "the last twelve months", no fast travel inside a year of
rows, no pinned context while scrolling, the oldest day first always, one row
per occurrence always, and the chrome outside the language.

### 1.3 The independent review (2026-10-11, read-only, Opus 5.5)

Twenty-one findings; the ones that shape this record, with the fix's slice.
CONFIRMED means the reviewer quoted the code; the lead re-verified R1 and R2
in the tree.

| # | Sev. | Finding | Where | Slice |
| --- | --- | --- | --- | --- |
| R1 | HIGH, CONFIRMED | A row tap from the view-menu path **pops the overview**: `toCalendarOccurrence` finds the calendar beneath and `_collapseOnto` ends in `navigator.pop()`, which is the overview. The period, the search and the scroll position are gone; the parking in `didPushNext` / `didPopNext` only ever served the drawer path. | `app_navigator.dart:286–297, 453–475`; `calendar_overview_page.dart:132–137, 178–189, 613–625` | D1 → slice 3 |
| R2 | HIGH for any range over a year, CONFIRMED | A store run longer than twelve months is only guarded by asserts (`_spanOf`); `_forEachMissingRun` splits at gaps, never at twelve; `resolveRange` clamps to `maxRangeDays` silently and `_resolveRun` caches the months past it as **empty**, never resolved again. | `agenda_month_store.dart:106–157`; `event_agenda.dart:241, 985–986` | slice 1 |
| R3 | MEDIUM, PLAUSIBLE | The mode cross-fade's outgoing `ListView` reads the field `_rows` at build time with a frozen `itemCount`; a fling during the 150 ms fade indexes past a shorter list (`RangeError`). | `calendar_overview_page.dart:673–679, 837–841, 897–904` | slice 3 |
| R4 | MEDIUM, CONFIRMED | The list's scroll offset is kept as pixels across year changes, searches and returns — a chevron from deep in one year lands mid-way through the next; nothing anchors to a row. | `:837–841, 459–468, 576–580` | slice 3 |
| R5 | MEDIUM, CONFIRMED | `_listenWhen` ignores `occurrenceRevision`, but a query's per-day match reads the occurrence descriptions; search results go stale after a day's text is edited. | `:253–259`; `event_agenda.dart` per-day match | slice 3 |
| R6 | MEDIUM, CONFIRMED | Search covers the shown year only; the chevrons walk every year of the bounds (1900–2100 under a retroactive open-ended series) one full scan each, and the empty state claims "Nothing in {year}" while other years match. | `:292–298, 829` | the period (slices 1, 3) |
| R7 | MEDIUM perf, CONFIRMED | `_schedulePrewarm` runs two full-year marks scans after every settle in list mode, where the next chevron runs `ensure` anyway and the tally comes free from the bucket. | `:420–430` | slice 3 |
| R8 | MEDIUM perf, CONFIRMED | Every keystroke pause drops every cache (`_tilesByYear`, the store), recomputes the query-independent `yearBoundsOf`, and `EventSearchQuery` has no `==`, so a trailing space rescans. | `:282–312, 576–580` | slices 1, 3 |
| R9 | MEDIUM, CONFIRMED absence | Row heights are unbounded (no `maxLines` on title, subtitle or day header) and the list has no extents, no scrollbar, no `jumpTo` target: scrollbar drift, a far jump laying out every row in between, no fast scroll on Android. | `agenda_day_list_rows.dart:168–194`; the page's list | slice 3 (§3.8) |
| R10 | LOW-MEDIUM, CONFIRMED | In list mode the jump picker ignores the picked month: `_goToYear` returns when the year is unchanged. | `:489–522, 470–487` | slice 3 (the nav leaves list mode; the picker is the period's) |
| R11 | LOW perf, CONFIRMED | Bars are folded for every resolved month in list mode and read only by month mode. | `agenda_month_store.dart:155, 193–213` | §8 |
| R12 | LOW perf, CONFIRMED | Per occurrence: `entryFor` resolves a description the entry drops, the subtitle is formatted eagerly, the scan copies its result, four objects per row. | `agenda_list_view.dart:692–726` | §8 |
| R13 | LOW, CONFIRMED | The store never evicts; every year paged keeps its buckets until the next rebuild. | `agenda_month_store.dart` | §8 (bounded by the period and the cap) |
| R14 | LOW, CONFIRMED | `missing.contains(key)` is quadratic in the months of a run. | `:113` | slice 1 |
| R15 | LOW, CONFIRMED | A return or a settings trip causes two full rebuilds (`didPopNext` adopts, then `_reloadAppearance` rebuilds again). | `:182–216` | slice 3 (coalesced) |
| R16 | LOW, CONFIRMED | Month headers vanish when a year's rows fall in one month (`multiMonth`), and the year is all-or-nothing per list. | `agenda_day_list_rows.dart:57–61` | slice 3 (always a month header in list mode) |
| R17 | LOW, CONFIRMED | `_today` is frozen at open: Today / Tomorrow headers, the this-year slot and the bounds go stale after midnight. | `:92, 142` | slice 3 |
| R18 | LOW, CONFIRMED absence | No `keyboardDismissBehavior`: the keyboard stays up over a 190 dp viewport at 360 × 780. | the page's list | slice 3 |
| R19 | LOW, CONFIRMED | Covering the page cancels neither the prewarm nor the search debounce. | `:179` | slice 3 |
| R20 | LOW, PLAUSIBLE | A sub-150 ms Year → List → Year switch attaches `_yearPager` to two `PageView`s. | `:314–321` | slice 3 (pin with a test) |
| R21 | LOW | No ids on the rows; semantic indexes count headers; the flow targets a title. | `05_overview.txt:13` | slice 3, slice 7 |

The review's cost model, one calendar year, "scan" = one `occurrencesInRange`
over twelve months: first open in list mode 1 entries scan + 2 wasted marks
scans; a keystroke pause the same, with every cache dropped; a chevron 1
entries scan + 1–2 marks; a return on the drawer path 1 + 2, doubled when the
appearance changed; Year → List → Year 1 marks (+ 2) → 1 entries → 0. A range
of 2019-03-15 → 2026-10-11 is 92 months: at least eight resolver calls once
runs are chunked, each re-running the O(N) pre-filter over every event, every
row built eagerly inside one `setState`; the whole bounds under a retroactive
open-ended series is 201 calls and a daily series alone is about 73 000
entries. Hence §3.8: resolve the first months synchronously and the rest
between frames, keep the query out of the scan, bound the rows.

## 2. Decisions

### 2.1 Asked of the owner on 2026-10-11 — answered the same day: delegated to the lead, the recommended option (A) stands for D1–D11

Recommended option first. A terse "A" per line is enough; "take it from me"
means the recommended option stands and the record says it was delegated.
D5, D7 and D8 were revised and D11 added in revision 2, after the owner's
feedback on the first mock.

| D | Question | Options |
| --- | --- | --- |
| D1 | What a row tap does (R1) | **A** push a calendar over the overview, back returns to the list where it was · B open the detail sheet over the list with the calendar's detail loop extracted into a shared controller (best in use; a rework of its own — §8) · C keep the collapse and remember the session for the next open |
| D2 | The Period menu's items | **A** This year · Last 12 months · Last 90 days · All time · Custom range… · B A plus Last 30 days and Year to date · C This year and Custom range… only |
| D3 | "All time" | **A** the first year an event starts in → today (the list is the log; the future is the agenda's) · B → the last year an event can fire in (projects an open-ended series to 2100, lands on the cap) |
| D4 | What persists | **A** a preset (This year, Last 12 months, Last 90 days, All time) persists; a custom span is session-only · B nothing new persists · C everything, custom spans included |
| D5 | Where the list options live (revised: two chip rows on a page were no shape the language has) | **A** the bar's tune button opens a live-apply sheet — Order, Rows, Missed only — advanced controls one level down, the agenda's pattern · B rows in the ⋮ |
| D6 | Fast travel | **A** a month scrubber (the draggable thumb with a month bubble), last slice, cuttable · B the interactive scrollbar alone · C neither |
| D7 | Where the list lands (revised: list mode has no Today slot any more) | **A** on today's day whenever today is inside the period, else at the top; Newest first lands at the top · B always at the top |
| D8 | The mode switch (revised) | **A** Year · Month · List as the view menu's second group, the calendar's own pattern; the page loses a band, a switch costs two taps · B a chip row under the filter group, the day list sheet's pattern, one tap |
| D9 | The agenda's "Custom range…" (Flutter's Material dialog today) | **A** moved onto the picker's range mode in slice 2 · B later |
| D10 | A "Per event" row's tap | **A** opens the calendar on the event's last day in the period · B puts the title in the search |
| D11 | The period control (new: the first mock's centered two-line nav between two chip rows was out of place) | **A** a Period menu row in the filter group and no nav in list mode; the count is the group's caption; a span is set in the picker · B keep a nav with chevrons that step the period, under the filter group |

### 2.2 Taken by the lead (technical; the owner may overrule)

| T | Decision | Why |
| --- | --- | --- |
| T1 | **Idiom: the day list's rows**, hoisted from `AgendaDayListSheet` into one shared builder both surfaces render (§3.3). | The calendar set the dated-entry grammar in Tier 3 (read row per day over entry rows, months as section labels); the page's `AgendaDayListRowView` was left for Tier 4 by name. One piece of code for the sheet and the page is the 2026-09-26 principle for the store already. |
| T2 | **A period, not a year**, is the list's unit: `OverviewPeriod` (§3.4). Year and Month modes keep their year and month. | The ask. |
| T3 | **The query is a post-filter** over resolved entries, never an input of the scan, on every mode of the page (§3.8). | R8: typing re-expanded every recurrence of the year; a post-filter over cached entries costs one match per entry through the same fold caches. The allowlist stays a scan-time filter (it narrows the expansion and changes rarely). |
| T4 | **Fixed row extents** per row kind measured once per text scale and locale, `itemExtentBuilder`, exact `jumpTo`, an accurate scrollbar, and a **pinned month label derived from the offset** rather than per-month slivers (§3.8). | R9; the scrubber, the landing on today and the anchoring all need offsets that are exact without laying out the rows in between. |
| T5 | **Batched resolution** past two years with a visible tail caption, and a hard **entry cap** (§3.8). | The review's extrapolation: a long period must never block a frame or take the memory of 73 000 rows. |
| T6 | `AgendaMonthStore` **chunks every run at twelve months** (R2) and keeps its contract otherwise. | A multi-year `ensure` must be correct in release builds, not only asserted in debug. |
| T7 | The range picker is a **third mode of `CalendarDatePickerSheet`** (`pickRange`), not a new sheet, and carries **no preset chips** — the presets are the Period row's menu (§3.5). | "Dates go through `CalendarDatePickerSheet`"; the grid, the nav, the year tiles and the chrome exist; one home for the presets. |
| T8 | The entry row's caption is **one line** in the list (`captionMaxLines: 1`), the node carrying the whole text. | T4: one geometry per row kind. The day list keeps its two-line clamp. |
| T9 | The pushed calendar (D1 · A) is **stamped as the plain calendar destination**, as the alert tap's root push is, and `toCalendarOccurrence` collapses only when the overview is not above the calendar. | Launch restore must not replay a calendar over the overview; `_livePageRoutes` and the restore seal decide what a stamp means — the implementer verifies in slice 3. |
| T10 | In range mode the Dates sheet's **year view picks whole months**: a tile tap sets the span to that month, a second tile extends it to that month's end; the month view refines days. | With the nav gone from list mode, a past year must still be two taps away (January, December); the tile is a 60 dp target, and travel to a month is the Month view's job. |
| T11 | The options sheet's badge counts **restrictions only** (Missed only), as the agenda's and the calendar's filter buttons do. | Order and Rows re-present the same entries; a badge means "something is hidden". |

## 3. The spec

### 3.1 Geometry and tokens

Everything reads `FormMetrics`, `RowMetrics`, `AppBarMetrics` and
`SurfaceRoles` by name. The ground is `pageGround`, groups `rowGroup`,
hairlines `rowDivider`, the scrubber's bubble and the menus `menuSurface`.
New numbers, named first:

- `lib/constants/overview_list_metrics.dart`, `OverviewListMetrics`:
  `syncMonths = 24` (months resolved before the first frame), `batchMonths =
  12` (one store run per event-loop turn after that), `maxEntries = 20000`
  (the cap; §3.8), `searchDebounce = Duration(milliseconds: 200)` (moved from
  the page's private constant), `modeSwitchDuration`, `pageDuration`,
  `prewarmDelay` (the page's other three privates, moved).
- `FormMetrics`: `scrubberLaneWidth = 48` (the touch lane along the list's
  right edge), `scrubberThumbWidth = 4`, `scrubberBubbleInset = 12`,
  `scrubberBubbleRadius = FormMetrics.menuRadius`, `scrubberBubblePadding =
  EdgeInsets.symmetric(horizontal: 12, vertical: 8)` — the scrubber is a
  shared primitive (§3.7).

### 3.2 The page in list mode, top to bottom

1. **App bar** (`AppBarMetrics`): the title is `CalendarViewMenu` with a
   **second group for the overview's presentations** (D8 · A) — after the
   pages and a `PopupMenuDivider(AppTheme.menuDividerHeight)`, three
   `FormMenuChoiceItem`s Year · Month · List (`FormMenuItemRow(icon:
   grid_view_rounded / calendar_view_month_rounded /
   format_list_bulleted_rounded, label: dayListModeYear / -Month / -List,
   checked: mode == x, identifier: overview-view-year / -month / -list)`),
   exactly as the calendar's formats sit there. `CalendarViewMenu` takes
   `presentation: AgendaDayListMode?` and `onPresentationSelected`; null
   leaves the group out (the calendar passes nothing, the overview passes
   nothing in no state). The title keeps reading "Overview". Actions: the
   **tune button** — `Badge.count(count: restrictions, isLabelVisible:
   restrictions > 0)` over `AutomationId(overview-options-open)` over
   `IconButton(tooltip: overviewListOptions, isSelected: restrictions > 0,
   icon: tune_rounded)` (the calendar bar's filter button and the agenda's
   tune, `calendar_page.dart:1212–1236`, `upcoming_agenda_view.dart:1228–1240`);
   then the ⋮ as today. The tune button is present in every mode: Missed
   only also applies to month mode's rows; Order and Rows apply to list mode
   and are disabled rows (38 %) in the sheet while another mode shows.
2. **The filter group** — one `FormRowGroup` at `RowMetrics.groupInset`,
   `FormMetrics.bodyTop` under the bar:
   - `FormSearchRow(controller: _searchController, hint: upcomingSearchHint,
     clearTooltip: upcomingClearSearch, onChanged: _onQueryChanged,
     identifier: overview-search)`. Session-only, as today.
   - `FormPickerRow(glyph: Icons.category_rounded, label:
     overviewCategories, value: <read-back>, onTap: _pickCategories,
     identifier: overview-categories)`. The read-back is
     `calendarFilterCategoriesAll` ("All") for the empty allowlist, else
     `CalendarFilterSummary.namesReadBack` over the localized labels (two
     names, then "+N more"), never an ellipsis. `CategoryFilterTile` and
     `_CategoryAvatarCluster` lose their last reader (§5, §6 slice 6).
   - **The Period row** (D11 · A): `FormMenuRow<OverviewPeriodChoice>(glyph:
     Icons.date_range_rounded, label: overviewPeriod, value:
     _period.menuValue(l10n), selected: _periodChoice, items: [This year,
     Last 12 months, Last 90 days, All time, Custom range…], onSelected:
     _selectPeriod, menuWidth: FormMetrics.menuWidth, identifier:
     overview-period)` — the agenda filters sheet's Period row
     (`agenda_filters_sheet.dart:530`), its items with ids
     `overview-period-this-year` / `-last-12-months` / `-last-90-days` /
     `-all-time` / `-custom` and the icons `today_rounded` / `history_rounded`
     / `history_rounded` / `all_inclusive_rounded` / `date_range_rounded`
     ("value lists carry their values' icons"). A preset writes the period at
     once; "Custom range…" opens the picker (§3.5) seeded with the current
     span and writes it on Apply, nothing on cancel. The checked item is the
     current preset, or Custom range… while the period is a span; the value
     reads the preset's label or the span ("Mar 15 – Jun 20, 2026",
     `valueMaxLines`). The row drops focus first (`_blur()`).
3. **The count**: `FormCaptionSlot(candidates: [the count], child:
   FormCaption(agendaDayListCountLabel(kept, missed), maxLines: 1, padding:
   FormMetrics.groupCaptionPadding))` under the group — the **listed**
   entries after every filter of §3.8; "No entries" never: the empty state
   below says it, and the caption then reads `daySummaryEntryCount(0)`.
   One line that changes text only.
4. **The pinned month label**: `FormSectionLabel(text: monthLabel(month,
   withYear: true), trailing: agendaDayListCountLabel(month's kept, missed))`
   at the group inset on `pageGround` with `RowMetrics.groupGap` above and
   `sectionLabelBottomPadding` below, present whenever the list has rows;
   its text follows the first visible row's month (§3.8), changing text,
   never geometry. In Per event mode it names the first visible category
   group instead ("GYM · 2 EVENTS"). An empty `SizedBox` of the same height
   on the empty state.
5. **The list**: `ListView.builder(controller: _listScroll,
   itemExtentBuilder: _extentOf, keyboardDismissBehavior: onDrag, padding:
   (groupInset, 0, groupInset, bodyBottom + max(viewInsets.bottom,
   viewPadding.bottom)))` under a `Scrollbar(controller: _listScroll,
   interactive: true)` and the scrubber (§3.7); body id `overview-list`. The
   rows are §3.3's. Empty: `FormCaption(overviewEmptyPeriod, padding:
   groupCaptionPadding)` in a `ListView` as the day list does. While months
   are still resolving (§3.8) the last row is `FormCaption(overviewLoading)`;
   past the cap, `FormCaption(overviewCapReached(count))`.
6. **The list options sheet** (D5 · A), `lib/widgets/overview_options_sheet.dart`,
   `OverviewOptionsSheet.show(context, {required OverviewListOptions
   initial, required bool listMode, required ValueChanged<OverviewListOptions>
   onChanged})`: a **live-apply sub-sheet** — content-tall under the
   `sheetHeightFactor` clamp, route drag, no `PopScope`, `FormSheetHandle`,
   `FormSheetHeader(leadingIcon: close_rounded, leadingTooltip: close,
   leadingIdentifier: overview-options-close, title: overviewListOptions,
   trailing: SizedBox.shrink(), trailingInset: headerActionInset)`, one
   `FormRowGroup`: `FormMenuRow<OverviewOrder>(glyph: swap_vert_rounded,
   label: overviewOrder, value: Oldest first / Newest first, items with ids
   overview-order-oldest / -newest, identifier: overview-order)`,
   `FormMenuRow<OverviewRows>(glyph: view_list_rounded, label:
   overviewRows, value: Every occurrence / One per event, ids
   overview-rows-every / -per-event, identifier: overview-rows)`,
   `FormSwitchRow(glyph: do_not_disturb_on_outlined, label:
   overviewMissedOnly, identifier: overview-missed-only)`. Every control
   writes at once through `onChanged`; the two menu rows are disabled (38 %,
   inert) while `listMode` is false. Bottom clearance on the group's padding;
   the sheet joins `sheet_bottom_clearance_test.dart`. Order and Rows persist
   (`SettingsKeys.calendarOverviewOrder` / `calendarOverviewRows`, names,
   `fromName` fallbacks `oldestFirst` / `everyOccurrence`); Missed only is
   session-only (a restrictive filter that would otherwise hide the log on
   the next open).
7. **Year and Month modes**: unchanged bodies (the year nav over the pager,
   the month nav over the grid and its rows) under the same bar and filter
   group — the Period row reads the year ("2026") in year mode and is
   disabled (38 %, inert) in month mode, where the month nav is the control;
   month mode's section header is replaced in slice 3 by the day list's
   picked-day read row (`FormRowShell` + `FormPickerRow(onTap: null)` with
   the ✕ "Whole month" trailing button, id `overview-whole-month`) and the
   day list's rows — the same builder as list mode, so Tier 4's item is
   closed for the whole page, not the list alone. The `Visibility`-held
   button and `_buildSectionHeader` go (§5). The year nav keeps its ids
   `overview-nav-previous` / `-next` / `-today` / `-title`; the month nav
   takes the same set (the two never share a screen).

### 3.3 The rows — one builder for the sheet and the page

`lib/widgets/agenda_day_list_rows.dart` keeps the row model
(`AgendaDayListRow` and its three cases) and `buildAgendaDayListRows`, and
gains `AgendaDayListRowBuilder`: a stateless helper taking `rows`, `today`,
`onEntryTap`, `onEntryEdit`, `captionMaxLines` and the `l10n`, exposing
`build(context, index)` plus `extentKindOf(index)` — the day list sheet's
`_buildRow` / `_buildReadRow` / `_buildEntryRow` (`agenda_day_list_sheet.dart:682–780`)
moved verbatim, and the sheet calls it. The rows:

- **Month row** → `FormSectionLabel(monthLabel(month, withYear: showYear),
  trailing: <the month's count label>)`. In list mode `buildAgendaDayListRows`
  is called with `withMonths: true` and a new `alwaysMonths: true` so a
  single-month period still carries its header (R16), and `showYear` is
  per row — true when the period crosses a year.
- **Day read row** → `FormRowShell(first: true, last: false)` over
  `FormPickerRow(label: dayHeaderLabel(day, today), value:
  agendaDayListCountLabel(kept, missed), onTap: null, showChevron: false,
  dividerIndent: dividerIndentPlain)`. `dayHeaderLabel` gains `withYear`
  so a day outside today's year reads "Friday, May 31, 2024" once the period
  crosses a year.
- **Entry row** → `FormRowShell(first: false, last: <next row is not an
  entry>, trailingGap: !isLast)` over `FormPickerRow(leading: EventAvatar,
  label: entry.title, caption: entry.subtitle, captionMaxLines:
  captionMaxLines, onTap: onEntryTap(entry), showChevron: false,
  trailingButton: entry.onEdit == null ? null : the pencil)` — the page
  passes `onEntryEdit: null`, so no pencil; missed → `FormIndentedRow(
  dividerIndent: dividerIndentTitle)` over `Opacity(missedEventAlpha)`. The
  title is one line, ellipsized; the node reads the whole title and caption.
  A row carries `Semantics(identifier: SemanticsIds.overviewRow(eventId,
  day))` = `overview-row-<eventId>-<yyyy-MM-dd>`.
- **Per event row** (D10) → the same entry row with `value: '$count'`
  (tabular), `caption: '<first> – <last>' + (missed > 0 ? ' · <missed>' : '')`
  through `overviewEventSpan` / `dayListMissedCount`, grouped under
  `FormSectionLabel(categoryLabel, trailing: overviewEventCount(n))`. The
  fold (§3.8) produces `AgendaDayListRow` cases of its own:
  `AgendaDayListCategoryRow` and `AgendaDayListEventRow`, in the same file.

The extent kinds (T4): `month`, `dayRead`, `entry`, `entryCaption`, each
plus `groupGap` when `trailingGap`; `category` and `event` reuse `month` /
`entryCaption`. `_RowExtents` measures one template of each kind offstage
after the first frame and on every change of text scale, locale or theme
(a `LayoutBuilder` + post-frame read of four `GlobalKey`s, the same "size the
dependent area with an invisible template" the nav title uses), and falls
back to the nominal metrics (`RowMetrics.singleLineMinHeight`,
`FormMetrics.titleRowMinHeight`, `twoLineRowMinHeight`, the section label's
line plus its padding) until measured.

### 3.4 The period

`lib/models/overview_period.dart`:

```
sealed class OverviewPeriod
  OverviewYearPeriod(int year)                       // This year, a year set by year mode
  OverviewRollingPeriod(OverviewRollingPreset preset) // last12Months · last90Days · allTime
  OverviewCustomPeriod(DateTime start, DateTime end)  // date-only UTC, inclusive
```

`resolve({today, yearBounds, calendarBounds}) → (start, end)`: a year → Jan 1
– Dec 31; last12Months → today − 364 → today; last90Days → today − 89 →
today; allTime (D3 · A) → Jan 1 of `yearBounds.first` → today; custom → as
is, clamped to `CalendarBounds`. `menuValue(l10n)`: `'$year'`,
`overviewPeriodLast12Months`, `overviewPeriodLast90Days`,
`overviewPeriodAllTime`, or the Dates sheet's span grammar for a custom span
(`CalendarDatePickerSheet.spanLabel(l10n, start, end)`, hoisted from
`summaryLabel`'s two-date branch: "Mar 15 – Jun 20, 2026", both years named
when the span crosses one). `menuChoice`: the `OverviewPeriodChoice` the
Period row checks — `thisYear` for `OverviewYearPeriod(today.year)`, the
preset's choice, else `custom` (a year set by year mode other than today's
reads its number as the value with `custom` checked). `codec`: `encode()`
writes `preset:<name>` for a rolling period, `thisYear` for this year, and
nothing otherwise; `decode(String?)` reads forward-compatibly and falls back
to `OverviewYearPeriod(today.year)`; persisted under
`SettingsKeys.calendarOverviewPeriod` (D4 · A) and read with the page's other
settings in `getCalendarOverviewSettings()`.

Mode interplay: year mode's `_year` and the list share one notion of "the
year" — paging years, a tile tap and the month nav set
`_period = OverviewYearPeriod(thatYear)` as they set `_year` today; a
rolling or custom period chosen in the list is kept across mode switches and
year mode then shows the period's first year. Landing (D7 · A): a period
change, a query change or an order change lays the list out at today's day
when today is inside the period and the order is oldest first — the first
day on or after today, or the end — else at the top.

### 3.5 The period picker — `CalendarDatePickerSheet.pickRange`

`CalendarDatePickerMode.range` beside `single` and `multi`. `pickRange(
context, {required DateRange? initialRange, required DateTime firstDate,
required DateTime lastDate, required CalendarAppearance appearance}) →
Future<DateRange?>` with `DateRange = ({DateTime start, DateTime end})`. The
overview passes the current period's span, `firstDate = Jan 1 of
yearBounds.first`, `lastDate = Dec 31 of yearBounds.last`.

The sheet, in range mode: the filler box (`sheetHeightFactor`, route drag,
no `PopScope`), `FormSheetHandle`, `FormSheetHeader(close_rounded / cancel /
date-picker-cancel · overviewPeriod "Period" · FormHeaderTextButton(
datePickerApply "Apply", date-picker-save))`; the summary line as the
Dates sheet's, reading `spanLabel(start, end) · upcomingPeriodDays(days)`
("Mar 15 – Jun 20, 2026 · 98 days") or `datePickerRangeNone` ("Pick a start
day") while the draft has no start; the Dates sheet's own view switch
limited to Month and Year (the list view is multi mode's); the month nav as
today; the grid. **No preset chips** (T7). Taps on the grid: with no start
or with both ends set, a tap sets the start and clears the end; with a start
alone, a tap on or after it sets the end, before it restarts the start. The
span paints the start and end cells filled in the accent (`onPrimary`
numeral), the days between in the accent at `EventAvatar`'s 0.16,
continuous across the row; dimmed days outside the bounds refuse the tap as
today. **The year view picks whole months** (T10): a tile tap with no start
or both ends set makes the span that month; with a start alone, a tile on
or after it extends the span to that month's last day, a tile before it
restarts; the tiles colour the span's days (`dayColors`). Apply returns the
draft (`null` end → the start alone, one day); ✕, the barrier and drag
return `null`. `pickSingle` / `pickMulti` and every caller are untouched
(§4.1).

D9 · A: `agenda_filters_sheet.dart:252–272` `_pickCustomRange` calls
`pickRange` instead of `showDateRangePicker`; its test and the
`10_agenda_filters` flow are updated in the same slice.

### 3.6 Per event

With Rows = One per event, the listed entries (after the query and Missed
only) fold by `eventId`: title, icon and colour from the first entry,
`count`, `missed`, `first` / `last` day; groups by category id in the
allowlist's catalog order, rows by count descending then title
(`compareWithinDay`'s title fold); with Newest first, rows by last day
descending. A row tap opens the calendar on the event's last day (D10 · A).
The group's caption counts entries, not rows ("212 entries · 7 missed"
stays). The pinned label names the category group (§3.2 item 4).

### 3.7 The scrubber (D6 · A)

`lib/widgets/list_scrubber.dart`, `ListScrubber`: wraps a scroll view and
its `ScrollController`; a `Listener` lane of `scrubberLaneWidth` along the
right edge over a `Scrollbar(interactive: true, thickness:
scrubberThumbWidth)`; while a pointer is down in the lane
(`_scrubbing`), the thumb stays visible and a bubble on `menuSurface`
(`scrubberBubbleRadius`, `scrubberBubblePadding`, `labelLarge`) floats
`scrubberBubbleInset` left of the thumb, vertically tracking it, showing
`labelAt(offset)` — the page supplies the month (or category) at that
offset from its prefix sums. No perpetual animation; the bubble fades with
the scrollbar's own timing. One `Semantics` node, `identifier:
overview-scrubber`, `label: overviewScrubberLabel`, excluded from the list's
indexes. Optional in the sense of §6: slice 5 is the one slice that can be
cut without touching another.

### 3.8 Resolution and performance

1. **The store is query-free.** `_scan` drops `query`, `categoryLabels` and
   `labelTextOf`; `_rebuild` keeps the store and `_tilesByYear` across query
   changes and compares queries (`EventSearchQuery` gains `==` / `hashCode`
   over its terms and clauses). The query is applied by `EventQueryMatcher`
   (`lib/utils/event_query_matcher.dart`), extracted from the scan's
   candidate pass and its `matchesQuery` closure (`event_agenda.dart:300–407`)
   so the scan and the post-filter are **one grammar**: `matches(event, day)`
   with the per-event state memoized, the same fold caches, the same per-day
   override rule. The scan keeps calling it. The fold-budget suites pin that
   nothing is folded twice. Entries carry `eventId`; the page keeps
   `Map<String, CalendarEvent>` of the loaded list for the lookup. In year and
   month modes with a live query the tallies and bars come from the filtered
   entries (`AgendaDayListMonth.where(predicate)` → a bucket, then
   `AgendaMonthTally.ofBucket`), which costs rows for twelve months only
   while searching.
2. **The allowlist stays a scan-time filter**; a change rebuilds the store as
   today. Events, `membershipRevision`, `presenceRevision`, the appearance and
   the locale rebuild as today; `occurrenceRevision` rebuilds only while a
   query is live (R5).
3. **Batched resolution.** `_recompute` for the list asks the store for the
   period's months in order (reversed under Newest first): the first
   `syncMonths` synchronously, then one `batchMonths` run per event-loop
   turn (`Future(() {...})`, cancelled by a generation token on the next
   rebuild or mode switch), appending rows and updating the caption as runs
   land; the tail caption while pending. The store chunks any run at twelve
   months (T6) and `_forEachMissingRun` collects keys in a `Set` (R14).
   Resolution stops at `maxEntries` listed entries; the cap caption replaces
   the tail.
4. **Rows and extents.** Rows are built per resolved run and concatenated;
   prefix sums of extents per month (and per category group) are kept beside
   them, so `offsetOfDay`, `monthAtOffset` and the scrubber's label are
   O(log months). `jumpTo` is exact.
5. **Anchoring.** Before any rebuild that keeps the period (events, presence,
   appearance, a return) the page notes the first visible row's day and
   event id; after it, it jumps to that day's offset (or the nearest later
   day). A period, query or order change lands per D7.
6. **Prewarm** runs only in year mode and only for a year period (R7; the
   list has no year to page to — built so in 3a);
   covering the page cancels the prewarm and the debounce (R19); `_today` is
   re-read on `didPopNext` and on app resume, and a changed day rebuilds
   (R17); `didPopNext` coalesces the pending state and the appearance re-read
   into one rebuild (R15); the mode switch captures `rows` into the builder's
   closure (R3); `_syncPager` is left as is and pinned by a test (R20).
7. **Budget tests** (`test/widgets/overview_list_benchmark_test.dart`, tagged
   `benchmark`, and `CalendarEvent.debugOccursOnCalls`): with 10 000 events
   of mixed rules, list mode open on This year ≤ 1 scan; a keystroke pause ≤
   0 scans; a preset change ≤ 1 scan per twelve months; All time over eight
   years resolves two years synchronously and the rest in ≥ 1 later turns; a
   far `jumpTo` builds no row between; the extent table matches the laid-out
   rows at scale 1.0, 1.3 and 2.0 in en and de.

### 3.9 Copy and l10n (en / de / ro together, `gen-l10n`, `untranslated.txt` `{}`)

New keys: `overviewCategories` "Categories"; `overviewPeriod` "Period" (the
row's label and the picker's title); `overviewPeriodLast12Months` "Last 12
months"; `overviewPeriodLast90Days` "Last 90 days"; `overviewPeriodAllTime`
"All time"; `overviewListOptions` "List options" (the tune button's tooltip
and the sheet's title); `overviewOrder` "Order"; `overviewOrderOldestFirst`
"Oldest first"; `overviewOrderNewestFirst` "Newest first"; `overviewRows`
"Rows"; `overviewRowsEveryOccurrence` "Every occurrence";
`overviewRowsPerEvent` "One per event"; `overviewMissedOnly` "Missed only";
`overviewEmptyPeriod` "Nothing in this period"; `overviewLoading` "Loading
more…"; `overviewCapReached` "Showing the first {count} entries. Narrow the
period to see the rest."; `overviewEventCount` "{count, plural, one {1
event} other {{count} events}}"; `overviewEventSpan` "{first} – {last}";
`overviewScrubberLabel` "Scroll by month"; `datePickerApply` "Apply";
`datePickerRangeNone` "Pick a start day". Reused: `dayListModeYear` /
`-Month` / `-List` (the view menu's rows), `upcomingPeriodWholeYear` ("This
year"), `upcomingPeriodCustom` ("Custom range…"), `upcomingSearchHint`,
`upcomingClearSearch`, `calendarFilterCategoriesAll`, `upcomingPeriodDays`,
`daySummaryEntryCount`, `dayListMissedCount`, `datePickerToday`, `close`,
`cancel`. Retired: `overviewEmptyYear`. German keeps the day list's
"Termin" for counts (the open copy question of Tier 3 §8 stays open).

### 3.10 Semantics ids (`lib/constants/semantics_ids.dart`, under the day list's block)

`overview-view-year` / `-month` / `-list` (the view menu's rows),
`overview-options-open`, `overview-options-close`, `overview-order` with
`overview-order-oldest` / `-newest`, `overview-rows` with
`overview-rows-every` / `-per-event`, `overview-missed-only`,
`overview-search`, `overview-categories`, `overview-period` with
`overview-period-this-year` / `-last-12-months` / `-last-90-days` /
`-all-time` / `-custom`, `overview-nav-previous` / `-next` / `-today` /
`-title` (year and month modes), `overview-list`, `overview-whole-month`,
`overview-scrubber`, `overviewRow(eventId, day)` →
`overview-row-<eventId>-<yyyy-MM-dd>`, `overviewEventRow(eventId)` →
`overview-event-<eventId>`. `calendar-overview-open`, `calendar-view-menu`,
`date-picker-save` / `-cancel` / `-today` stay.

## 4. Behaviour

### 4.1 Must not change

- The page owns no data and edits nothing; rows come from the app-wide
  `CalendarBloc`; every input funnels through `_rebuild`; the grid filters
  are ignored; the allowlist is empty = all with the picker's inversion
  (`_pickCategories` re-reads the catalog after the picker, a full result
  collapses to empty); `CalendarOverviewPage.forTesting(openOccurrence:)`
  reports `(day, eventId)`.
- Persisted keys and meanings: `calendar_overview_categories` (sorted CSV),
  `calendar_overview_mode` (`year` / `month` / `list`, default `year`,
  `fromName` fallback), read in one statement by
  `getCalendarOverviewSettings()` with the appearance and the haptic switch;
  the search is session-only; `_persistMode` writes only on a user's pick.
- Year mode as shipped: the year nav, the pager, `yearBoundsOf` over
  `passesEventFilters`, marks-only tiles, the 250 ms prewarm of the
  neighbouring years, the jump picker's flash, `_tileColor`; month mode as
  shipped: the month nav, the month grid on `CalendarDaysOfWeek`, `hasEntry`
  / `barsFor` cache-only, the picked day narrowing the rows, `_goToMonth`
  clamping `_year`, `_scrollMonthToTop`.
- `AgendaMonthStore`: resolve on navigation, never in build (the pager's
  `tilesFor` the one exception); one resolver call per contiguous run of at
  most twelve months; an empty bucket for every requested month; bars folded
  on arrival; the tally tier; `keyOf` / `monthOfKey` / `monthOf` /
  `monthOrder` / `monthsOfYear`. The day list sheet keeps rendering through
  it unchanged, with its two scopes, its chips, its ids and `DayListRobot`.
- `EventAgenda.occurrencesInRange`'s results for every existing caller, the
  `maxRangeDays` cap, `resolveRange`, `partitionForWindow`, the per-day
  `compareWithinDay` order, the collapse pass, the fold caches and their
  debug counters, every fold-budget test; `yearBoundsOf`.
- `buildAgendaDayListRows` and `agendaDayListCountLabel` for the day list's
  calls (`alwaysMonths` defaults to false); `AgendaListView.eventDayEntries`
  / `eventDayMarks` / `monthLabel` / `dayHeaderLabel` for every caller
  (`withYear` defaults to false).
- `CalendarDatePickerSheet.pickSingle` / `pickMulti`, their guards
  (`allowEmpty`, the answer latch), `summaryLabel` / `datesValue`, the
  single and multi views (the year view keeps opening a month there), their
  ids and `calendar_date_picker_views_test` (the Dates sheet's suite; the
  name `calendar_date_picker_sheet_test` this record first used does not
  exist).
- `CalendarViewMenu`'s pages group and the calendar's formats group with
  their ids; the ⋮ (`CalendarOverflowMenu`: Alerts, Export disabled on an
  empty store, Calendar settings with the reload after); `switchToCalendar`
  returning to the calendar beneath; `toCalendarOverview` /
  `switchToCalendarOverview`; `toCalendarOccurrence`'s root push when no
  calendar is open and its collapse when the calendar is the top page's own
  satellite (the alerts hub).
- The agenda filters sheet's Period row, its menu and `_PeriodChoice`; only
  its `_pickCustomRange` body changes (D9).
- `EventSummaryProvider` as the one look rule; `EventAvatar`;
  `CalendarColors.missedEventAlpha`; presence decided in the agenda layer.
- The sheet chrome rules of `ui-language`, the bottom clearance rule and
  `sheet_bottom_clearance_test.dart` (the range mode and the options sheet
  join it); every existing calendar flow green; `05_overview` updated, never
  dropped.

### 4.2 Deliberately changes

- The list's unit is a period (§3.4), set from the Period row's menu and the
  picker; list mode carries no nav; the year nav's "Nothing in {year}"
  becomes "Nothing in this period"; the list lands on today (D7).
- The modes move from a `SegmentedButton` on the page into the title's view
  menu (D8 · A); the list options live in a sheet behind the bar's tune
  button (D5 · A).
- A row tap from the view-menu path **pushes** a calendar over the overview
  instead of collapsing onto the one beneath (D1 · A, R1); the overview's
  parking then serves both paths; back returns to the list anchored on the
  row that was tapped.
- The rows, the search field and the categories row move onto the language;
  `AgendaDayListRowView`, `CategoryFilterTile`, `_CategoryAvatarCluster`,
  the `SegmentedButton`, the raw `TextField` and month mode's
  `_buildSectionHeader` go.
- The entry caption is one line on the page (T8); a month header is always
  present in list mode (R16); day headers and month labels name the year
  when the period crosses one.
- The query no longer rescans (T3); `occurrenceRevision` rebuilds while a
  query is live (R5); the prewarm is skipped for non-year periods (R7); the
  cover cancels pending work (R19); today is re-read (R17); the keyboard
  drops on drag (R18); the list is anchored across rebuilds and lands per D7
  on a period, query or order change (R4).
- New persisted keys: `calendar_overview_period` (a preset name or absent),
  `calendar_overview_order`, `calendar_overview_rows` (names); all three
  join `_calendarOverviewKeys`, the settings reset and the backup's settings
  pass as every setting does.
- Month mode's day headers wrap like the day list's (the fix pass's D): its
  sliver sizes its rows, so the single-line squeeze went; the picked day's
  row and the ✕ are unchanged.
- The pinned band above the list yields when it would take more than
  `OverviewListMetrics.pinnedBandMaxShare` of the list's share (the keyboard
  up at 360 × 780 × 2.0), and the list shifts by its height then — the one
  place the "nothing moves" rule bends, for a scrollable list over a band.
- The agenda filters' custom range opens the in-app picker (D9 · A), with
  no start when no range is pinned (the Material dialog pre-filled today →
  today + rangeDays − 1).

## 5. Facts from the tree (`ae98d62`, re-grep before editing)

- `lib/pages/calendar_overview_page.dart`: fields :72–137 (`_mode` :88,
  `_today` :92, `_searchController` :106, `_rows` :121, `_route` /
  `_covered` / `_pendingState` :132–137); `initState` :140; `didPushNext` /
  `didPopNext` :179–189; `_loadSettings` :191; `_reloadAppearance` :209;
  `_openSettings` :223; `_refreshCategoryLabels` :238; `_listenWhen` :253;
  `_adopt` :272; `_rebuild` :282–312; `_syncPager` :314; `_scan` :323;
  `_resolve` :336; `_resolveMarks` :346; `_recompute` :355–392 (list case
  :362–372); `_tilesFor` :394; `_tallyYear` :406; `_schedulePrewarm` :420;
  `_selectMode` :436; `_persistMode` :453; `_onYearPaged` :459; `_goToYear`
  :470; `_pickDate` :489–522; `_openMonth` :524; `_goToMonth` :534;
  `_toggleSelectedDay` :550; `_onQueryChanged` :565; `_clearQuery` :570;
  `_applyQuery` :576; `_pickCategories` :587; `_openOccurrence` :613–625;
  `build` :632–686 (`AnimatedSwitcher` :673, the ⋮ :656); `_buildSearchField`
  :688–723; `_buildCategoryTile` :725–740; `_buildModeSelector` :742–780;
  `_buildBody` :782–895 (list :818–842, month :844–893); `_buildRow` :897;
  `_buildYearNav` :906; `_buildMonthNav` :921; `_buildSectionHeader`
  :949–1004. Private constants :74–77.
- `lib/widgets/calendar_header_menus.dart`: `CalendarViewMenu` fields
  :40–55 (`format`, `onFormatSelected`), `_labelOf` :66, `_items` :121–162
  (the formats group :147–161 after `PopupMenuDivider(
  AppTheme.menuDividerHeight)`), `build` :165–214; `CalendarOverflowMenu`
  :215.
- `lib/pages/calendar_page.dart:1212–1236`: the bar's filter button
  (`Badge.count` over `AutomationId` over `IconButton(isSelected:)`);
  `lib/widgets/upcoming_agenda_view.dart:1228–1240`: the agenda's tune
  button, the same shape.
- `lib/widgets/agenda_filters_sheet.dart`: `_PeriodChoice` :106, the Period
  `FormMenuRow<_PeriodChoice?>` :530, `_pickCustomRange` :252–272
  (`showDateRangePicker` :254), `_periodChoice` :278, `_selectPeriod` :290.
- `lib/widgets/form_rows.dart`: `FormRowShell` :139, `FormSectionLabel` :199
  (`trailing`), `FormSheetHandle` :251, `FormSheetHeader` :279,
  `FormPickerRow` :714 (`leading`, `caption`, `captionMaxLines`,
  `trailingButton`), `FormSwitchRow` :1431, `FormChip` :2039, `FormChipRow`
  :2185, `FormCaption` :2321 (`maxLines`, `padding`), `FormCaptionSlot`
  :2366 (`candidates`), `FormSearchRow` :2413, `FormMenuItem` :2504,
  `FormMenuRow` :2528 (`glyph`, `label`, `value`, `selected`, `items`,
  `onSelected`, `menuWidth`, `identifier`; no caption). `AppTheme.menuWidth`
  :118, `menuDividerHeight` :123. `lib/constants/form_metrics.dart`,
  `row_metrics.dart`: the names of §3.1; `lib/constants/app_colors.dart`
  :81–98 `SurfaceRoles`.
- `lib/utils/agenda_month_store.dart`: `ensure` :76, `ensureTallies` :84,
  `_forEachMissingRun` :106–124, `_spanOf` :126–136, `_resolveRun` :138–157,
  `_resolveMarkRun` :159–175, `barsFor` :179, `hasEntry` :185, `_buildBars`
  :193–213.
- `lib/utils/agenda_day_list_index.dart`: `AgendaDayListIndex.build` :57,
  `_MonthAccumulator` :198, `AgendaMonthTally` :250, `AgendaDayListMonth`
  :304–391.
- `lib/widgets/agenda_day_list_rows.dart`: the row cases :9–41,
  `buildAgendaDayListRows` :48–95 (`multiMonth` :57, `crossesYear` :61),
  `agendaDayListCountLabel` :99, `AgendaDayListRowView` :107–208.
- `lib/widgets/agenda_day_list_sheet.dart`: `_buildBody` :604–677,
  `_buildRow` :682–712, `_buildPickedDayRow` :714, `_buildReadRow` :736,
  `_buildEntryRow` :757–780, `_buildMonthNav` :782.
- `lib/utils/event_agenda.dart`: `EventOccurrence` :19, `maxRangeDays` :241,
  `occurrencesInRange` :266 (candidates :300–366, `partitionForWindow` call
  :372, `matchesQuery` :383–407, the day loop :410–447, the collapse
  :449–480), `passesEventFilters` :489, `yearBoundsOf` :517, `resolveRange`
  :980–986, `debugClearFoldCaches` :1080.
- `lib/widgets/agenda_list_view.dart`: `monthLabel` :640, `dayHeaderLabel`
  :657, `eventDayEntries` :692, `eventDayMarks` :728.
- `lib/widgets/category_picker_sheet.dart`: `CategoryFilterTile` :403 (the
  overview :733 is its last reader; `_CategoryAvatarCluster` beside it).
- `lib/widgets/calendar_date_picker_sheet.dart`: modes :23, views :28,
  `pickSingle` :92, `pickMulti` :120, `summaryLabel` :149, `_show` :186, the
  answer latch :296, the header and view switch :416–445, `_buildSummary`
  :523, the Today slot :493, the year view :701, the list view :811, the day
  cell :1060.
- `lib/models/upcoming_agenda_filters.dart`: `AgendaPeriodMode` :102,
  `presetWindow` :213.
- `lib/services/app_navigator.dart`: `_collapseOnto` :286–297,
  `pendingCalendarOccurrence` :435, `toCalendarOccurrence` :453–475,
  `toCalendarOverview` :511, `switchToCalendarOverview` :546–552.
- `lib/pages/calendar_page.dart`: `CalendarPage(initialDay, initialEventId)`
  :153–162, `_openOccurrence` :668–704, `_openDetailSheet` /
  `_detailSheetLoop` :855–1000 (the dependencies D1 · B would have to lift:
  `_sheetGuard` :185, `_colorPalette` :194, `_keepsHeard` :581–600,
  `_setOccurrencePresence`, `_openWikiLink`, `_resolveNoteTitle`,
  `_skipOccurrence`, `_quickEditDescription`, `_editExplicitDates`,
  `_editorSheet`, `_openLinkedNote`, `_pendingAfterSave`,
  `_occurrenceSurvives`).
- `lib/services/settings_service.dart`: `_calendarOverviewKeys` :1229,
  `getCalendarOverviewSettings` :1247–1265, the two setters :1267–1280;
  `lib/constants/settings_keys.dart`: :226–232, `defaultCalendarOverviewMode`
  :521.
- `lib/constants/semantics_ids.dart`: `calendarViewMenu` :62,
  `calendarOverviewOpen` :64, `calendarFormatMonth` :65, the day list's
  block :386–404.
- Tests: `test/widgets/calendar_overview_page_test.dart` (cases :187–492; the
  one list case :345; `pumpUntilLoaded` waits for a `ListTile`; the header
  group :379–492 drives the view menu);
  `test/utils/agenda_month_store_test.dart`; `test/widgets/support/` has no
  overview robot (`day_list_robot.dart` is the shape);
  `CalendarEvent.debugOccursOnCalls` `lib/models/calendar_event.dart:455`;
  `test/widgets/agenda_filters_sheet_test.dart` drives the custom range.
- QA: `tool/qa/flows/calendar/05_overview.txt` (taps "Year" / "Month" /
  "List" by label, expects "Lifting session"); `08_header.txt` walks the view
  menu; `tool/qa/fixtures/calendar.json` seeds eight events.
- Precedents: `SliverMainAxisGroup` in `markdown_settings_page.dart:1732`
  (not used here); `itemExtent` in `month_year_picker_sheet.dart:578` and
  `note_match_list_sheet.dart:187`; `AgendaPeriodNav`'s template measuring
  (`agenda_period_nav.dart:132–175`).

Retire list (grep for the last reference before deleting, slice 6):
`AgendaDayListRowView`; `CategoryFilterTile` and `_CategoryAvatarCluster`
(`category_picker_sheet.dart:403`) if the overview was the last reader;
`_buildModeSelector` and the `SegmentedButton` import on the page;
`_buildSearchField`; `_buildSectionHeader` and the `Visibility` button; the
list-mode branch of `_buildYearNav`'s callers; the page's four private
`Duration`s; `overviewEmptyYear` (three ARBs); the agenda's
`showDateRangePicker` import.

## 6. Slices

### Slice 0 — The safety net (implementer)

Before any visual change, against the old UI, all green:

- `test/widgets/support/overview_robot.dart` (`OverviewRobot`): open in a
  mode, switch modes, read the nav title and count, type a query, pick
  categories, tap a row by title, the chevrons, the Today slot, the jump
  picker; the suites drive the page only through it.
- `calendar_overview_page_test.dart`, list block: a persisted
  `calendar_overview_mode = list` opens in list mode; the rows carry month
  and day headers with counts under faded and hidden missed display; a row
  tap reports `(day, eventId)`; the chevrons and the picker change the rows
  (pin today's kept pixel offset after a chevron, R4, so slice 3 changes it
  on purpose); the search narrows, clear restores, an empty year shows the
  empty state; a bloc emit with a new list or `presenceRevision` redraws; an
  `occurrenceRevision`-only emit with a live query is pinned as today (R5);
  emits while covered are parked and adopted once on pop; a fling then a mode
  switch during the fade (R3) — recorded as today's behaviour, whichever it
  is; scan budgets through `debugOccursOnCalls`: open, a keystroke, a
  chevron, Year → List → Year, the prewarm's two extra scans after 250 ms in
  list mode (R7); a navigation case: a row tap with a calendar route beneath
  pops the overview (R1), with the header group's navigator-key pattern; the
  keyboard via `tester.view` insets at 360 × 780, 412 × 915 and scale 2.0;
  de / ro header labels.
- `test/widgets/agenda_day_list_rows_test.dart`: `buildAgendaDayListRows`
  (`groupByDay`, `withMonths`, a single-month year — R16 pinned, `crossesYear`,
  empty days skipped, kept vs missed) and `AgendaDayListRowView`'s gap rule
  and faded row.
- `agenda_month_store_test.dart`: a run of more than twelve months asserts
  (pins the contract slice 1 chunks around); a partly cached year resolves
  in two calls.
- `test/widgets/overview_list_benchmark_test.dart` (tag `benchmark`): 10 000
  events, open / chevron / keystroke / far `jumpTo` timings and scan counts,
  numbers printed, budgets of §3.8 item 7 asserted only after slice 4.

### Slice 1 — Model, store, matcher, persistence (implementer, `effort: medium`)

`OverviewPeriod` + codec + tests; `OverviewListOptions` (`OverviewOrder`,
`OverviewRows`, `missedOnly`) + codecs; `OverviewListMetrics`; the store
chunks runs at twelve months and uses a `Set` (R2, R14) + tests;
`EventQueryMatcher` extracted and the scan rewired, every fold-budget and
agenda suite green unchanged, `EventSearchQuery ==`; `SettingsKeys` ×3,
`getCalendarOverviewSettings` and setters, reset and backup; the ARB keys of
§3.9 in three languages, `gen-l10n`; the ids of §3.10;
`buildAgendaDayListRows(alwaysMonths:)` and `dayHeaderLabel(withYear:)`
with tests. Nothing visible changes.

### Slice 2 — The period picker (implementer)

`CalendarDatePickerSheet.pickRange` per §3.5 with its suite
(`calendar_date_picker_sheet_test.dart`: Apply returns the span, ✕ / barrier
/ drag return `null`, the grid's tap rules, the year view's month picks,
bounds refuse, de at 2.0 with no overflow at 360 × 780, the clearance test
entry); D9 · A: the agenda's custom range on it,
`agenda_filters_sheet_test` and the `10_agenda_filters` flow updated.

### Slice 3 — The page (implementer)

§3.2 whole — the view menu's presentations group (`CalendarViewMenu`
extended, the header suite extended, `08_header` kept green), the tune
button, the options sheet with its suite
(`overview_options_sheet_test.dart`, an `OverviewOptionsRobot`, the
clearance entry) and its robot, the filter group with the Period row and
the caption slot, the pinned label, the list on the shared builder (§3.3,
the day list adopting it with `DayListRobot` green and its test bodies
untouched), §3.4, §3.6, §3.8 items 1, 2, 4, 5, 6; the row tap per D1 (T9
verified against the restore stack); month mode on the day list's
picked-day row. `OverviewRobot` is rewritten for the new UI; the test bodies
change only where §4.2 says so, each change named in the report. Flow
`05_overview` updated (the modes through the view menu's rows); a new
`23_overview_list` flow: List · the Period menu (a preset) · Custom range…
on the grid and on the year view · the options sheet (Newest first, One per
event, Missed only, the badge) · a row tap and back lands on the list ·
search · Calendar through the view menu.

### Slice 4 — Batched resolution and the cap (implementer)

§3.8 items 3 and 7; the benchmark budgets asserted; FakeAsync tests for the
batches, the generation token, the tail and cap captions, Newest first
resolving from the end.

### Slice 5 — The scrubber (implementer) — the cuttable slice

§3.7, `ListScrubber` with its own suite (`list_scrubber_test.dart`: a drag in
the lane scrolls and shows the label, a drag on the rows does not, one
semantics node); wired into the page with the offset map; the flow walks it.

### Slice 6 — Delete the old UI (implementer, `effort: medium`)

The retire list of §5; `dart analyze lib test` clean; `untranslated.txt`
`{}`.

### Slice 7 — Device pass, review, docs

`qa-runner`: `qa relaunch --fresh --seed tool/qa/fixtures/calendar.json`
then `qa flows calendar` (24 flows), then `qa set theme=dark locale=de
text-scale=2.0`, the list, the view menu, the options sheet, the picker and
Per event at 360 × 780 and 412 × 915, `qa errors` clean. `reviewer`: §3,
§4.1 and the diff, confirmed defects only; fix, re-run the gate. Docs:
`docs/calendar-events-feature.md` gets a dated addendum (the period, the
matcher, the batches, the row tap, the view menu's second group);
`.claude/skills/calendar-events/references/subsystems.md` § Overview gets
its facts; `calendar-events` SKILL.md "Overview, drill-down, years" gets
the rule lines (the query is a post-filter; runs chunk at twelve; the row
tap pushes; the view menu carries the presentations); `calendar-ui`
SKILL.md gets the ids and the flow count; this record's status line and the
master's §9 table.

## 7. Definition of done

1. The data the page writes equals what it wrote before for the same input:
   the three old keys unchanged, the three new keys absent until set.
2. Every control reachable one-handed at 360 wide with 48 dp targets: the
   view menu's rows, the tune button, the filter rows, the sheet's rows, the
   scrubber lane, the picker's cells and tiles.
3. The picker's ✕, barrier and drag change nothing; Apply returns the span;
   the options sheet's ✕, barrier and drag leave what was set.
4. Light and dark; en, de, ro; 1.3 and 2.0 with no clipped label and no
   overflow on the page, the view menu, the options sheet, the picker and
   the Per event rows.
5. Keyboard up and down: the list's bottom clearance holds, the filter group
   stays put, the keyboard drops on drag.
6. Nothing moves under the finger: the pinned label and the caption slot
   change text only, the sheet's disabled rows stay in place.
7. Every string in three ARBs, `untranslated.txt` `{}`.
8. One node per row, ids on everything the flows target, tooltips on every
   icon button, the scrubber excluded from the list's indexes.
9. `calendar_overview_page_test`, `agenda_day_list_sheet_test`,
   `agenda_month_store_test`, the fold-budget suites,
   `calendar_header_menus`' header cases and
   `calendar_date_picker_sheet_test` pass with bodies unchanged except where
   §4.2 names the change; the new suites of §6 exist.
10. Nothing on the retire list is referenced; no literal number on the page.
11. Budgets: This year open ≤ 1 scan; a keystroke 0 scans; a preset change ≤
    1 scan per twelve months; a far jump builds no row in between; All time
    over eight years keeps the first frame under the sync budget and
    finishes in later turns.
12. A row tap and back lands on the same row; a period change lands per D7.

## 8. Deferred

- **D1 · B — the detail sheet over the list.** Extract
  `_detailSheetLoop` (`calendar_page.dart:865–1000`) and its twelve
  dependencies (§5) into `lib/controllers/occurrence_detail_flow.dart`,
  owned by whichever page opens it, writing only through the bloc; the
  overview then opens an occurrence in place with no navigation. A rework of
  its own with the detail, description and alert-keep guards as its must-not-
  change list.
- **D11 · B — a stepping nav in list mode**, if the owner wants chevrons
  that shift a span by its own length: `OverviewPeriod.stepped(by:)` and
  `AgendaPeriodNav` under the filter group, the Today slot as This year.
- **The lane as a whole-height drag target** (review 12): a vertical drag
  anywhere in the rows' trailing 48 dp scrubs; a right thumb scrolling at
  the edge jumps. D6 · A chose the lane; the alternative is to scrub only
  from the thumb's band. The owner decides after living with it.
- **Header slots sized for the locale's widest day label**: at German 2.0 a
  header that needs two lines sits in a slot sized for the widest case
  (three lines) with visible padding; keying the template on the period's
  own widest label would tighten it at the cost of a re-measure frame per
  period change.
- **The count caption's number is unformatted** (`daySummaryEntryCount`
  reads "20000 entries"); `decimalPattern` as the cap caption has.
- **The 19 flow** (`19_fasting_schedule`) is red on the 952 dp emulator for
  a pre-existing reason: its `scroll-to id:fasting-days-off` leaves "Extra
  fast days" below the fold; not this rework's.
- **`toCalendarQuickAlarm` above an overview**: it still matches stamped
  calendars only, so with the occurrence calendar on top it collapses onto
  the calendar beneath and pops the overview; the same name match
  `toCalendarOccurrence` gained in the 3a follow-up would make it push or
  serve in place.
- **Store eviction** (R13): a bounded LRU of months, keyed on access, once a
  period can hold decades.
- **Lazy bars** (R11): fold a month's bars on the first `barsFor`.
- **Lighter entries** (R12): an entry converter that skips the description
  resolve and formats the subtitle in the row.
- **Fading through colours** instead of `Opacity` on missed rows, if the
  benchmark shows raster cost; the day list would follow.
- **Cross-year search index**: the query over All time is the answer today;
  a term index would make it instant.
- **Share this period**: the listed rows as text (title · day per line) through
  `shareExport`; the ⋮'s `.ics` export stays event-level.
- **Collapsible months**, **per-category totals under the caption**, **Last
  30 days / Year to date** (D2 · B), **saved views** (period + options +
  categories as a named preset, the saved filters' pattern).
- **The jump picker's day wheel** and the **two-line sheet header at 200 %**
  (Tier 3 §8) stay open.

## 9. Ledger

- **2026-10-11 — PLAN.** Read of the list mode at `ae98d62`; one
  independent review (R1–R21); the mock
  https://claude.ai/artifact/GpAs4MTkY1Vc4gY9wyBhnq (version 1); D1–D10
  asked; nothing in the tree. Baseline `flutter test` count: to be recorded
  by slice 0.
- **2026-10-11 — PLAN, revision 2.** The owner found the list's period nav
  out of place and asked for every component to respect the language. The
  nav and both chip rows left list mode; the Period menu row, the caption
  slot, the view menu's presentations group and the options sheet took
  their place (mock version 2); D5, D7, D8 re-asked, D11 added; nothing in the tree.
- **2026-10-11 — IN PROGRESS.** The owner delegated D1–D11 ("take any
  decisions using fable and implement using whatever you see fit"); the
  recommended option stands for each. Slices dispatched one at a time to
  `implementer` agents (Opus 5.5), slice 3 split into 3a (the chrome: view
  menu group, tune button, options sheet, filter group) and 3b (the list
  body and behaviours); the gate after each. At dispatch nothing was in the tree.
- **2026-10-11 — slice 0 done (the safety net).** Whole suite `+7317 ~7 -1`
  before → `+7356 ~8 -1` after (39 tests; the extra skip is the benchmark,
  tagged and skipped by default as the other benchmarks are);
  `OverviewRobot`, a 24-case list-mode group, 13 row-builder cases, 2 store
  cases, the 10 000-event benchmark. Characterizations: R1, R4, R5, R7, R16
  pinned as today; R3 **reproduced** (the outgoing list throws
  `RangeError`s during the cross-fade); the keyboard overflows nowhere (R18
  is about the viewport's height, not a layout failure). Benchmark
  (412 × 915, year 2026): open in list mode 643 ms / 8 608 `occursOn`
  calls; the prewarm +11 993; a chevron 79 ms / 7 615; a keystroke pause
  97 ms / 385; a far `jumpTo` **13 237 ms**, 6 346 row builds, landing
  25 516 px short of the real extent (R9). Noticed: `multiMonth` counts
  empty edge days, so `[Jan 6 (empty), Mar 9]` draws a lone "March" header —
  `alwaysMonths` (slice 1) makes it moot for the page.
- **2026-10-11 — slice 1 done (model, store, matcher, persistence).** Whole
  suite `+7404 ~8 -1` (48 tests). `OverviewPeriod` (+ `DateRange`,
  `OverviewPeriodChoice`, codec), `OverviewListOptions`,
  `OverviewListMetrics` (the page reads them), the store chunking runs at
  twelve (the slice-0 assert case flipped to "12 + 1", a 30-month case
  added), `EventQueryMatcher` with the fold caches and helpers moved into it
  (`mayMatch` / `matches`, memo by event identity; parity shown on the six
  fold-budget and agenda suites unchanged), `EventSearchQuery ==`, the three
  keys with `getCalendarOverviewSettings({today})` / two setters
  (`deleteValue` for a custom period), 21 ARB keys ×3, the ids,
  `alwaysMonths`, `dayHeaderLabel(withYear:)`. Deviations: `encode({today})`
  needs today; `fromChoice(custom)` throws; there is **no reset list and no
  backup pass carrying the overview keys** (§4.2's assumption was wrong —
  nothing to mirror). Noticed: `overview_period.dart` imports the picker
  widget for `spanLabel` — slice 2 moves it to `lib/utils/date_span_label.dart`.
- **2026-10-11 — slice 2 done (the period picker).** Whole suite
  `+7421 ~8 -1` (16 range cases + 1 clearance case). `pickRange` through a
  generic `_show<T>`, the draft as `_rangeStart` / `_rangeEnd`, Apply
  null-pressed without a start, the summary in a two-line `FormCaptionSlot`,
  Month and Year views only, one `_pickRangeEnds` helper for days and tiles,
  the band as two half-cell layers behind the chip at the avatar's alpha
  (`CalendarDayCell.chipTop` named for it), the year tiles coloured on
  in-span days; `dateSpanLabel` in `lib/utils/date_span_label.dart` (the
  model no longer imports the widget); the agenda's `_pickCustomRange` on
  `pickRange` with the sheet taking `appearance` (optional, the production
  caller passes it), its two test bodies rewritten, `showDateRangePicker`
  gone. Deviations: the Dates sheet's suite is
  `calendar_date_picker_views_test.dart` (§4.1's name was wrong); an
  unpinned custom range now opens with no start (the dialog pre-filled
  today → today + rangeDays − 1); an end on an outside-month cell is not
  dimmed, as multi mode has it; the `10_agenda_filters` flow never walked
  the custom range, so it was not changed.
- **2026-10-11 — slice 3a done (the chrome, the period, the row tap).**
  Whole suite `+7447 ~8 -1`. `CalendarViewMenu(presentation:,
  onPresentationSelected:)` with Year · Month · List (`apps_rounded` /
  `calendar_view_month_rounded` / `format_list_bulleted_rounded`, a test
  pins every glyph unique); the tune button with the badge;
  `OverviewOptionsSheet.show(context, {initial, listMode, onChanged})` (8
  cases, `OverviewOptionsRobot`, a clearance case); the filter group
  (`FormSearchRow`, the Categories picker row, the Period `FormMenuRow`
  with `pickRange` behind Custom range…), the count caption; `_period` the
  list's unit (rows inside the span only, `alwaysMonths`, the year on the
  headers across a year boundary through `buildAgendaDayListRows(showYear:)`
  / `AgendaDayListRowView(dayHeaderWithYear:)`), the list's own
  `ScrollController` reset to the top on a period / query / order change,
  `keyboardDismissBehavior: onDrag`; the options honoured on the old body
  (Newest first reverses the days, Missed only narrows the list and month
  rows; `rows` held for 3b); R3, R5, R7, R15, R16, R17, R18, R19 closed;
  the row tap pushes an **unstamped** `CalendarPage` over the overview
  (`NavigationHistoryObserver` records only the stamped prefix, so the
  restore stack stays `[calendar, calendarOverview]` — asserted with the
  real observer); `OverviewRobot` rewritten; `05_overview` switches modes
  through the menu. Deviations: the prewarm now runs in year mode only (the
  list has no year to page to); the pushed calendar is matched by route,
  not by caller, so a warm alert tap above an overview pushes too — and a
  tap while the pushed calendar is on top stacked another (fixed in the
  follow-up below); whole-year picks took tile · day · tile because a tile
  with both ends set restarted the span (T10 corrected in the follow-up:
  a tile after the end extends, before the start or inside restarts);
  clearing the search applies at once; five year-mode cases now read the
  nav's text through a scoped helper because the Period row shows the year
  too. Noticed: month mode's old `_buildSectionHeader` overflows by 25 px at
  412 wide with a missed count — 3b replaces it.
- **2026-10-11 — slice 3a follow-up done.** Whole suite `+7449 ~8 -1`.
  The occurrence calendar is pushed under
  `RouteSettings(name: AppNavigator.occurrenceCalendarRouteName)` with no
  arguments (never recorded by the history observer); `toCalendarOccurrence`
  matches the last stamped calendar OR that name, so a second warm tap
  opens on the pushed calendar and stacks nothing; `CalendarPage` gained a
  serve gate (`AppNavigator.servesCalendarOccurrence(route)` — only the last
  live calendar serves the pending request) and an `ensureVisualUpdate()`
  after `_openOccurrence` registers its post-frame callback (a request
  served by the calendar already on top pops nothing, so no frame was
  scheduled). The picker's year tiles: a month after the span's end
  extends, one before the start or inside restarts, none yet → that month.
  Left: `toCalendarQuickAlarm` still matches stamped calendars only (§8).
- **2026-10-11 — slice 3b done (the list body).** Whole suite
  `+7484 ~8 -1` (35 tests; eight cases flipped on purpose).
  `AgendaDayListRowBuilder` (`rows, today, onEntryTap, onEntryEdit,
  onEventTap, captionMaxLines, dayHeaderWithYear, monthCounts,
  singleLineHeaders, singleLineTitles, rowIdentifier, eventRowIdentifier`;
  `build`, `extentKindOf`, `trailingGapOf`, `closesGroupOf`, `readRow`) —
  the day list sheet renders through it with no test body changed;
  `AgendaDayListMonthRow(kept, missed)`, `AgendaDayListCategoryRow`,
  `AgendaDayListEventRow`, `foldAgendaDayListRowsByEvent`;
  `FormLabelValue.wrap`, `FormPickerRow.singleLine`,
  `FormSectionLabel.singleLine`, the stacked caption honouring
  `captionMaxLines` (three primitive changes, all additive, suite extended);
  `_RowExtents` over six kinds (entry kinds measured with and without the
  closing hairline) from an `Offstage` probe keyed on (scaler, locale,
  brightness), the list a `ListView.custom` whose delegate reports the
  **exact** `estimateMaxScrollOffset` under a `Scrollbar(interactive)`;
  `_ListLayout` prefix sums (`offsetOfDay`, `rowAtOffset`, `groupAt`, …);
  the pinned label shown only once the group's own row has scrolled past
  the top; the store query-free (`_scan` passes the allowlist only), a
  matcher per rebuild, filtered buckets per month / year / list,
  `AgendaMonthStore.buildBars` public and `AgendaDayListMonth.entries`;
  the per-event fold; anchoring by the first visible row and the D7
  landing on today for a period / query / order / rows change; month mode
  on the builder with the picked day's ✕ row (the 25 px overflow gone);
  the Scaffold on `pageGround` (the light `rowGroup` was invisible on
  `surface`); flow `23_overview_list` written, not yet run. Benchmark
  (10 000 events): open 624 ms / 8 608 `occursOn`; prewarm 0; Last 12
  months 242 ms / 1 383; a keystroke 137 ms / **0**; a far `jumpTo` **45 ms,
  15 row builds** (13 237 ms and 6 346 in slice 0), the extent exact before
  and after. Left for slice 4: landing also on the first layout after open
  or a switch into List (today it starts at the top).
- **2026-10-11 — slice 4 done (batching, the cap, landing after open, the
  budgets).** Whole suite `+7494 ~8 -1`; the benchmark `+2` under
  `--tags benchmark --run-skipped`. `_resolveGeneration` bumped by every
  `_recompute` (and `dispose`); `_listMore(n)` takes the next n months in
  reading order and keeps going over already-cached months, rebuilds the
  rows over everything listed so far, then `_scheduleListRun` → one
  `Future(() {...})` per `batchMonths`, each checking the token, never
  re-anchoring; the tail as a `FormCaption` slot (`caption` / `capCaption`
  extents measured with the real localized text); the cap counts listed
  entries after the query and Missed only and keeps the day it falls in
  partial; `_landOnOpen` and a landing on a switch into List; landing and
  anchor targets are `double?` and a null target waits for the run that
  brings its row (`_jumpList` retries per run); `forTesting(onStore:)` as
  a seam. Budgets asserted by scan equivalents (`occursOn` calls of one
  `occurrencesInRange` over the same range): This year ≤ 1 scan (8 608),
  a keystroke 0, Last 12 months ≤ 2 (1 383), a far jump ≤ 19 builds (15),
  All time over eight years: 24 months after the frame, 94 after the turns
  (59 ms + 51 ms). Seven test bodies now scroll to the top first (the list
  lands on today). Left: runs keep going under a covering page (slice 5
  pauses them); per-event rows may shift under a kept offset while runs
  land (no re-anchor per run, by the brief); the landed-on-today cases
  assume today is past early January (slice 6 makes them date-safe).
- **2026-10-11 — slice 5 done (the scrubber; runs pause under a cover).**
  Whole suite `+7504 ~8 -1`; the benchmark `+36`. `ListScrubber` in
  `lib/widgets/list_scrubber.dart` (`controller, labelAt, semanticsLabel,
  identifier, onLabelChanged, child`): a 48 dp translucent lane with one
  `VerticalDragGestureRecognizer` and no tap recognizer — the default arena
  favours it (hit-tested first), a tap in the lane reaches the row, a drag
  on the rows scrolls normally; `y / height × maxScrollExtent` → `jumpTo`;
  the bubble on `menuSurface` placed by a `CustomSingleChildLayout`
  (centred on the pointer, 12 dp left of the lane, width capped), fading
  over `scrubberBubbleFade`; six `FormMetrics` names; the page's
  `_groupLabelAt` (month with the year, or the category group), `_click`
  on a label change; `_scheduleListRun` skips while `_covered`, a due run
  returns untouched, `didPopNext` reschedules (both halves proven by
  removing each). Flow 23 gained `expect id:overview-scrubber`, a `drag`
  from the lane to the search row (the agent path only — `drag` throws on
  adb; the calendar pass runs with `ANTA_QA_VIA=agent`) and a `scroll-to`
  back to today's row. Left for slice 6: the thumb fades during a still
  scrub and the scrollbar's track-tap band competes with row taps while
  visible — the scrubber takes the `Scrollbar` over, `thumbVisibility`
  while scrubbing, `interactive: false`.
- **2026-10-11 — slice 6 done (the old UI deleted, tidy).** Whole suite
  `+7498 ~8 -1` (5 `AgendaDayListRowView` cases and 3 `CategoryFilterTile`
  cases gone, 2 scrubber cases added); `dart analyze lib test tool
  test_driver` clean; `overviewEmptyYear` removed from three ARBs,
  `untranslated.txt` `{}`. `AgendaDayListRowView`, `CategoryFilterTile`,
  `_CategoryAvatarCluster` deleted (final grep over `lib test tool
  test_driver`: nothing); `OverviewListMetrics.yearPagerPadding` names
  year mode's 16 / 0 / 16 / 16; `ListScrubber` builds the `Scrollbar`
  (`thumbVisibility` while scrubbing, `interactive: false`) — the thumb
  stays through a held scrub and a press on the old track band reaches
  the row (both proven against the old settings); three landing cases
  re-seeded on a series 60 days before today under Last 12 months so they
  hold on 1 January and 31 December, the far-jump and the four keyboard
  cases scroll to the top first (the list opens landed on today); one
  narration comment removed. Left: the picker's `_rowHeight` literals (6,
  52) predate the rework; the skill references and older records still
  name the deleted widgets — the slice 7 docs pass.
- **2026-10-11 — slice 7, the device pass (qa-runner, Pixel_9_Pro,
  `ANTA_QA_VIA=agent`).** `qa run --fresh --seed` 30.6 s; `qa flows calendar
  --keep-going`: 22 / 24 green. Red: `19_fasting_schedule` (pre-existing —
  its `scroll-to id:fasting-days-off` leaves "Extra fast days" below the
  fold at this 952 dp height, as `docs/alert-surfaces-redesign-roadmap.md`
  already notes; three later flows cascaded from its open sheet and went
  green on a re-run) and `23_overview_list` (two flow defects: step 9
  expected a row the landed-on-today list had not built; an `expect` of an
  event row while the options sheet was open can never pass — a modal
  hides the list from the semantics tree; and the scrubber step used
  `drag`, which the harness cannot scroll any list with). Experiments: a
  real touch on the lane **scrolls instead of scrubbing** on the device
  (the lane wins the arena in widget tests, loses on the emulator) — the
  fix pass's item A; a cold open at phone size lands on today (the earlier
  "opened on September" shot was a kept scroll position after `qa set`,
  withdrawn). `qa errors` clean. Matrix (dark · de · 2.0 and light · ro ·
  1.3, both at 427 dp and 360 dp): no overflow stripe, the options sheet
  right everywhere; findings — the pinned month label drawn twice after a
  scroll (the in-list label still visible under the pinned one), day
  headers squeezed to "M…" beside a long count at 2.0 and the pinned label
  to "OKT…" (the single-line read rows), year-tile names and the ro
  app-bar title ellipsized (pre-existing), the Period menu's German items
  wrapping (by design). The "6 entries · 8 missed" month label is the
  house grammar (kept · missed), not a contradiction.
- **2026-10-11 — slice 7, the independent review (Opus 5.5, read-only).**
  23 findings, 16 confirmed, none losing data or crashing: a "This year"
  pick after year paging not persisted (the equality return before the
  write); a theme / scale / locale change unmounting the list (brightness
  in the extent inputs, a spinner flash, the position lost); the drawer
  path still pushing a stamped calendar; per-event groups' first row with
  square corners; a deferred landing overriding a user's scroll; year mode
  at open ignoring a stored rolling period's first year; `pickRange`'s
  draft start outside its bounds; the tail slot stale on a width change;
  the badge counting Missed only in year mode; New Year with the page open;
  two literals in the range summary; the cap count unformatted; the lane's
  node without actions; every batch run rebuilding all rows (quadratic
  over runs); the SDK's varied-extent sliver walking from index 0 per child
  (the prefix sums unused); the probe rebuilt on every `setState`; missing
  tests (the serve gate's decline half, the drawer path, scan-vs-post-filter
  parity, a wider extent parity). Deferred by the lead: the lane as a
  whole-height target (D6 · A stands; §8). All the rest went to one fix
  pass (A–F in its brief), run after the device pass.
- **2026-10-12 — the fix pass done (A–F).** Whole suite `+7524 ~8 -1`;
  analyzer clean; `untranslated.txt` `{}`; the benchmark `+2` (the far
  jump 14 builds, a fling from the end 74 builds in about 205 ms, the
  extent exact before the jump); `05_overview` and `23_overview_list`
  green on the emulator (92 / 92 steps), `qa errors` clean. **A, the lane
  on the device:** the lane's `RawGestureDetector` factory never set
  `gestureSettings`, so its recognizer waited for `kTouchSlop` (18 dp)
  while the `Scrollable` takes Android's 8 dp from `MediaQuery` and crossed
  its slop first on every real touch (`qa log`: `mq touchSlop=8.0`, the
  lane's `slop=null`, `onDown` but never `onStart`); fixed by
  `recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(context)`
  and pinned by a scrubber case under an 8 dp slop; proven by a native
  swipe landing on Dec 20–21 and a native tap in the lane opening the
  detail sheet. **B:** flow 23's step 9 `scroll-to … --up`, the event-row
  `expect` after the sheet closes, the scrub as `swipe up --from 1208,1800
  --dist 1000 --ms 800 --via native` (physical px; another screen needs its
  own x). **C:** `_ListLayout.pinnedAt` pins a section only once its own
  label's slot lies wholly above the list's top; the band sits above the
  list inside the list's share and yields past
  `OverviewListMetrics.pinnedBandMaxShare` (the overlay was built first and
  dropped: rows' nodes and hit targets ended under it). **D:**
  `AgendaHeaderSlots` — the probe measures the day read row and the month
  label on their locale's widest case (the widest `dayHeaderLabel` with the
  year over twelve months × weekdays 22–28 plus Today / Tomorrow, beside
  "100 entries · 100 missed"; the widest month name with the year) one-line
  and wrapped, and the kind takes the wrapped layout only when wrapping
  changes something (`FormSectionLabel.wrapTrailing`, `capitals`,
  `textStyle` public for the probe); month mode's headers wrap freely like
  the day list's. **E1–E16** all done (persist an unchanged pick; the
  extents keyed on scale · locale · width with the old layout kept and the
  anchor noted before invalidating; the drawer path pushes the named
  route; per-event first rows rounded; a user drag drops a waiting landing;
  `_yearFromPeriod` at open; `pickRange` clamps `initialRange`; the badge
  in list and month modes only; `OverviewPeriod.followingToday` across
  New Year; `FormMetrics.rangeSummaryPadding` / `yearViewBottomGap`;
  `decimalPattern` on the cap count; `onStep` → `onIncrease` /
  `onDecrease`; runs append rows and `_ListLayout.extendedTo` re-sums from
  the old last row, `debugListedEntryVisits` as the seam;
  `_ExactExtentSliver` over a `RenderSliverFixedExtentBoxAdaptor` subclass
  reading the prefix sums, the list a `CustomScrollView`; the probe
  `SizedBox.shrink()` while idle). **F:** the serve gate's decline half with
  a real calendar beneath, the drawer path, scan-vs-post-filter parity.
  Deviations: the band yields (the list shifts by its height at 360 × 780
  × 2.0 with the keyboard up); the day template always carries the year;
  section labels sit on their slot's bottom; a de 2.0 header needing two
  lines sits in a slot sized for the locale's widest. Not verified: New
  Year on a clock, TalkBack's increase / decrease on the device, ro and
  412 × 915 on the device after the pass.
  Slice 0's note stands: no change under
  `lib/` went into
  the tree.
