# Calendar overview — the List mode rework (2026-10-11)

**Status: COMMITTED `f3e0bc8` (2026-10-18, 51 files) — D32 (§2.8, §3.16), the snackbar surface (decision 9 of `docs/ui-language-adoption-roadmap.md` §3) and D33 (§2.9, §3.17); on top of it §2.9 item 17 IMPLEMENTED 2026-10-18, uncommitted — five files: the tune badge inside the glyph on the overview's and the calendar page's bar buttons, which the owner's phone had shown clipped by the 48 dp bar; its gate `dart analyze lib test tool test_driver` clean, `flutter test` `+8077 ~10 -1` (the one failure the known Windows-only `host_devices_test` case); no device pass of its own — the geometry tests pin the painted pill inside the bar on both pages, at text scales 1.0 and 2.0 on the overview, and the count out of the buttons' spoken name (the code review's catch: `ExcludeSemantics`); the owner commits.** The slices' own gate before `f3e0bc8`: `dart analyze lib test tool test_driver` clean, `flutter test` `+8074 ~10 -1`, no ARB touched; one review over both slices (eleven findings, none above low: nine fixed in one pass, two of them record wording); the device pass on the Pixel_9_Pro with the two-theme screenshot set retaken (`ovw2_*`, `ovw3_*`): flows 05, 17, 23 and 25 green, 24 red on its own pre-existing step (a label tap while the "Saved as …" message is still up) and green on the re-run after the fix pass taught it to wait (05 and 23 green again beside it); `qa errors` clean three times.** In the same commit, before it: **D32 (§2.8, §3.16): under the hidden missed display the picked day in Month mode lists its missed occurrences faded with the presence button, and every day with an occurrence is a day to pick; gate on the final tree `dart analyze lib test tool test_driver` clean, `flutter test` `+8044 ~10 -1` (the one failure the known Windows-only `host_devices_test` case), no ARB touched; the review's seven low findings fixed or accepted (§9 ledger); the device pass on the Pixel_9_Pro green — flow 25 72/72 on the agent transport, flows 23 and 05 green from a fresh seed, the owner's scenario by hand on 22 Oct and 10 Nov under Hidden, the de · dark · 2.0 matrix, `qa errors` clean; 12 files, in `f3e0bc8`.** Before it: **COMMITTED `ca3a5e3` (2026-10-17) — D31 (§2.7, §3.15): the day panel's presence button on the overview's day rows, the Mark presence switch retired; gate `dart analyze lib test tool test_driver` clean, `flutter test` `+8036 ~10`, `untranslated.txt` `{}`; the review clean on the code; the device pass green by hand and on flow 05, flows 23 and 24 red on two pre-existing harness items and green past them (§8, §9).** On top of: **IMPLEMENTED 2026-10-14, uncommitted — the third follow-up (§2.5 D19–D25, §3.13, slices 10a–10c) on top of both follow-ups IMPLEMENTED 2026-10-13, uncommitted (§2.3 D12–D14, slices 8a–8c; §2.4 D15–D18, slices 9a–9d), on top of the rework COMMITTED `c4f5697` (2026-10-12).** Together 73 uncommitted files. The third follow-up's gate on the final tree: `dart analyze lib test tool test_driver` clean, `flutter test` `+7654 ~9 -1` (the known Windows-only `host_devices_test` case; the one new skip is the reproduction of the page's stale-semantics case, §8), no ARB touched; `qa flows calendar` on the Pixel_9_Pro: 00–18 green, 19 red as before, 20–24 green run one by one after it (19 leaves its dialog open, so in a one-shot directory run every flow after it fails at its first step — a harness hazard that predates this slice), 23 green from a fresh seed (its first two runs, on data the earlier flows had mutated, read Gym 5 · Strength 9 against the seed's Gym 4 · Strength 8; a six-point bisect of its own steps from a fresh seed read 13 entries at every point); the matrix: en 1.0 light — twelve tiles on screen at 427 and at 360 wide, the nav one line, the title's menu on screen, Categories the sheet's first row, the search row summoned and dismissed; de 2.0 dark — both title menus whole with the ✓, "Kategorien" whole beside "Alle", "Jahr · Monat · Liste" and the search button on one row (the tiles' truncated names at 2.0 are Tier 3's §8 item; what looked like the count clipping the title at 360 is the harness overlay's tag drawn above the count's rect — the two rects abut); the behaviour check (Last 90 days from Year lands in List, Today disabled as the home); `qa errors` clean after the flows and the matrix. Not verified on a device: TalkBack's geometry after a title-menu pick that switches mode (§8, the observer) and the keyboard fold with the Search row open under a real keyboard. The owner reviews and commits; the next session that opens this record corrects this line from `git log`. Together 71 uncommitted files (new: `lib/controllers/event_sheets_flow.dart`, `lib/utils/sheet_guard.dart`, `lib/models/overview_view.dart`, `lib/database/tables/overview_views_table.dart`, `lib/database/daos/overview_view_dao.dart` + `.g.dart`, `lib/services/overview_view_service.dart`, `lib/widgets/overview_view_sheet.dart`, four test suites, two robots, a test helper, flow 24). The lead's own final gate on the final tree: `dart analyze lib test tool test_driver` clean, the whole `flutter test` `+7638 ~8 -1` (7536 after the first follow-up; the one failure the known Windows-only `host_devices_test` case), `untranslated.txt` `{}`, the schema at v41 and the upgrade run on the emulator's real v40 database with nothing in `qa errors`, `qa flows calendar` 24 / 25 (`19_fasting_schedule` red as before; `23_overview_list` and `24_overview_views` green end to end on the final tree), `qa errors` clean after every run. Not verified on a device: the chip row's fold under a real keyboard, TalkBack's reading of the marking hint, the long press on Android, 412 × 915 (the wrapper offers 360 × 800 and the default only). The owner reviews and commits; the next session that opens this record corrects this line from `git log`. The first follow-up: 19 files (17 changed, 2 new), `dart analyze lib test tool test_driver` clean, the whole `flutter test` `+7536 ~8 -1` on the lead's own run (the one failure the known Windows-only `host_devices_test` case), `untranslated.txt` `{}` (no ARB changed), `qa flows calendar` 23 / 24 on the Pixel_9_Pro emulator (`19_fasting_schedule` red as before; `05_overview` and `23_overview_list` green), `qa errors` clean after the flows and after the matrix; the chip row's fold under a real keyboard rests on widget tests (the harness cannot raise one). The owner reviews and commits; the next session that opens this record corrects this line from `git log`. The rework: slices 0–7 and the fix pass, 64 files: `dart analyze lib test tool test_driver` clean, the whole `flutter test` `+7524 ~8 -1` (7317 before the rework; the one failure the known Windows-only `host_devices_test` case), `untranslated.txt` `{}`, the benchmark green under `--tags benchmark --run-skipped`, `qa flows calendar` 23 / 24 with `23_overview_list` green end to end on the Pixel_9_Pro emulator (the one red, `19_fasting_schedule`, predates this rework), `qa errors` clean. D1–D11 were delegated to the lead by the owner on 2026-10-11 ("take any decisions using fable and implement using whatever you see fit"); the recommended option (A) stands for each. The owner committed it as `c4f5697` on 2026-10-12; their first use on the phone (2026-10-13) raised three points, answered in §2.3 (D12–D14, A each) and built as §6's slices 8a–8c against §3.11. 2026-10-15 — §2.6 D26–D30 decided (the years scroll, §3.14); slices 11–12 and the 12b fix pass IMPLEMENTED 2026-10-15, uncommitted; device pass 2026-10-15 green for the rework (24/25 flows, 19 red as before; Year mode by hand green; 360-wide not run), owner commit owed.
Written on a clean tree at `a4f783a` from a read of the overview page, the
store, the index, the rows, the Tier 3 day list and the scan, plus one
independent read-only review of the list mode's performance and behaviour
(Opus 5.5, 2026-10-11; its findings are §1.3). The mock is
**"Overview List Mock"** — https://claude.ai/artifact/GpAs4MTkY1Vc4gY9wyBhnq —
one board of the list (light at rest, dark while scrubbing), one of the
period picker, strips of the view menu, the options sheet and the "Per
event" rows, an audit of every component against the language, and the
decisions of §2 as the owner will answer them. Where the mock and this
record disagree, **this record wins**. Line numbers in §5 are from
`a4f783a`; re-grep every one before editing. This is also Tier 4's overview
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

### 2.3 Asked of the owner on 2026-10-13, after the first use on the phone — answered the same day: A, A, A

The owner's three points, and what the tree said. "Where is the beautiful
mode where we could see all the twelve months?" — year mode exists, but
D8 · A moved the Year · Month · List control into the title menu and the mode
persists, so a page left in List, or dropped into Month by a tile tap, shows
no way back to the tiles. "The period is not even usable, it is disabled" —
by §3.2 the Period row is disabled in month mode, and in year mode a pick
only pages the year. "When I select an event and tap back I am instantly on
the calendar even though I was in the overview" — D1 · A pushes a calendar
with the detail sheet, so one back closes the sheet onto that calendar and
only a second returns to the list. The overview already reads the app-wide
`CalendarBloc` (`calendar_overview_page.dart:67`, `:296`), so D1 · B is one
slice, not the rework §8 feared.

| D | Question | Options |
| --- | --- | --- |
| D12 (supersedes D8) | Where the mode switch lives | **A** a chip row Year · Month · List on the page above the filter group — the day list sheet's pattern, one tap, always visible; the title menu's presentations group goes · B the chip row and the menu group both · C the menu only, the mode no longer persisted so every visit opens on the tiles |
| D13 (supersedes D11's month-mode clause) | The Period row outside list mode | **A** enabled in every mode; a pick switches to List mode on that period (a period is the list's unit); This year picked in year mode pages to this year · B enabled, and the mode stays: year mode jumps to the span's first year, month mode to its first month · C the row only in List mode |
| D14 (supersedes D1) | A row tap, and where back lands | **A** the detail sheet opens over the list, no calendar: back closes it onto the row; the calendar's detail loop becomes a shared controller (D1 · B) · B keep the push, closing the sheet pops the calendar too · C leave it, two backs |

Lesson for the record: a delegated "two taps instead of a band" hid the
page's primary control. A switch the owner looks at on every visit belongs
on the page; the menu is for what is set once.

### 2.4 Asked of the owner on 2026-10-13, second round — "decide each with Fable first": D15–D18, decided by the lead, the recommended option (A) stands

The owner took three items out of §8 (the stepping nav, per-category totals,
saved views) and added one (presence from the rows), each with its open
sub-decisions. Options lettered, the recommended one first with its reason;
the owner may overrule any line.

| D | Question | Options |
| --- | --- | --- |
| D15 | A stepping nav in List mode (§8's D11 · B) | **A** the `AgendaPeriodNav` under the filter group in List mode too, as Year and Month modes already have it — ◄ the period's label with the count as its subtitle, the Today slot, ► — so the three modes share one band and nothing foreign is added; the count caption moves into the nav's subtitle · B chevrons on the Period row itself (a new row shape) · C no nav, the Period menu alone |
| D15a | What a step does to a rolling preset | **A** a step turns it into a custom span of the same length, shifted by its own length (Last 90 days ◄ → the ninety days before, shown as "Apr 17 – Jul 15, 2026", the Period row reading the span with Custom range checked); This year steps to the neighbouring year; a custom span shifts by its own width; All time does not step (both chevrons disabled) — what a stepped window is, said honestly · B a rolling period with a step count (a new period kind, persisted) · C rolling presets do not step |
| D15b | The Today slot | **A** back to the period as picked ("home": the last Period-row pick or the persisted one; stepping and Year-mode paging never move it), enabled while the shown period differs from it; its tooltip names the home period · B always "This year" · C re-anchor a span to end today |
| D15c | Persistence of a step | **A** none: a step never writes the period key (the home stays persisted; D4's rule for custom spans is untouched), so a closed app reopens on the pick, not on a look · B persist the stepped span |
| D16 | Per-category totals | **A** a two-line caption slot under the nav, in every mode, "Gym 41 · Run 12 · Yoga 3 · +2 more" in catalog order over what the mode lists — kept entries, or the missed ones while Missed only narrows the list — three named then "+N more" (`categoriesMore`), the text changing and the slot never · B list mode only · C all categories, wrapping and ellipsized |
| D16a | Missed counts | **A** not beside the kept ones: the nav's count already says how many were missed in all, and under Missed only the totals are the missed ones per category · B both per category ("Gym 41 (3)") |
| D17 | Saved views — persistence | **A** a Drift table `overview_views` (v41) byte-for-byte the presets table's shape (name, one JSON payload, sort order, the v29 CRDT block, soft delete), a DAO and an `OverviewViewService` mirroring `FilterPresetDao` / `FilterPresetService` (cache, the 50 cap, create / update / delete / reorder / matching / export / import, the lifecycle reset), the backup key `overviewViews` added the way `calendarFilterPresets` was (additive, absent leaves the table, the archive version unbumped) — the owner's "FilterPresetService shape" taken literally, with sync and backup parity for free · B a JSON list in one settings key · C rows in `calendar_filter_presets` with a kind column |
| D17a | Where the entry point sits | **A** a bar button between the tune button and the ⋮ (`bookmarks_outlined`, "Saved views", `overview-views-open`, `isSelected` while the shown list equals a saved view) — the calendar bar's own pattern for its saved filters, two taps to any view, no fourth row in the filter group · B a row in the filter group · C the ⋮ |
| D17b | A custom span in a view | **A** allowed: a view is the one place a fixed span earns its keep ("Q1 2026 · Gym · per event"); the view's JSON spells the period out, the settings key's codec is untouched · B presets and This year only |
| D17c | What a view holds and does | **A** the period, Order, Rows, Missed only and the categories allowlist — not the query, not the mode; applying one switches to List mode, sets and persists each part as a pick would (a custom span stays session-only per D4), leaves the query as typed, lands per D7 · B the mode and the query too |
| D18 | Presence from the rows | **A** (the owner's recommendation) a session-only Mark presence switch in the options sheet: while on, a tap on an entry row in List (every-occurrence rows) or Month mode toggles the day's presence through `SetOccurrencePresence` — the panel's quick-toggle semantics, one tap per day, the row's dimming and the header's counts as feedback, a long press still opening the detail sheet; no row geometry changes; the tune button reads selected while the switch is on · B a Present / Missed pair in the row's trailing slot · C the detail sheet only (D14) |

### 2.5 Asked of the owner on 2026-10-14, after the chips' first days — answered "Okay, you may start implementation": the recommended option (A) stands for D19–D25

The owner's words: the chips make switching seamless, but Year mode is "a
bit too crowded" and they want to "focus on that year"; "the datepicker is
too large for the yearly picker" — the months should be seen better; the
date picker and the period picker should be "one so we don't waste so much
space"; Month mode "looks okay" but could lose a bit of space too. What the
tree says (en, text 1.0, 360 × 780, a 24 dp status bar): the chrome above
the first tile is 404 dp — the status bar 24, the bar 48, the chip row 56
(`bodyTop` + `chipTapTarget`), the filter group 152 (`bodyTop` + three
48 dp rows), `belowFilters` 8, the nav 72 (a two-line title box of 48 in
its 4 dp of ink padding, the 16 dp count, the row's 4 dp bottom padding),
the totals 44 (`groupCaptionPadding`'s 8 over two 18 dp lines) — while
the twelve tiles need 504 (four rows of `YearMonthTile.gridDelegate`'s 116
with three 8 dp gaps and the pager's 16 dp bottom inset), so the fourth
row of months is below the fold; on the 952 dp emulator it fits with 44 dp
to spare, which is why the pass never showed it. The title box is two
lines in every mode because slice 9a measures the List nav's span
templates ("Dec 28, 2025 – Dec 28, 2026" at `titleMedium` 600 in the
174 px the two chevrons, the Today slot and the drop-down glyph leave) into
all three navs, so "2026" sits in a 48 dp box. The Period row and the nav's
title both answer "which period". The mock: **"Overview mock"** —
https://claude.ai/artifact/GSMUfABr93vsP1cyknoGsp — today's Year beside
the proposed Year, Month and List, light and dark, List with the search
open, the title's menu and the options sheet as insets.

| D | Question | Options |
| --- | --- | --- |
| D19 (supersedes D11's row and D15's title) | The period control | **A** the nav's title opens the Period menu — This year · Last 12 months · Last 90 days · All time · Custom range…, the row's items and ids unchanged — in every mode, and the Period row goes; ◄ ► page years, months or step the list as today; the Today slot stays home. One control answers "which period", 48 dp back in every mode · B keep both, as today · C the Period row stays and the nav's title loses its tap |
| D20 (supersedes slice 9a's one height) | The nav's height | **A** the title box is measured per mode — Year over the year, Month over the twelve month titles (the day list's month nav), List over the span templates — so Year and Month are one line at 1.0 and only a List span wraps; a mode switch may change the band's height (the body cross-fades under the chips, nothing is under a finger), inside a mode nothing moves · B one height across the three modes |
| D21 | Search | **A** a search button at the end of the chip row reveals the Search row above the band and focuses it; it reads selected while a query is set; the row's ✕ clears, the button again closes and clears. Search is a List-mode tool most days, the button is where the thumb already is, and the bar keeps its three actions · B the Search row always on the page · C a fourth bar action |
| D22 | Categories | **A** the first row of the options sheet behind the tune button ("Categories · All ›", the badge counts it as a restriction); the totals line reads the chosen categories back on the page. The calendar page keeps its categories behind its filter button the same way · B the row stays on the page, alone in its group (the tiles still fit, with 6 dp to spare) |
| D23 (supersedes D16's two lines) | The totals | **A** one line: three names then "+N more", ellipsized past the width · B two lines, as today · C none in Year mode, where every tile carries its count |
| D24 | The mode switch | **A** the chips stay, the day list sheet's twin, now with the search button at their end · B a `SegmentedButton`, the widget the Dates sheet and the panel already switch with (40 dp, full width, 8 dp back) · C a `TabBar` flush under the bar, swipeable; new to the app |
| D25 | The jump picker | **A** `MonthYearPickerSheet` leaves the overview: ◄ ► page, the Year chip's tiles are the month jump, Custom range…'s year view picks whole months; the day list keeps its own · B a "Jump to…" item at the end of the menu |

With every A, Year mode's chrome is 206 dp above the first tile (the
status bar, the bar, the chip row, a 52 dp one-line nav, a 26 dp totals
line) and the twelve months fit a 780 dp screen with 70 dp to spare; Month
mode's grid starts at 206 too (404 today); List mode's pinned label at 226
(its nav keeps two lines for a span).

### 2.6 Asked of the owner on 2026-10-15 — answered "Perfect, choose for me and make it really performant so we can have it as a flagship feature": the recommended option (A) stands for D26–D30

The owner's words: with the recent changes "the overview mode looks
amazing"; they want "an extreme functionality": "to see multiple years in
the year [mode]", "months separated by years in a continuous scroll or
something that is really performant and clean", and asked for the
recommended mock, the performance and the design "in the best way". What
the tree says: Year mode is `AgendaYearPager`, a `PageView.builder` over
`EventAgenda.yearBoundsOf` (one year per page, swiped or stepped by the
chevrons, 260 ms), whose builder resolves a year's tallies synchronously
(`_tilesFor` → `AgendaMonthStore.ensureTallies`, the one documented
"never in build" exception) and prewarms the two neighbouring years 250 ms
after a page settles; the twelve tiles need 488 dp (four rows of
`YearMonthTile.gridDelegate`'s 116 with three 8 dp gaps) under a 206 dp
chrome. The mock: **"Overview years mock"** —
https://claude.ai/artifact/HW9tTTqBo1xanRoRr29PUb — four frames: light and
dark at rest opened on this year, light mid-scrub the frame after landing
on 2024 with 2025 not yet resolved, dark at text scale 2.0; under the
board the decisions, the performance plan, the must-not-change list and
the numbers. The lead chose on the owner's word; every A below is the
decision.

| D | Question | Options |
| --- | --- | --- |
| D26 | The years' order | **A** chronological downward — earlier years above, later below — and the scroll opens with today's year's header at the top; the twelve tiles already read January → December downward, so December sits right above the next January and the whole scroll is one timeline, in the direction of the list's default Order (oldest first) · B newest at the top, scrolling down walks into history; months still run downward inside a year, so the direction flips at every header |
| D27 | The year header | **A** a flat row that scrolls with its tiles: the year at `OverviewListMetrics.yearHeaderFontSize` 22 / 500 `onSurface` on the tiles' left edge, the year's count (`agendaDayListCountLabel`) at the right in the caption role 13 / 400 `onSurfaceVariant`, shrinking to one line and never wrapping, blank while the year is unresolved; `yearHeaderHeight` 48 at 1.0, measured once per text scale as the nav measures its title; no hairline, no box; the nav's title is the live year, so nothing pins · B a pinned header per year (`SliverPersistentHeader`) — it repeats what the nav's title shows and costs a persistent header per year |
| D28 | Which years the scroll holds | **A** from the first event year to next year: `yearBoundsOf`'s span with the open-ended ceiling replaced by today's year + 1 — a bounded series or a pinned date past that still extends the end, today is always inside; an open-ended weekly series reaches 2100 today, which would hand most of a scrubber lane to empty decades, and the overview is the log, the future is the agenda's (All time's own words, §2); the day list sheet's pager keeps the full bounds · B keep `yearBoundsOf` exactly as the pager has it — free to scroll thanks to fixed extents, but every year that matters sits in the lane's top tenth |
| D29 | The scrubber | **A** the list's `ListScrubber` over the scroll, the year in its bubble, ±1 year on a step, shown when the scroll holds two or more years; a one-year scroll has nothing to scrub and keeps its right tile column clear · B always shown · C never — chevrons only, a decade is ten taps |
| D30 | A year not yet resolved | **A** its section renders at once — month names, blank counts, every day at the unmarked alpha — and fills when its run completes, a frame or two later; same geometry, no spinner, no shimmer, nothing moves · B a shimmer placeholder — motion for a state that lasts one frame |

With every A a 360 × 780 phone shows today's year whole and the next
year's header at the bottom edge (552 dp per year: 48 + 488 + 16); a
century of years is one fixed-extent sliver whose far sections cost
nothing until they are seen.

### 2.7 The owner's own ask on 2026-10-17 — the day panel's presence button on the row: D31, the switch retired

The owner's words (translated): "when we tap the filter at the top right,
List options opens, and Mark presence is always disabled — it is never on.
Can't we mark presence from Month view, for example: tap the day and have
a presence toggle button in the event's card, like the normal calendar when
that option [the event's presence tracking] is active." What the tree
said: the switch was live only in Month mode or in List mode with
every-occurrence rows, and never while the missed display is hidden; the
overview lands in Year mode (the persisted default), where the switch is
disabled by design — so the first visit, and every visit that opened the
sheet from Year mode, found it dead. The mode-gated switch was the D18 · A
trade (a tap that marks, no row geometry change) and it failed on
discoverability: a control that changes what another control does, kept
in a sheet, disabled where the page opens.

| # | Question | Options · **decision** |
| --- | --- | --- |
| D31 | Presence from the overview's rows, revisited | **A** (the owner's ask) the day panel's control on the row — a `FormTrailingButton` in the trailing slot of every day row whose event tracks presence (`EventPresence.appliesTo`): `event_busy` while present, `event_available` while missed, the day panel's tooltips, a press writing the opposite explicit status through `EventSheetsFlow.setOccurrencePresence`; the row's tap keeps opening the detail sheet; the Mark presence switch, the tap-to-mark mode, the long press and the row hint retired; offered in Month mode and in List mode's every-occurrence rows (a per-event row has no day), and not while the missed display is hidden (the review-2 rule: a mark would take its row away with nothing on the overview left to undo it) · B keep the switch and draw the button only while it is on (two controls for one act, and the switch stays dead where the page lands) · C the button under the hidden display too (the first mark would read as a delete — the day panel's own reason for sparing missed rows) |

### 2.8 The owner's screenshot later on 2026-10-17 — the picked day under the hidden missed display: D32

The owner's words (translated): "for example in Month view I have a gym
event, but I can't mark it present for tomorrow. Also, the dedicated
presence button doesn't appear for me." The screenshot: October 2026 in
Month mode on the phone, one daily "Gym Presence 2026" event, "14 entries"
and "Gym 14" — exactly the days with a bar; days 1, 5 and 10 and every
day after today (the 17th) without one; the 16th picked, its one row
without a button. What the tree said: the phone runs the missed display
on `hidden`. Under it `AgendaListView.eventDayEntries` drops every missed
or assumed-absent occurrence before it becomes a row, so a future day of
a daily assume-absent event has no entry at all; the grid's
`enabledDayPredicate` (`hasEntry`) leaves such a day inert, so tomorrow
cannot even be picked; and D31's `_presenceOffered` (`!_missedHidden`)
withholds the button from the rows that do exist. D31's rule protected
the whole-month rows — a mark missed would take a row away with nothing
on the overview left to undo it — and for the owner's setting it leaves
the overview unable to mark anything. The calendar page already answers
this case: `DaySummaryPanel` lists missed occurrences dimmed but always,
even under `hidden`, because the panel is where they are marked and
un-marked.

| # | Question | Options · **decision** |
| --- | --- | --- |
| D32 | The picked day under the hidden missed display | **A** (the owner's yes) the picked day in Month mode is the day panel's twin: its rows come from a one-day scan over the loaded events converted with `faded`, never from the month's bucket, so a hidden missed or assumed-absent occurrence is listed faded with "Mark as present"; the presence button is offered on the picked day's rows under every display; a mark missed fades the row in place instead of removing it; the grid makes every day with any occurrence in the allowlist tappable and full-strength (a per-month occurrence mask the page folds from the scan), a day with none stays inert and faded; the whole-month rows, the bars, the nav's count, the totals, Year mode and List mode are untouched (`hidden` keeps dropping missed occurrences there, and their rows keep no button) · B switch the setting to `faded` — zero code, and every future day of a daily assume-absent event fades across the whole app, which is why `hidden` is the owner's setting · C the button under `hidden` on every overview row (D31's option C) — on the whole-month rows the first mark missed still reads as a delete |

### 2.9 The owner's third ask on 2026-10-17 — "white snackbars and many things not in conformity with the design": the conformity pass, D33

The owner's words (translated): "also, about the overview mode: I noticed
there are sometimes white snackbars and many things that are not in
conformity with the design — please correct them." What the tree said:
(1) both of the app's snackbars paint `inverseSurface`, `#E6E0E9` in the
dark theme — a near-white card over a dark page; that is app-wide and is
settled as decision 9 of `docs/ui-language-adoption-roadmap.md` §3 (one
`snackBarTheme` on the popup menu's surface, read by both bars). (2) A
read-only audit of the overview and the surfaces it opens against the
`ui-language` rulebook (one reviewer, 2026-10-17) found twenty deviations,
and a screenshot set of every overview surface in both themes confirmed
the visible ones: in the light theme the bar is white over a grey page and
the year tiles are darker than their ground; the Period menu opens at the
screen's left edge instead of under the title; the nav's count line is
11 px; the name dialog is hand-built beside the app's one dialog layer
(whose own outlined field is the master record's inventory item next to
its decision 2 — not this pass's). The dispositions are the lead's, on the
owner's "correct them".

| # | Question | Options · **decision** |
| --- | --- | --- |
| D33 | What the conformity pass corrects | **A** every rule breach the audit found and the screenshots confirmed (the list below, "fixed"), nothing that a record decided or that is a judgement call (the list below, "left", for the owner) · B everything the audit named, judgement calls included (the lane narrowed, the totals centred, the action menus rebuilt on a new primitive) — widens the owner's ask into design changes nobody asked for · C the snackbar alone — leaves what the owner called "many things" |

**Fixed (D33 · A).**

1. The bar paints `surface` over a `pageGround` page (`calendar_overview_page.dart`, the `AppBar` vs the `Scaffold`): in the light theme a white bar and status strip over a grey page → `pageGround` with `surfaceTintColor` transparent (`app_colors.dart`: `pageGround` is "what its bars sit on").
2. The bar is 56 dp with 24 px glyphs, not `AppBarMetrics` (48 / 22): no `toolbarHeight`, default icon sizes → `toolbarHeight: AppBarMetrics.toolbarHeight`, the leading glyph and the three actions at `AppBarMetrics.glyphSize`; the calendar page's bar takes the same two lines so switching pages through the title menu moves nothing (§2.5's 206 dp sum above the first tile becomes 198).
3. `AgendaPeriodNav`: the count line is `labelSmall` 11 / 500 → the caption role, 13 / 400 `onSurfaceVariant` (`FormMetrics.captionSize`); the title is `titleMedium` at w600, a weight no role has → 17 / 500 (`FormMetrics.headerTitleSize`); the title box and the subtitle height re-measure through the templates, so nothing shifts between modes. The day list sheet's navs follow — one widget.
4. The nav title, a menu control, has a `Tooltip` and no Android hint → `Semantics(button: true, hint:)` as `CalendarViewMenu._hintFor` does; TalkBack then says it opens the period choice.
5. The nav's literals — the 48 slot, the title ink's radius 8, two paddings, the 24 px chevrons and Today glyph → named in `FormMetrics` (`trailingButtonSize`, `chipRadius`, `periodNav*`); values unchanged.
6. The Period menu opens at the screen's left edge: `formMenuPosition` pins the menu's right edge to the anchor's right — a row's rule — and a centred title's right edge leaves no room for a 220 dp menu, so it is clamped to the left → `showFormMenu` takes an alignment (`FormMenuAlignment.end` for rows, the default; `center` for a centred anchor), the menu centred under the title and kept inside the screen's margins.
7. Year tiles paint the token `surfaceContainerHigh` (`agenda_year_grid.dart`), not a role: in the light theme a darker tile on the grey ground, inverting "the page ground is one tone under the row groups" that Month's and List's cards follow → `rowGroup`; every host of `YearMonthTile` (the overview, the day list sheet, the Dates sheet's year view) is checked to pass a background one tone off its own ground.
8. `YearMonthTile` literals — radius 12, padding 10, gap 8, the delegate's 132 / 116 / 8 → named in `OverviewListMetrics` / `FormMetrics`; its two text styles stay (the tile is a calendar idiom, Tier 3) but their sizes are named.
9. The views sheet's ✕ carries `cancel` on a live-apply sheet → `close`; the saved filters sheet, its twin, the same.
10. The views sheet's and the saved filters sheet's header hairline from a raw scroll-controller listener → `FormHeaderHairline` (a delete that shortens the body left the hairline on).
11. The name dialog (`FilterPresetNameDialog`: `showDialog` + a hand-built `AlertDialog`, an outlined `TextField`, a literal 60, a grey `errorText`) → `AppDialogs.textInput`, extended with `selectAll`, `allowEmpty: false` and a soft `warningFor` line on the counter's row in the counter's own metrics and the error colour (so the dialog does not grow when it appears); the limit from the one named constant the views and presets share (`kSavedListNameMaxLength`). The dialog layer's own outlined field stays what it is (below, "left"). The filters record's 2026-09-27 "kept unchanged" was a scope choice, not a design one.
12. The views sheet's ⋮ glyph `more_vert_rounded` → `more_vert` (header record D14: on every platform).
13. The options sheet: Missed only stays live in Year mode where it changes nothing → disabled as Order and Rows are; the Categories value `singleLine` (an ellipsis §3.2 item 2 forbids) → the two-line clamp, the sheet wrapped in `FormSheetSemanticsRefresh` for the resize the ellipsis was avoiding; the header gets its `scrolled:` hairline.
14. The chip row's search button is a default `IconButton` (24 px glyph) → the trailing control's 48 × 48 box and 20 px glyph (`FormTrailingButton`'s sizing), `isSelected` kept.
15. `AgendaMonthGrid` literals (the 4 dp side padding, the marker's 4 dp) → named.
16. `OverlaySnackbar`'s ✕ had no label → the close tooltip (the snackbar slice).
17. (2026-10-18, the owner's phone the morning after) The tune button's count badge was clipped at the top: `Badge.count` wrapped the whole 48 dp button and Material places a labelled badge 4 dp above its child, which the 56 dp bar had absorbed and the 48 dp bar clips → the badge rides the glyph inside the button (`IconButton(icon: ExcludeSemantics(child: Badge.count(child: Icon)))`, Material's own placement), on the overview's tune button and the calendar page's filter button alike. The `ExcludeSemantics` is the code review's catch (2026-10-18, ten angles over this diff): inside the button's merged node the count became its label, and Android 9+ announces a label instead of the tooltip, so TalkBack would have read the button as a bare "1" — the count stays silent, since a spoken count needs words of its own (three strings, the owner's call). The overview's page suite measures the painted pill, not its text, inside the 48 dp bar at text scale 1.0 (9 dp of slack) and 2.0 (about 1 dp — the pill grows with the label, and past about 2.1× linear it would clip again, which Android's non-linear 200 % never reaches), and pins that the button's semantics label is not the count. The calendar page's header suite pins the same for its filter button (a hidden category through `ChangeCalendarFilters`, the pill inside the bar, the node's label not the count). The agenda search row's count badge (`upcoming_agenda_view.dart`) still wraps its button: in no bar, so unclipped, though at 2.0 its pill runs past the panel's edge.

**Left for the owner** (a recorded decision or a judgement call): the scrubber lane over the rows' presence button since D31 (TalkBack finds the lane first over 32 of the button's 48 dp, and a vertical drag that starts on the button scrubs — record §8's lane item; the choices are a lane narrowed to the gutter and the thumb, or the presence slot inset in List mode); the totals caption left-aligned under a centred nav (D23 set the slot, not its alignment); the views sheet's row menu and the bar's overflow on `showMenu` + `PopupMenuItem` (the language has no action-menu primitive; header D7); the Period menu's 220 floor beside the 236 header menus; the Dates sheet's Month | Year `SegmentedButton` (Tier 1 D11 kept it unchanged — the one stock control left on the overview's path); "Nothing in this period" under a live search, the search button's tooltip while it is open, and the overlay bar covering a one-row sheet (master record §8); the dialog layer's own field — `AppDialogs.textInput` draws an outlined `TextField` under a floating label, so the name dialog now looks like every other text prompt in the app, and the layer's look is the master record's inventory item beside its decision 2; inside an `AppBar` a bar button's `isSelected` has no visible effect (the ambient `IconTheme` colour overrides the selected state — pre-existing, the views and tune buttons included; the tune badge is what shows). Seen on the emulator only: a light system navigation bar in the dark theme (the owner's phone draws it dark; app-wide, not the overview's). From the code review of item 17, pre-existing and outside this pass: the browser bar's overflow badge (`folder_overflow_menu.dart`, the bar's last action) reaches 7–8 dp past the bar's right edge at text scale 2.0 and is clipped there — a trailing gutter on every bar (an `actionsPadding` end inset named in `AppBarMetrics`) or a cap on the badge label's text scale would settle it app-wide; the agenda search row's badge (above) would take the glyph placement with care for its `selectedIcon`; a spoken count on the badged buttons needs three strings.

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
   **tune button** — `AutomationId(overview-options-open)` over
   `IconButton(tooltip: overviewListOptions, isSelected: restrictions > 0,
   iconSize: AppBarMetrics.glyphSize, icon: ExcludeSemantics(Badge.count(
   count: restrictions, isLabelVisible: restrictions > 0, child:
   Icon(tune_rounded))))` — the badge on the glyph inside the button since
   §2.9 item 17 (2026-10-18; around the button it was clipped by the 48 dp
   bar), the calendar bar's filter button the same shape (`calendar_page.dart`),
   the agenda's tune still the older badge-around-the-button shape
   (`upcoming_agenda_view.dart`, in no bar);
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
`overview-event-<eventId>`; `overviewRowPresence(eventId, day)` →
`overview-row-presence-<eventId>-<yyyy-MM-dd>` (2026-10-17, §3.15;
`overview-mark-presence` retired with it). `calendar-overview-open`, `calendar-view-menu`,
`date-picker-save` / `-cancel` / `-today` stay.

### 3.11 The follow-up (D12–D14, 2026-10-13)

**The mode chips (D12 · A).** Under the bar, above the filter group:
`FormChipRow(indented: false, chips: [for mode in Year · Month · List:
FormChip(label: dayListModeYear / dayListModeMonth / dayListModeList,
selected: _mode == mode, onTap: () => _selectMode(mode), identifier:
overview-view-year / -month / -list)])` — the day list sheet's row
(`agenda_day_list_sheet.dart:544–554`), in the page's order (the page opens
on Year). The row sits at `FormMetrics.bodyTop` under the bar; the filter
group keeps its `FormMetrics.bodyTop` above it. Nothing else moves: the
count caption, the gap and the body follow the group as today.
`CalendarViewMenu` loses `presentation`, `onPresentationSelected` and
`_PresentationChoice`; the overview passes `page` and `onPageSelected` only,
as the calendar does. The ids keep their names (never renamed); the robot's
`selectMode` taps the chip and `currentMode` reads the selected one. Flows
`05_overview` and `23_overview_list` switch modes by tapping the chip, with
no `tap id:calendar-view-menu` before it.

**The Period row in every mode (D13 · A).** `onSelected: _selectPeriod`
whatever the mode. `_selectPeriod(choice)`: in list mode as today; in year
mode `thisYear` as today (`_setPeriod(OverviewYearPeriod(today.year))` —
the pager lands on this year, the choice persists); every other case — any
other choice in year mode, every choice in month mode — resolves the period
first (the picker for `custom`; a cancel changes nothing, the mode
included), then in one `setState`: `_mode = list`, `_period = period`,
`_year = _firstYearOf(period)`, `_selectedDay = null`, `_recompute()`; then
`_land()`, `_schedulePrewarm()`, and both the mode and the period persist
(`_persistMode`, `_persistPeriod`). The row's value outside list mode keeps
reading the shown year (`_shownPeriod`); the options sheet's Order and Rows
rows follow `listMode` as today.

**The detail sheet over the list (D14 · A).**
`lib/controllers/event_sheets_flow.dart`: `EventSheetsFlow`, the calendar
page's trip through an event's sheets moved whole — `_detailSheetLoop`
(`calendar_page.dart:874–1012`), `_pendingAfterSave`, `_occurrenceSurvives`,
`_quickEditDescription`, `_skipOccurrence`, `_editExplicitDates`,
`_editorSheet` with the save path it runs (`_dispatchOccurrenceResult`,
`_dispatchSkipResult`, `_afterAlertsSaved`, `_checkAlertPermissions`),
`_setOccurrencePresence`, `_resolveNoteTitle`, `_openLinkedNote`,
`_openWikiLink` — behaviour-preserving: every write still goes through
`context.read<CalendarBloc>()`, every sheet opens on the caller's context,
and the suites that drive the page's trip (`calendar_keep_notice_test`,
`event_detail_*_test`, `calendar_page_jump_test`, the editor suites) pass
unchanged. The page's own editor opens (`_openEditorSheet`, the template
quick add) call the flow's editor the way the trip does; the page keeps the
FAB, the panel, the filters, the quick alarm and the templates.
`SheetGuard` (`calendar_page.dart:134–147`) moves to
`lib/utils/sheet_guard.dart`. The flow takes what the loop read off the
page: a `SheetGuard`, `CalendarAppearance Function()`,
`MarkdownColorPalette Function()` and `int Function() keepsHeard` (read at a
trip's start and after each step, exactly as `_keepsHeard` is today). The
calendar page keeps `_sheetGuard`, `_keepsHeard`, `_serveKeepNotice`,
`_eventsBeforeKeep`, `_initialTargetDone` and `_openOccurrence` (the initial
target and the pending request) and calls the flow where it called
`_openDetailSheet` (`calendar_page.dart:710`, `:869`, `:1454`). The overview
owns a `SheetGuard`, a `_keepsHeard` served by an `AlertKeepNotice.instance`
listener of its own (registered as the calendar page's is,
`calendar_page.dart:479–484`: count, and a `LoadCalendarEvents` while the
notice is still pending — **never `take()`** (the review's finding 1, 2026-10-13):
when a calendar beneath, the older listener, has taken it the flag is down
and its reload is on its way; when none has, the flag stays for the calendar
an Open event pushes, whose `_predatesKeep` defers its initial target to its
own reload, a guard a taking overview defeated; a pending notice is served
after the first frame, the listener removed in `dispose`) and the
`_appearance` and palette it adopts from the settings (the palette joins
`getCalendarOverviewSettings`). While the trip holds the guard the page
parks bloc states as it does under a cover and adopts the last once the trip
ends (finding 7: a tick in the sheet must not re-resolve the period). The
chip row's fold follows the page's own keyboard only (`ModalRoute.isCurrent`,
finding 6). `_openOn(day, eventId)`: `_blur()`, the event
found by id in `_events` (none → nothing), `flow.open(context, event, day)`;
a per-event row opens on `row.last` as D10 says. `CalendarOverviewPage.forTesting`
loses `openOccurrence`; nothing navigates. `AppNavigator.toCalendarOccurrence`,
`occurrenceCalendarRouteName`, `servesCalendarOccurrence` and the calendar
page's serve gate stay for the alert paths (`main.dart`, `alarm_page.dart`,
`alerts_page.dart`); the overview no longer calls them. Flow 23: the row tap
waits for `event-detail-close`, one `key back` closes it, the row is expected
on the list; the second `key back` goes.

### 3.12 The second follow-up (D15–D18, 2026-10-13)

**The period band in List mode (D15 · A).** Under the filter group, where
Year and Month modes draw theirs (`_buildYearNav`
`calendar_overview_page.dart:2272–2289`, `_buildMonthNav` `:2291–2316`),
List mode draws an `AgendaPeriodNav` too: `title: _period.menuValue(l10n)`,
`subtitle: agendaDayListCountLabel(l10n, _listedKept, _listedMissed)` (the
count caption `_buildCount` `:1890–1900` goes; `belowFilters` `:1648–1650`
becomes the nav in every mode, then D16's totals slot), `onPrevious` /
`onNext` stepping (below), the Today slot per D15b, `onTitleTap` opening the
Dates sheet's range mode (the same picker the Period row's Custom range…
opens; a pick is a pick: `_setPeriod`), the four `overview-nav-*` ids,
tooltips `overviewPeriodPrevious` / `overviewPeriodNext` and, on the Today
slot, `overviewPeriodHome(period)` with the home's `menuValue`. Nothing
centered is added: it is the band the other two modes already have.

The title's box must not change height between periods (the nav's own
rule): `AgendaPeriodNav` gains `titleTemplates: List<String>?`, measured
the way the twelve month titles are (`_titleHeight`
`agenda_period_nav.dart:148–164`; the LRU key `:14–22` gains a `templates`
string, `''` on the month path) — the box is the tallest of the shown title
and the templates, on `FormMetrics.periodTitleMaxLines`. The list nav
passes the three preset labels, a year, and two spans in `dateSpanLabel`'s
grammar built on the locale's widest `MMM` with two-digit days (the
same-year and the cross-year shapes).

**Stepping (D15a).** `OverviewPeriod.stepped({required int direction,
required DateTime today, required AgendaYearBounds yearBounds})` →
`OverviewPeriod?` (`lib/models/overview_period.dart`): a year →
`OverviewYearPeriod(year ± 1)`; a rolling preset or a custom span → an
`OverviewCustomPeriod` shifted by its resolved inclusive length L (back
`[start − L, start − 1]`, forward `[end + 1, end + L]`); All time → null;
null too when the result lies wholly outside `[Jan 1 of yearBounds.first,
Dec 31 of yearBounds.last]` (the year nav's own bounds) or `CalendarBounds`.
A chevron is disabled when `stepped` is null. The page's `_step(direction)`:
`_click()`, `_period = stepped`, `_year = _firstYearOf(period)`,
`_recompute()`, `_land()` (D7: today outside → the top),
`_schedulePrewarm()`; no persistence (D15c).

**Home (D15b).** `_home`: the period as picked — set by `_setPeriod` and
`_listPeriod` beside `_period`, initialized from the persisted period,
moved across New Year with `followingToday` as `_period` is; never by a
step, never by Year-mode paging. The Today slot: `onToday: _period == _home
? null : _goHome`, `_goHome` setting `_period = _home`, `_year`,
`_recompute()`, `_land()`; tooltip `overviewPeriodHome(_home.menuValue(l10n))`.
The Period row keeps reading `_shownPeriod`: a stepped span with Custom
range… checked, as a paged year reads today.

**Per-category totals (D16 · A).** Under the nav in every mode, a
`FormCaptionSlot` whose candidate fixes two lines (a `FormCaption(maxLines:
2)` over a two-line template), its child `FormCaption(text: totals,
maxLines: 2, overflow: ellipsis)` at `FormMetrics.groupCaptionPadding`
inside `RowMetrics.groupInset`, one semantics node. The tally runs over
what the mode lists — List mode `_listedEntries` (`:252`), Month mode the
month's listed entries, Year mode the twelve buckets' entries through
`_listed` — and an entry counts when `!entry.missed`, or when it is missed
while Missed only narrows this mode (`_options.missedOnly && _mode !=
year`); its category comes from the lookup the per-event fold already uses
(`categoryOf`, `:837`). Text: the categories in catalog order
(`CalendarCategories.all` kept to those with a count), each
`overviewCategoryTotal(label, count)`, joined with " · " as the count
label's grammar joins, three named then `categoriesMore(rest)`; empty when
nothing is listed. Computed in `_recompute` and when a batch run lands,
beside `_listedKept`.

**Saved views (D17 · A).** `lib/models/overview_view.dart`:
`OverviewView({id, name, period: OverviewPeriod, options:
OverviewListOptions, categoryIds: Set<String>, sortOrder})`, `toJson` /
`fromJson` forward-compatible (the period as `{kind: year | preset |
custom, year, preset, start, end}`, unknown → this year; absent options →
defaults, `missedOnly` kept; `markPresence` never stored), `matches(period,
options, categoryIds)` ignoring `markPresence`.
`lib/database/tables/overview_views_table.dart` (`overview_views`, v41:
`id`, `name`, `payload`, `sort_order`, `created_at`, `updated_at`, the v29
CRDT block, `is_deleted`, `deleted_at`), `DatabaseSchema.currentVersion =
41` with `v41OverviewViews`, `_migrateV40ToV41` (`CREATE TABLE IF NOT
EXISTS`, the v35 step's shape `database_migrations.dart:1387–1389`),
registered in `database.dart` as the presets are (`:69`, `:89`),
`build_runner`; `lib/database/daos/overview_view_dao.dart` cloned from
`filter_preset_dao.dart` (stamping in the DAO, soft delete,
`nextSortOrder`, `reorder`, `importAll`, `deleteAll`);
`lib/services/overview_view_service.dart` cloned from
`filter_preset_service.dart` (`maxViews = 50`, `isFull`, `views`, `create`
→ null when full, `update`, `delete`, `reorder`, `matching`, `exportData`,
`importData`, `reload`, `DatabaseLifecycle.registerResetHandler`,
`forTesting`); `backup_service.dart`: `'overviewViews'` exported beside
`'calendarFilterPresets'` (`:114`, `:164`) and imported when present
(`:464–471`), the archive version left at 1 as v35 left it
(`import_export_service.dart:99`); `references/schema-lineage.md` gains v41.

The bar (D17a): `_buildViewsButton` between the tune button and the ⋮
(`:1637–1644`) — `AutomationId(overview-views-open)` over
`IconButton(tooltip: overviewViewsTitle, isSelected: _activeView != null,
icon: bookmarks_outlined)` (the calendar bar's `calendar_page.dart:878–884`),
`_activeView` being `service.matching(_shownPeriod, _options,
_categoryIds)` read on each rebuild from the service's cache.
`lib/widgets/overview_view_sheet.dart`: `OverviewViewSheet.show(context,
{required OverviewView current, required ValueChanged<OverviewView>
onApply})` — the preset sheet's chrome one for one
(`filter_preset_sheet.dart`): handle, `FormSheetHeader(✕
overview-views-close, title overviewViewsTitle)`, the search row past the
same threshold (`overview-views-search`), `FormActionRow(
bookmark_add_outlined, overviewViewSaveCurrent, overview-views-save)`, one
row per view (`overviewViewRow(id)` — a tap applies and closes; a ✓ on the
matching one; the handle `overviewViewHandle(id)`; the ⋮
`overviewViewOptions(id)` → Rename `overview-views-rename` / Update to
current list `overview-views-update` / Move to top `overview-views-move-top`
/ Delete `overview-views-delete`), the limit through
`overviewViewLimitReached(50)`, delete through `AppDialogs.confirm`, names
through the preset sheet's name dialog made shareable (title and labels
passed in; no second dialog). No "None" row: a view is applied, never
cleared. Applying (D17c): `_applyView(view)` — one `setState` with `_mode
= list`, `_period = _home = view.period`, `_options = view.options`,
`_categoryIds = view.categoryIds`, `_recompute()`, then `_land()` and the
persistence each part has today (`_persistMode`, `_persistPeriod`,
`_persistOptions`, `setCalendarOverviewCategories`); the query untouched.
"Save the current list" snapshots `_shownPeriod`, `_options` and
`_categoryIds`.

**Mark presence (D18 · A — retired 2026-10-17 by D31, §2.7 / §3.15: the day panel's button on the row).** `OverviewListOptions.markPresence`
(session-only like `missedOnly`; `copyWith`, `props`). The options sheet
takes `mode: AgendaDayListMode` in place of `listMode` (Order and Rows
enabled in List as today) and gains `FormSwitchRow(label:
overviewMarkPresence, identifier: overview-mark-presence)` under Missed
only, enabled when `(mode == list && rows == everyOccurrence) || mode ==
month`, disabled otherwise (38 %, never hidden); a Rows change to One per
event turns it off. The page: `_rowBuilder`'s `onEntryTap` →
`_onEntryTap(entry)`: while `_options.markPresence` and the entry's event
tracks presence (`EventPresence.appliesTo`, as `event_detail_sheet.dart:288`
tests) → `_click()` and `EventSheetsFlow.setOccurrencePresence(bloc,
entry.eventId, entry.day, !entry.missed)` (`event_sheets_flow.dart:574–584`),
nothing else — the bloc's `presenceRevision` reaches the listener and the
row re-renders dimmed or not, the day header's counts with it; otherwise
`_openOn` as today. `AgendaDayListRowBuilder` gains `onEntryLongPress`
(`FormPickerRow` gains `onLongPress`, the one primitive extension): while
marking, a long press opens the sheet; off, null. Semantics while marking:
the entry row's node carries the hint `eventMarkMissed` / `eventMarkPresent`
(the panel's words, `day_summary_panel.dart:216–226`). The tune button:
`isSelected: restrictions > 0 || _options.markPresence`; the badge counts
restrictions only (T11). A skip is not presence; the `isMissed` rules are
untouched; per-event rows keep opening the sheet.

**Copy** (en / de / ro together, `gen-l10n`, `untranslated.txt` `{}`):
`overviewPeriodPrevious` "Previous period", `overviewPeriodNext` "Next
period", `overviewPeriodHome` "Back to {period}", `overviewCategoryTotal`
"{label} {count}", `overviewMarkPresence` "Mark presence",
`overviewViewsTitle` "Saved views", `overviewViewSaveCurrent` "Save the
current list", `overviewViewSaved` "Saved as \"{name}\"",
`overviewViewUpdate` "Update to current list", `overviewViewDelete` "Delete
saved view", `overviewViewDeleteConfirm` "Delete \"{name}\"? The events it
lists are untouched.", `overviewViewActions` "Saved view options",
`overviewViewLimitReached` "You can save up to {count} views",
`overviewViewSearchHint` "Search saved views", `overviewViewNoMatches` "No
saved view matches your search"; reused: `filterPresetName`,
`filterPresetRename`, `filterPresetReorder`, `moveToTop`, `delete`,
`cancel`, `categoriesMore`, `eventMarkMissed` / `eventMarkPresent`.

**Ids** (`semantics_ids.dart`, the overview block `:406–442`):
`overview-mark-presence`, `overview-views-open`, `overview-views-close`,
`overview-views-search`, `overview-views-save`, `overviewViewRow(id)`
(`overview-view-<id>`), `overviewViewOptions(id)`, `overviewViewHandle(id)`,
`overview-views-rename`, `overview-views-update`, `overview-views-move-top`,
`overview-views-delete`; the list nav wears the existing `overview-nav-*`.

### 3.13 The third follow-up (D19–D25, 2026-10-14)

Line numbers are from the uncommitted tree of 2026-10-14 (the two
follow-ups on `c4f5697`); re-grep before editing.

**The page in every mode, top to bottom** (en, 1.0, 360 wide): the bar as
today; the chip row — `_buildModeChips` (`calendar_overview_page.dart:2153`)
becomes a `Row` of the `FormChipRow(indented: false)` in an `Expanded` and,
at its end, **the search button** (D21 · A):
`AutomationId(overview-search-open)` over `IconButton(tooltip: l10n.search,
isSelected: _query.isNotEmpty, icon: Icons.search_rounded, onPressed:
_toggleSearch)` — a plain `IconButton` with `isSelected`, the tune
button's own shape, never a tonal one; the row's height (`_chipRowHeight`,
`:2173`) and its fold are unchanged; **the Search group, only while
`_searchOpen`**: `Padding(left / top / right: groupInset / bodyTop /
groupInset)` over `FormRowGroup(trailingGap: false, children:
[FormSearchRow(controller: _searchController, focusNode: _searchFocus,
hint: upcomingSearchHint, clearTooltip: upcomingClearSearch, onChanged:
_onQueryChanged, identifier: overview-search)])` — the filter group's
first row in the filter group's own box; `belowFilters` (8) follows it as
it followed the group, and is absent with it; **the band** (the nav, then
the totals), folding with the keyboard as today; the body.
`_buildFilterGroup` (`:2200–2246`) is deleted with the Categories row
(D22, into the options sheet) and the Period row (D19, into the nav's
title); `_categoriesValue` (`:2250`) moves to the sheet; `_periodLabel` /
`_periodIcon` / `_periodId` (`:2260–2298`) stay, read by the title's menu.
`FormSearchRow` (`form_rows.dart:2551`) gains `focusNode: FocusNode?`,
passed to its `TextField` — the one primitive extension; `form_rows_test`
gains the case.

**The search (D21 · A).** `_searchOpen` and `_searchFocus` are the page's,
session-only, closed on open (the query is session-only too, so a closed
row never hides a live query). `_toggleSearch`: closed → `setState(() =>
_searchOpen = true)` and, after the frame, `_searchFocus.requestFocus()`;
open → `_blur()`, then if the query is non-empty `_searchController.clear()`
and `_onQueryChanged('')`, then `setState(() => _searchOpen = false)`. The
row's own ✕ clears the text and the query and leaves the row open. The
button reads selected while `_query.isNotEmpty`. Every sheet and menu the
page opens `_blur()`s first, as today. `_searchFocus` is disposed beside
the controller (`:390`).

**The period control (D19 · A).** `AgendaPeriodNav.onTitleTap`
(`agenda_period_nav.dart:94`) becomes `ValueChanged<BuildContext>?`: the
title's own context — the `InkWell`'s, inside the `LayoutBuilder` (`:262`)
— so a caller can anchor a menu to the title; the day list's two callers
(`agenda_day_list_sheet.dart:723`, `:796`) become `(_) => _pickDate()`;
`agenda_period_nav_test` pins that the argument is the title's context (its
render box is the title's). The overview's three navs pass `onTitleTap:
_openPeriodMenu` and `titleTooltip: l10n.overviewPeriod` (Year's and
Month's read `monthYearPickerTitle` today, `:2781`, `:2808`; the title no
longer picks a date). `_openPeriodMenu(BuildContext anchor)`: `_blur()`,
then `showFormMenu<OverviewPeriodChoice>(anchor, items: [for each
OverviewPeriodChoice: FormMenuItem(value, label: _periodLabel, icon:
_periodIcon, identifier: _periodId)], selected:
_shownPeriod.menuChoice(today: _today), menuWidth: FormMetrics.menuWidth)`;
a non-null answer runs `_selectPeriod(choice)` (`:1578`) exactly as the
row's `onSelected` did — D13 · A untouched: List → `_setPeriod`; This year
in Year mode → `_setPeriod` (pages to this year); every other case resolves
the period (the range picker for Custom range…, a cancel changes nothing)
then `_listPeriod`. `showFormMenu<T>(BuildContext anchor, {required
List<FormMenuItem<T>> items, required T? selected, required double
menuWidth}) → Future<T?>` is `FormMenuRow._open`'s body
(`form_rows.dart:2719–2760`) hoisted into `form_menu_item.dart` — the
`showMenu` call with `formMenuPosition(anchor, …, menuHeight:
formMenuHeight(items.length))`, `menuSurface`, `menuRadius`,
`menuPadding`, the `minWidth: menuWidth` / `maxWidth: menuMaxWidth` box and
the `FormMenuChoiceItem` / `FormMenuItemRow` items — and `FormMenuRow._open`
calls it after its own `onSelected == null` return and unfocus, so the row
behaves as before (`form_rows_test` unchanged). `_pickListRange` (`:1621`)
goes: a span is picked through the menu's Custom range… (`_selectPeriod` →
`_pickRange`, `:1601`). `MonthYearPickerSheet` leaves the page (D25 · A):
`_pickDate` (`:1252–1283`), `_highlightMonth`, `_highlightToken` and the
pager's `highlightMonth:` / `highlightToken:` arguments (`:2440–2441`) go;
`AgendaYearPager.highlightMonth` itself stays for the day list sheet. The
title's menu is the Period row's: the checked item follows `_shownPeriod`
(`:1716`) — a paged year in Year mode checks Custom range…, as the row read
it; the position is `formMenuPosition`'s (right edge on the title's, below
it while it fits), and at 200 % the route's own clamp keeps it on screen
(the device pass looks).

**The nav's height per mode (D20 · A).** `_buildYearNav` (`:2769`) passes
no `titleTemplates` and no `month`: its box is the year's one line, every
year alike; `_buildMonthNav` (`:2789`) passes `month: _month` alone — the
twelve `yMMMM` titles, the day list's month nav; `_buildListNav` (`:2327`)
keeps `titleTemplates: _titleTemplates(l10n)`, from which the twelve month
titles (`:2369–2370`) are dropped (the list's title is never a month). The
tests "the nav is one height in Year, Month and List"
(`calendar_overview_page_test.dart:1628`) and "the title box is as tall
for a year, a preset and a span" (`:1516`) change per §4.2: Year's and
Month's navs are the one-line height at en 1.0 on 360, List's is the
templates' (two lines there), and a Year page, a Month page and a List
step each move the body by nothing.

**The totals (D23 · A).** `OverviewListMetrics.totalsMaxLines = 1`
(`overview_list_metrics.dart:33`, its comment rewritten: one line, the
list below never moves, three names then "+N more", an ellipsis past the
width); the slot's template in `_buildTotals` (`:2301`) is a one-line
caption (`text: ' '`); `namedTotals` stays 3. The "the totals (D16)" group
(`:1653`) re-pins the slot at one line.

**Categories in the options sheet (D22 · A).** `OverviewOptionsSheet.show`
(`overview_options_sheet.dart:45`) and the widget gain `required
Set<String> categoryIds` and `required ValueChanged<Set<String>>
onCategoriesChanged`; the sheet's first row, above Order:
`FormPickerRow(glyph: Icons.category_rounded, label:
l10n.overviewCategories, value: <the read-back>, singleLine: true,
identifier: SemanticsIds.overviewCategories, onTap: _pickCategories)`. The
read-back is the page's `_categoriesValue` moved whole ("All" for the empty
allowlist, else `CalendarFilterSummary.namesReadBack` over
`CalendarCategories.visiblePlus(ids)`'s chosen labels); `singleLine` so the
sheet never re-lays out on the picker's answer (the stale-semantics bug,
§9 2026-10-13). `_pickCategories` is the page's (`:1772–1800`) moved whole
— the offered set, `CategoryPickerSheet.pickMulti(context, selected:
ids.isEmpty ? offered : ids)` over the sheet, the all-offered → empty
collapse, the `setEquals` short-circuit, a local `_pickerOpen` — then
`setState` on its own copy and `onCategoriesChanged(next)`. The page's
`_onCategoriesChanged(next)` keeps what followed the pick: `_categoryIds =
next; _categoryRevision = null; _refreshCategoryLabels(); _storeStale =
true; _rebuild();` then `setCalendarOverviewCategories(next)` (`:1793`).
`_openOptions` (`:1722`) passes `categoryIds: _categoryIds` and the
callback. The tune button (`:2111`): `restrictions` counts the categories
allowlist too — `(missedOnly && mode != year ? 1 : 0) +
(_categoryIds.isNotEmpty ? 1 : 0)`, in every mode (the tiles honour the
allowlist); `isSelected` unchanged in shape. `sheet_bottom_clearance_test`
and `overview_options_sheet_test` take the two new arguments; the sheet
suite gains the row: the read-back, a pick that applies and reports, the
collapse to empty, the picker above the sheet.

**Ids.** New: `overviewSearchOpen = 'overview-search-open'`. Retired:
`SemanticsIds.overviewPeriod` (`semantics_ids.dart:430`) — the row is
gone; the menu's items keep `overview-period-*`; `overview-categories`
moves onto the sheet's row, `overview-search` onto the revealed row; the
constant's doc comment (`:413–418`) and the `calendar-ui` catalogue say
so. **Flows** (`tool/qa/flows/calendar/`): `05_overview.txt:14` waits on
`overview-nav-title` instead of `overview-period` (and its header comment
drops the "no nav in List" line, stale since 9a); `23_overview_list.txt`
`:54`, `:132` likewise, `:60`, `:72`, `:161` tap `overview-nav-title` to
open the menu, `:157` becomes `tap id:overview-search-open` · `wait
id:overview-search` · the typing as today, and the search is closed after
its check (`tap id:overview-search-open` · `wait id:overview-search
--gone`); one Categories trip joins the options-sheet steps (`tap
id:overview-options-open` · `wait id:overview-categories` · `tap
id:overview-categories` · `wait id:category-pick-close` · `tap
id:category-pick-close` · `tap id:overview-options-close` · `wait
id:overview-options-close --gone`; the picker's ids are the calendar-ui
catalogue's `category-pick-*`); `24_overview_views.txt` `:22` waits on and
`:25`, `:43`, `:77` tap `overview-nav-title`.

**Tests.** The robot (`test/widgets/support/overview_robot.dart`): the
Period row block (`:459–512`) becomes the title's menu — `openPeriodMenu`
taps `overview-nav-title`, `periodValue` reads the nav's title,
`periodChoice` opens the menu and reads the checked `FormMenuItemRow` then
dismisses, `periodEnabled` reads `onTitleTap != null`; the jump picker
helpers (`:433–457`) go; `searchOpen`, `openSearch` / `closeSearch` (the
chip row's button) and `searchFocused` join. Test bodies change only where
§4.2 names the change (the Period row's cases, the jump picker's, the
categories row on the page, the one-height band, the two-line totals, the
search row's presence); new cases: the search button reveals the row
focused, the ✕ clears text and query, the button again closes and clears,
selected while a query is set, the chips and the band still fold over
`_chipRowHeight` with the row open; the title opens the menu in Year,
Month and List, a pick in Month mode switches to List (D13 · A), This year
in Year mode pages, Custom range… opens the range picker and a cancel
changes nothing, the checked item follows `_shownPeriod`; Year's box is
one line at 1.0 and a page moves the pager by nothing, Month's over the
twelve titles, List's over the templates; the options sheet's Categories
row; the totals slot one line; **the geometry pin**: at en 1.0 on
360 × 780 in Year mode the distance from the bar's bottom to the pager's
top is 134 dp (the chip row 56, the nav 52, the totals 26) and the
December tile's bottom edge lies within the page's first 756 dp (780 less
the 24 dp status bar the test does not draw) — the reason for this
follow-up.

**Copy.** No new strings: `search` ("Search") for the button's tooltip,
`overviewPeriod` ("Period") for the title's tooltip in every mode.

**Numbers** (en, 1.0, 360 × 780, a 24 dp status bar): above the first
tile 404 today → 206 (the status bar 24, the bar 48, the chip row 56, the
one-line nav 52 — the 48 dp chevrons and the row's 4 dp bottom padding —
the totals 26); the twelve tiles 504; 70 dp to spare. Month mode's grid
starts at 206 (404 today); List mode's pinned label at 226 (its nav keeps
two lines for a span).

### 3.14 The years scroll (D26–D30, 2026-10-15)

**The widget.** `AgendaYearScroll` (`lib/widgets/agenda_year_scroll.dart`)
replaces `AgendaYearPager` on the overview page only; the pager stays for
the day list sheet's year scope, with its flash and its picker. Under a
`LayoutBuilder`, a `CustomScrollView` with one `SliverFixedExtentList`
whose items are the span's years, oldest first (D26). `itemExtent` =
`yearHeaderHeight` (measured once per text scale) + rows ×
`YearMonthTile.gridDelegate.mainAxisExtent` + (rows − 1) × its
`mainAxisSpacing` + `yearSectionGap`, computed once per width and text
scale; the column count comes from one rule shared with the grid delegate
(`YearMonthTile.columnsFor(width)`, the delegate's own
`(crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing)).ceil()`,
at least 1), rows = `(12 / columns).ceil()`. A section is a
`RepaintBoundary` over a `Column`: the header row, then rows of tiles with
the delegate's spacing, each tile `Expanded` so its width equals the
grid's `usableCrossAxisExtent / crossAxisCount`, its height the delegate's
116. Both the grid (the pager's page) and the section build their tiles
through one shared builder lifted out of `AgendaYearGrid.itemBuilder`
(label, count, colours, matrix, semantics), so the two surfaces cannot
drift; the section takes no highlight. Horizontal insets
`yearScrollPadding` (`groupInset` left and right; the pager's bottom inset
becomes the last section's gap), the metric renamed from
`yearPagerPadding`, which has no other user.

**The header (D27).** `yearHeaderHeight` 48 and `yearHeaderFontSize` 22 in
`OverviewListMetrics`; the year in 22 / 500 `onSurface`, tabular figures,
bottom-aligned with 8 dp of air to the tiles; the count
`agendaDayListCountLabel(l10n, kept, missed)` at 13 / 400
`onSurfaceVariant` in a `FittedBox(scaleDown)` one-line box, an empty slot
of the same height while the year is unresolved; `yearSectionGap` =
`groupInset` (16) below the tiles. One `Semantics` node (`header: true`,
label `"<year>, <count label>"`), identifier
`SemanticsIds.overviewYearHeader(year)` = `overview-year-<yyyy>`; the
scroll view carries `SemanticsIds.overviewYears` = `overview-years`, the
list's `overview-list` twin.

**The controller.** `AgendaYearScrollController` (same file) is what the
page holds instead of `_yearPager`: `firstYear`, `lastYear`, the extent
once the first layout fixed it, `offsetOfYear(year)`,
`yearAtOffset(offset)` = `firstYear + ((offset + headerHeight / 2) /
extent).floor()` clamped to the span, `jumpToYear(year)`,
`animateToYear(year)` (`OverviewListMetrics.pageDuration`,
`Curves.easeOutCubic`). The inner `ScrollController` is created inside
the `LayoutBuilder` the first time the extent is known, with
`initialScrollOffset: offsetOfYear(initialYear)`, so the first frame
opens on the year with no jump after it; a year requested before that is
remembered and becomes that offset. When the extent changes (a width or
text-scale change) the controller keeps the top year — the offset is
corrected in the same layout pass — the top year never changes because
the extent did.

**The top year.** The widget's scroll listener reports
`onTopYearChanged(year)` once per change of `yearAtOffset(pixels)`, never
per pixel; the page's `_onYearScrolled` is today's `_onYearPaged`
(`_year`, `_period = OverviewYearPeriod(year)`, `_recompute`). A landing
(`jumpToYear`, `animateToYear`'s end, `_setPeriod`) reports the same way
in the same turn, so the title never lags a jump.

**Resolution (D30, "resolve on navigation, never in build").** The
section builder reads the store's cached tally only
(the page's `AgendaYearTileSource`, `tilesFor(year)` null when unresolved → the D30 placeholder; since the fix pass each section listens to the source and rebuilds alone when its year's version moves). A
viewport-driven queue replaces the pager's synchronous `tilesFor` and its
250 ms prewarm: on every scroll notification, landing, mode switch into
Year and `forget`, `_scheduleYearRun()` derives `wanted` = the years whose
sections intersect the viewport, then the top year's two neighbours,
inside the span, minus the resolved — ordered top year first, then the
visible in reading order, then the neighbours — and, if any remain and no
run is pending, schedules one run in a post-frame callback (`_runYear`, with `ensureVisualUpdate`; `_yearFrameOwed` holds the next run one more frame after any scan, so a frame that drew a scan's result runs no other scan) under `_resolveGeneration`. A run
re-derives the queue from the viewport as it is then (a year scrolled past
is never resolved), resolves exactly one year (`ensureTallies` over
`monthsOfYear`, one marks call; the row path under a live query, as
today), `setState`s, and schedules the next run while years remain. One
year per run, one run per frame: a fling across a decade costs
ten marks calls spread over frames and never two in one. The opening year
and a landing's target resolve synchronously before their frame (one
call, as "opening scans the year once" already holds), so neither the
first frame nor a jump ever shows a blank year; a drag does, for at most
a frame. `_schedulePrewarm` and `_prewarmTimer` retire with the pager;
List mode's runs are untouched. `_tilesByYear` is the `AgendaYearTileSource`; `forget(month)` from a presence mark drops its year's entry and the
year re-queues if visible.

**The band.** `_tallyYear(_year)` reads the cache: a blank count and a
blank totals line while the top year is unresolved (text, never
geometry), filled by the run's `setState`.

**The nav.** `_buildYearNav` keeps its shape and ids: ◄ `animateToYear(_year
− 1)` while `_year > span.first`, ► symmetric, Today
`animateToYear(_today.year)` while `_year != _today.year`; the Period
menu unchanged (This year → `_setPeriod` → `jumpToYear(_today.year)`, the jump today's `jumpToPage` made, the year resolved before its frame, and stays in Year
mode; every other pick lists; Custom seeds from the shown period; a cancel
changes nothing); `_setPeriod` lands with `jumpToYear(_firstYearOf(period))`.

**The span (D28).** `EventAgenda.yearBoundsOf` gains an optional
open-ended ceiling year; the overview passes `today.year + 1`, so an
open-ended series ends the span next year while a bounded series or a
pinned date past that still extends it and today is always inside; the
day list sheet passes nothing and keeps the full bounds. `_years` stays an
`AgendaYearBounds`.

**The scrubber (D29, slice 12).** In Year mode `ListScrubber` wraps the
scroll when the span holds two or more years: `labelAt` →
`'${controller.yearAtOffset(offset)}'`, `onStep` → ±1 year,
`identifier: SemanticsIds.overviewScrubber` (one lane per page, never two
modes at once), the recognizer's `MediaQuery.maybeGestureSettingsOf` kept.

**Tests.** `test/widgets/agenda_year_scroll_test.dart` (new): the extent
and the column rule against a real `SliverGridDelegateWithMaxCrossAxisExtent.getLayout`
at 328 and 580 of cross axis (same columns, same tile width); the
`offsetOfYear` / `yearAtOffset` round trip and the half-header threshold;
a hundred-year span builds only the viewport's sections (count the
headers); `initialYear`'s header is at the top on the first frame; a width
change keeps the top year; the header's semantics and ids; de at 2.0 and
360 × 780 / 412 × 915 without overflow; dark. `calendar_overview_page_test.dart`'s
Year block re-targeted to the scroll (the chevrons scroll and the title
follows; a drag into the neighbour flips the title at the threshold; the
span ends next year for an open-ended series and at a bounded end past
it; opening scans the year once and builds at most two sections, the
neighbours resolve in runs after the first frame; a run never resolves a
year the viewport passed; a presence `forget` re-resolves its month; the
Period menu's five rules; the nav ids) through `OverviewRobot`, which
grows the helpers it needs. `agenda_day_list_sheet_test.dart` and
`agenda_month_store_test.dart` untouched and green. Slice 12 adds the budgets (`overview_years_benchmark_test.dart`): a hundred-year span opens with at most three sections built (Flutter's default cache extent) and exactly three years resolved, one per frame; a far jump builds at most three and none in between; a fling over twenty years resolves at most one year per frame and no more than the years seen plus two; a keyboard animation builds no tile; a keystroke under a query scans nothing — the counts run untagged in the default suite (`budgets year mode over a hundred years`), the millisecond prints under the `benchmark` tag.

**After the reviews (2026-10-15, slices 12 and 12b).** The span is two
bounds from one pass — `EventAgenda.yearSpansOf` returns `full` and
`ceiled`, `yearBoundsOf` delegating to it — because the D28 ceiling had
leaked into List mode's ►, Month mode's year clamp and the range picker's
last date through the shared `_years`; `_scrollYears` (ceiled) is the Year
scroll's alone (its span, its nav's ◄ ►, `_goToYear`'s clamp, the queue's
bounds), `_years` (full) everything else's, and `_clampYearToScroll` brings
`_year` into the scroll's span on a switch into Year and in `_rebuild`. An
open-ended series contributes the later of the ceiling and its start year,
so a series starting past next year still extends the span. The scrubber
lives inside `AgendaYearScroll` (`AgendaYearScrubber`: the semantics label
`overviewYearScrubberLabel` — "Scroll by year" — the identifier,
`onLabelChanged`, `onStep` with the target year), shown only when the span
holds two or more years, a `GlobalKey` keeping the position when the lane
comes or goes; a step reaches `_goToYear`, so it resolves its target
synchronously and clicks like the chevrons. The controller remembers
`landingYear`: a pixel correction mid-landing re-issues the animation to
the target (`pageDuration` from wherever the scroll is), and `_rebuild`
resolves the target rather than the year passing the top. The keyboard
rebuilds nothing: the tail filler is a `SliverLayoutBuilder` (the box
`LayoutBuilder` reads only the width) and the sections' delegate is one
instance across runs. A query change keeps the near years' tiles (the top
year, the visible years, the two neighbours) until the same `setState`
refolds them, and drops every other cached year, so nothing stale is ever
drawn as current. `_rebuild` from `didChangeDependencies` defers its
resolve to a post-frame callback that also refuses while `_covered`. The
cache extent is Flutter's default.

### 3.15 The presence button (D31, 2026-10-17)

**The entry.** `AgendaDayListEntry.presenceTracked` (default false), the
day panel entry's field: set at the one conversion site,
`AgendaListView.eventDayEntries`, as `EventPresence.appliesTo(event)`; the
page's extent probe builds its entries with it on, so the measured row is
the row with the button (the same height either way —
`FormMetrics.titleRowMinHeight` 56 holds the 48 dp button, as the day list
sheet's pencil rows prove).

**The builder.** `AgendaDayListRowBuilder.onEntryPresence(entry, missed)`
and `presenceIdentifier(entry)` replace `onEntryLongPress` and
`entryHint`. `_entryRow`'s trailing slot: the pencil where the builder has
`onEntryEdit` and the entry carries `onEdit` (the day list sheet's rows,
unchanged); else, where `onEntryPresence` is given and the entry is
`presenceTracked`, `FormTrailingButton(icon: missed ? event_available :
event_busy, tooltip: missed ? eventMarkPresent : eventMarkMissed,
onPressed: onEntryPresence(entry, !missed), identifier)` in the pencil's
colour; else nothing. The row's tap is `onEntryTap` in every case; a
missed row fades with its button as the day panel's card does.
`FormPickerRow.onLongPress` and `hint`, the D18 primitive extension, leave
with their one caller.

**The page.** `_presenceOffered` (`_dayRowsShown && !_missedHidden`)
hands `_onEntryPresence` to `_rowBuilder` — Month mode's rows and the
list's every-occurrence rows; nothing in Year mode, nothing under One per
event, nothing while the missed display is hidden. `_onEntryPresence`:
`_click()`, the `(eventId, day)` into `_pendingMarks`, then
`EventSheetsFlow.setOccurrencePresence(bloc, id, day, missed)`; the
`_forgetMarked` rule (a mark re-resolves its month alone) is untouched.
A row tap opens the occurrence, always. The tune button selects for
restrictions alone.

**Retired.** `OverviewListOptions.markPresence` and every rule on it: the
options sheet's switch and `missedHidden`, `canMark`, the Rows menu
clearing it, `_marks`, `_setOptions`'s repaint-only shortcut,
`_selectMode`'s, `_resumeUncovered`'s, `_applyView`'s and `_listLook`'s
clearing, the views' `copyWith(markPresence: false)`, the id
`overview-mark-presence`, the ARB key `overviewMarkPresence` ×3. A view
never stored the flag, so no persisted JSON changes.

**Ids.** `overviewRowPresence(eventId, day)` →
`overview-row-presence-<eventId>-<yyyy-MM-dd>`, the button a device
script hits (its tooltip changes with the state and the locale).

**Flow 23.** The switch steps gave way to the button: a press on today's
Lifting row's button marks it missed (the row stays, faded), Missed only
lists it, a second press marks it present and takes it out of that list,
Missed only off.

### 3.16 The picked day under the hidden display (D32, 2026-10-17)

**The occurrence mask.** The page keeps `_occurrenceMask: Map<int, int>`
— `AgendaMonthStore.keyOf(month)` → bit `day - 1` set for every day with
any occurrence in the allowlist, hidden or not — folded in `_resolve`
from the scan's occurrences before `eventDayEntries` converts them (the
`_markedKept` precedent in `_resolveMarks`): rewritten whenever a month
is resolved again (after `forget`), cleared where `_markedKept` is
cleared (a new store). `_hasOccurrence(day)` is `_hasEntry(day) ||
(_missedHidden && the bit is set)`; under a live query it is
`_hasEntry` alone (an occurrence dropped before conversion was never
matched against the query, and the picked day's rows below are filtered
by it). The grid takes `_hasOccurrence` as its `hasEntry` (the parameter
is "a day to pick": enabled and full-strength); `_toggleSelectedDay`
guards on it in place of `countForDay`. Under `faded` the mask adds
nothing (`hasEntry` already holds every day with an occurrence), so the
grid is unchanged for everyone else.

**The picked day's rows.** `_pickedDayEntries(day)`:
`AgendaListView.eventDayEntries(_scan(day, day), l10n, null,
showRecurrenceLabels: _appearance.showRecurrenceLabels, missedDisplay:
CalendarMissedDisplay.faded)`, then `_matches` under a live query, then
`_listed` (Missed only). `_recompute`'s month branch builds `_rows` for a
picked day from it (`buildAgendaDayListRows([selected], (_) => entries,
groupByDay: false, withMonths: false, keptCountOf: …)`); the whole-month
path (`bucket.days`, `bucket.entriesOn`) is untouched. Under `faded` the
scan yields exactly `bucket.entriesOn(day)` (same conversion, same
inputs), so one path serves both settings and costs one day's
`occursOnUtcDay` per loaded event. `_buildPickedDayRow` takes its counts
from the same entries — the day's total and its kept count, `kept` 0
under Missed only as before — so the read row says what the rows show
(the label for a hidden future day is `faded`'s existing label for a day
whose only entry was missed).

**The button.** `_presenceOffered` becomes `_dayRowsShown &&
(!_missedHidden || _pickedDayShown)`, `_pickedDayShown` = `_mode ==
AgendaDayListMode.month && _selectedDay != null`. A press is D31's
`_onEntryPresence` unchanged; the bump re-resolves the month
(`_forgetMarked` → `forget` → `_resolve` rewrites the bucket and the
mask), `_recompute` rebuilds the picked day's rows from the scan, so the
row un-fades or fades in place, the day's bar appears or goes and the
nav's count follows. The whole-month rows under `hidden` stay without the
button (D31's reason holds there: a row that vanishes on its mark). The
flow for the owner: the overview (Month persisted), tap tomorrow, press
the button — three taps.

**Tests.** The page suite: under `hidden` in Month mode a future day of
an assume-absent daily event is tappable (full-strength cell, the day's
read row), its row listed faded with "Mark as present", a press emitting
`SetOccurrencePresence(missed: false)` and, after the `presenceRevision`
bump, the row un-faded and the day's bar drawn; a day with no occurrence
stays inert; the whole-month rows under `hidden` still carry no button;
a mark missed on the picked day fades its row and keeps it; under a live
query the picked day lists only matching entries; D31's review-2 test
("missed entries hidden take the buttons away") is narrowed to the
surfaces it still describes. `agenda_month_grid_test.dart`: a day the
predicate answers for is enabled and drawn full-strength, if not already
covered. A flow `25_overview_presence_hidden.txt`: from the calendar
seed, Calendar settings → the appearance page → the Hidden segment, the
overview in Month mode, the target day's cell tapped, the row's
`overview-row-presence-<id>-<date>` pressed, the row read back, then the
mark undone and the setting restored to Faded so the seed is left as
found; the target is an assume-absent tracked event's future day if the
fixture has one, else today's Lifting row marked missed first (as flow 23
does) so that under `hidden` its day empties and the picked day restores
it.

### 3.17 The conformity pass (D33, 2026-10-17)

**Geometry that changes.** The overview's bar is `AppBarMetrics` (48 dp
toolbar; 22 px glyphs on the leading arrow and the three actions through
`iconTheme` / `actionsIconTheme`, which also set the actions' colour to
`onSurface` as the browser bars do; the 22 / 28 title of the header record
untouched) on `pageGround` with no tint; the calendar page's bar takes the
same height and glyph sizes and keeps `surface`, its own page's ground —
the chrome above the first tile is 198 dp. The
nav's title is 17 / 500 (`FormMetrics.headerTitleSize`) and its count line
13 / 400 `onSurfaceVariant` (`FormMetrics.captionSize`); both measured as
before (`titleTemplates`, `_subtitleHeight`), so every mode's box is still
one height for the labels it may show. The year tiles sit on `rowGroup`;
`AgendaYearTileBuilder` / `agenda_year_grid.dart` take the host's
background and every host passes one tone off its own ground. The Period
menu is centred under the nav title: `showFormMenu(alignment:
FormMenuAlignment.center)` (rows keep `end`), `formMenuPosition` placing the
menu's centre on the anchor's and clamping to the overlay's 16 dp margins.
The chip row's search button is a 48 × 48 target with a 20 px glyph. The
name dialog is `AppDialogs.textInput(selectAll: true, warning: …)`: the
field selected whole on open as before, Save held while the trimmed text
is empty, the duplicate-name line a soft warning on the counter's row in
the counter's metrics and the error colour (no growth when it appears),
the limit from the named constant; `FilterPresetNameDialog` goes. The options sheet's
Categories row clamps at two lines under `FormSheetSemanticsRefresh`.

**Named, not changed.** `FormMetrics.periodNav*` (the title ink's padding
and radius, the row's padding, the glyph size), the year tile's radius,
padding, gap and delegate numbers, the mini grid's two 4 dp values.

**Tests.** The page suite: the bar 48 dp on `pageGround`, the search
button's box and glyph, the Period menu's left edge inside the screen and
its centre on the title's; `agenda_period_nav_test`: the count's and the
title's styles, the Android hint; the page suite and
`agenda_year_scroll_test`: `rowGroup` on every tile; `overview_view_sheet_test`
and `filter_preset_sheet_test`: the `close` tooltip, the hairline through
`FormHeaderHairline` after a delete, the name dialog's warning;
`overview_options_sheet_test`: Missed only disabled in Year mode, the
two-line Categories value; `app_dialogs_test` (new) for `textInput`'s
`selectAll`, `allowEmpty`, `warningFor` and the identifiers;
`calendar_header_test`: the calendar bar's height and glyphs;
`overlay_snackbar_test` (new) and `app_theme_test` for the snackbar
surface. Flows: ids unchanged; flow 24 waits for the "Saved as …" message
to go before it taps a view by label; the screenshot set in both themes is
retaken for the device pass, with flows 05, 17, 23, 24 and 25.

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
- (2026-10-13, slices 8a–8c) The calendar page's detail trip as its suites
  pin it (`calendar_keep_notice_test`, `event_detail_*_test`,
  `calendar_page_jump_test`, the editor suites): a Keep heard mid-trip takes the flag
  from the bloc's copy, a pending occurrence description is carried
  forward, the editor's Back reopens the sheet, Delete and an occurrence
  that no longer survives close it, Skip closes it; `SheetGuard`'s one slot;
  `toCalendarOccurrence`'s push over an overview for the alert paths; the
  `AgendaDayListMode` names, the persisted keys and the ids
  `overview-view-*` unchanged; the overview's anchoring and landing.
- (2026-10-13, slices 9a–9d) `OverviewPeriod`'s settings codec and D4 (a
  custom span never persists through the period key; a step never writes
  it); `_setPeriod`'s "an unchanged pick still persists"; D7's landing; the
  per-event fold; `FilterPresetService`, its table, DAO, sheet and backup
  handling (cloned, never changed) and the archive version; the day
  panel's quick toggle and the detail sheet's presence pair;
  `SetOccurrencePresence`'s explicit statuses (never `clearMark`); the
  `isMissed` rules and the skip filter; `AgendaPeriodNav`'s existing callers
  (`titleTemplates` is optional; the day list's navs measure as before —
  the overview's own three navs share one box since slice 9a); every
  existing overview id; the mode chips and
  the Period row of D12–D13; the sheet trip of D14; the exact extents and
  the scrubber (the band above the list changes height between modes by
  nothing — the nav and the slot are the same height in all three).
- (2026-10-14, slices 10a–10c) D13 · A's switch into List on a pick
  outside List mode and This year's paging in Year mode; `_setPeriod`,
  `_listPeriod`, `_step`, `_goHome` and `_home`'s rules (D15a–c); the
  period codec and D4; `CalendarDatePickerSheet.pickRange` and its other
  caller (the agenda filters sheet); `MonthYearPickerSheet` and the day
  list's use of it, `AgendaYearPager.highlightMonth` for the day list; the
  saved views — what a view holds, `_applyView`, the bar button and the
  categories a view sets; the presence button's rules (§3.15) and
  `_setOptions`'s rules; the
  chips' ids and their fold; the `overview-period-*` item ids and their
  labels and icons; `FormMenuRow`'s behaviour once its opener is hoisted
  (`form_rows_test` unchanged); the row builder, the exact extents, the
  pinned label and the scrubber; Month mode's grid, picked-day row and
  sliver; `AgendaPeriodNav`'s anatomy and the day list's navs' behaviour;
  the query's and the options' persistence rules (the query and
  `_searchOpen` session-only); `YearMonthTile.gridDelegate`.

- **The years scroll (2026-10-15, §3.14):** tiles come from marks, never
  rows (`AgendaYearTile.ofTally(…, perDayColors: true)`; the row bucket
  path only under a live query); the totals under the nav from the tiles'
  marks; `OverviewYearPeriod(_year)` session-only; the Period menu's five
  rules; saved views never hold the mode; a tile tap opens Month mode on
  that month; the chip row folds with the keyboard; the nav's ids, its
  52 dp one-line title box and the one-line totals slot keep their
  geometry; `AgendaYearPager` as it is for the day list sheet;
  `YearMonthTile.gridDelegate` the one tile geometry, shared with the date
  picker's year view; `AgendaMonthStore`'s contract (resolve on
  navigation, never in build; twelve-month chunks; `forget(month)` the one
  re-resolve); the scrubber's gesture settings; flows `05_overview` and
  `23_overview_list` green, their Year steps changed in the slice that
  changes the screen.

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
- (2026-10-13, slices 8a–8b) The modes are a chip row on the page again
  (D12 · A, superseding D8 · A) and the title menu carries pages only; the
  chip row folds with the keyboard inset over its own height (the page
  overflowed by 50 px at 360 × 780 × 2.0 with the keyboard up; the calendar
  grid's keyboard-coupled precedent) and leaves semantics while folded. The
  Period row is live in every mode (D13 · A): a pick outside List mode lists
  that period, This year in Year mode pages. A row tap opens the detail
  sheet in place (D14 · A, superseding D1 · A): nothing is pushed,
  `forTesting` loses `openOccurrence`, the calendar page's sheet trip is
  `EventSheetsFlow` (`lib/controllers/event_sheets_flow.dart`) and
  `SheetGuard` is `lib/utils/sheet_guard.dart`; `getCalendarOverviewSettings`
  also returns the markdown palette; the overview serves `AlertKeepNotice`
  (count, and a reload while it is still pending — never `take()`); bloc
  states are parked while the trip holds the guard and adopted once at its
  end; the fold follows the page's own keyboard only; the year and month
  navs wear `overview-nav-*` (declared by the rework, wired only now);
  `EventSheetsFlow.setOccurrencePresence` is the one presence writer the
  panel's toggle shares.

- (2026-10-14, slices 10a–10c, D19–D25) The filter group leaves the page:
  the Period row is the nav's title menu (the same five items), the
  Categories row is the options sheet's first row (the tune badge counts
  the allowlist), the Search row is summoned by the chip row's search
  button and closed by it; the nav's title never opens the jump picker and
  Year's and Month's title boxes are their own (one line at 1.0) while
  List's keeps the span templates; the totals slot is one line;
  `SemanticsIds.overviewPeriod` is retired, `overview-search-open` added;
  flows 05, 23 and 24 walk the menu from the title.

- **The years scroll (2026-10-15, §3.14):** Year mode's span ends at next
  year unless a bounded series, a pinned date or an open-ended series'
  start reaches further (D28), and its chevrons stop there; List mode,
  Month mode and the range picker keep the full bounds. ◄ ► and Today
  scroll instead of paging; the scrubber lane appears in Year mode when
  the span holds two or more years.

## 5. Facts from the tree (`a4f783a`, re-grep before editing)

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
- `lib/pages/calendar_page.dart`: the bar's filter button — since §2.9
  item 17 (2026-10-18) `AutomationId` over `IconButton(isSelected:, icon:
  ExcludeSemantics(Badge.count(child: Icon)))`, the badge on the glyph
  (around the button it was clipped by the 48 dp bar);
  `lib/widgets/upcoming_agenda_view.dart:1228–1240`: the agenda's tune
  button, still `Badge.count` over `AutomationId` over `IconButton` (in no
  bar, so unclipped; its `selectedIcon` would hide a badge placed in
  `icon:`).
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

### Slice 8a — The mode chips and the Period row in every mode (implementer, D12 + D13)

`calendar_overview_page.dart` (the chip row, `_selectPeriod`, the menu's two
arguments gone), `calendar_header_menus.dart` (`presentation` /
`onPresentationSelected` / `_PresentationChoice` removed),
`calendar_header_menus_test.dart` (the presentations group removed),
`overview_robot.dart` (`selectMode` by chip, `currentMode` by the selected
chip), `calendar_overview_page_test.dart` (the header group: the chips in
every mode with the right one selected, the menu without a second group; new
cases: Last 90 days picked in month mode → list mode on it, both persisted;
Custom range… in year mode → the picker → list mode on the span; a cancelled
picker leaves year mode; This year in year mode pages to this year and
stays), flows `05_overview.txt` and `23_overview_list.txt` (the mode steps).
Gate.

### Slice 8b — The detail sheet over the list (implementer, D14)

`lib/utils/sheet_guard.dart`, `lib/controllers/event_sheets_flow.dart`,
`calendar_page.dart` delegating (the suites that drive it unchanged),
`calendar_overview_page.dart` (`_openOn`, the guard, the keep listener,
`forTesting` without `openOccurrence`), `calendar_overview_page_test.dart`
(a row tap opens the sheet with the entry's title and day and pushes no
page route; back closes it and the row is still listed at its offset; a
per-event row opens on its last day; Missed from the sheet dims the row;
the editor's Save from the sheet renames the row), flow 23's tap steps.
Gate.

### Slice 8c — Review, device pass, docs

One `reviewer` over 8a + 8b's diff against §3.11 and §4.1; `qa-runner`:
`qa relaunch --fresh --seed tool/qa/fixtures/calendar.json && qa flows
calendar`, `qa errors`; docs: the feature doc's addendum,
`references/subsystems.md` § Overview, both skills' rule lines, the master's
row, this status line.

### Slice 9a — The period band: the list nav, stepping, home, the totals (implementer, D15 + D16)

`overview_period.dart` (`stepped`), `agenda_period_nav.dart`
(`titleTemplates`, the key), `calendar_overview_page.dart` (the list nav,
`_home`, `_step`, `_goHome`, the title tap into the range picker, the
totals tally and slot in every mode, `_buildCount` gone), four ARB keys ×3,
tests — `overview_period_test.dart` (stepping: a year, a preset, a span,
All time, the bounds); `agenda_period_nav_test.dart` (templates fix the
box); the overview suite: the nav in List mode with the count as its
subtitle and no count caption; ◄ on Last 90 days lists the ninety days
before with the Period row reading the span, Custom checked and nothing
persisted; ► back; Today returns to the preset and is disabled there; This
year ◄ → last year; All time's chevrons disabled; a step at the year bounds
disabled; the title box's height equal across a year, a preset and a
cross-year span at de 2.0; the totals in catalog order, three named and
"+N more", kept only, the missed ones under Missed only; the slot's height
constant between an empty and a full caption and across the three modes —
and flow 23 (◄, ►, Today in List mode; the totals expected by text). Gate.

### Slice 9b — Mark presence (implementer, D18)

`overview_list_options.dart`, `overview_options_sheet.dart` (`mode:`, the
switch), `form_rows.dart` (`FormPickerRow.onLongPress`),
`agenda_day_list_rows.dart` (`onEntryLongPress`, the hint),
`calendar_overview_page.dart` (`_onEntryTap`, the tune button), one ARB key
×3, tests — the sheet: enabled in List with every-occurrence rows and in
Month, disabled in Year and under One per event, turned off by a Rows
change; the page: a tap while marking dispatches
`SetOccurrencePresence(eventId, day, missed)` and the kept row dims once
the state says so, a second tap dispatches present, a non-tracking event's
row opens the sheet, a long press opens the sheet, the tune button reads
selected, off → a tap opens the sheet as before — and flow 23 (switch on,
tap a row, the header's count changes, tap again, switch off). Gate.

### Slice 9c — Saved views (implementer, D17; load `drift-migrations`)

The table, schema v41, the migration, `build_runner`, the DAO, the service,
the model and its codec, the backup key, `schema-lineage.md`'s v41 line,
`overview_view_sheet.dart`, the shareable name dialog, the bar button and
`_applyView` in the page, the ARB keys ×3, the ids, tests —
`overview_view_test.dart` (codec round trips, forward compatibility);
`overview_view_service_test.dart` against `NativeDatabase.memory()` cloned
from the preset service's suite (the cap, soft delete, reorder, export /
import); the upgrade-chain test extended to v41 and the backup parity test
gaining the key; `overview_view_sheet_test.dart` through a robot (save,
apply, rename, update, delete, the limit) and the clearance test entry; the
overview suite (the button, `isSelected` on a match, applying restores the
period, the options and the categories and switches to List) — and the
flow `24_overview_views.txt` (save the current list under a name, change
the period, apply the view, rename, delete). Gate.

### Slice 9d — Review, device pass, docs

One `reviewer` over slices 9a–9c's whole diff against §3.12 and §4.1;
`qa-runner` (`qa run`, `qa relaunch --fresh --seed`, `qa flows calendar`
with the 24th flow, the matrix on the three modes, the views sheet and the
options sheet); docs: the feature doc's addendum, `references/
subsystems.md` § Overview, `references/schema-lineage.md`, the
`calendar-events` rule lines (the view service and table, stepping,
presence from rows), the `calendar-ui` ids and flow count, the master's
row, this status line.

### Slice 10a — The page, the sheet, the nav, the primitive (implementer)

§3.13 whole: `showFormMenu` hoisted and `FormMenuRow` on it;
`FormSearchRow.focusNode`; `AgendaPeriodNav.onTitleTap` with the title's
context and the day list's two callers; the page — the search button and
the summoned Search group, the filter group deleted, the nav's title menu,
`_pickListRange` and the jump picker gone, the per-mode title boxes, the
one-line totals; the options sheet's Categories row and the page's
callback; the tune badge; the ids; the three flows; the robot and the
suites; the gate.

### Slice 10b — Review and the fix pass

One `reviewer` over slice 10a's diff against §3.13 and §4.1 (its
2026-10-14 bullet); confirmed defects fixed by the lead or one
`implementer`; the gate again.

### Slice 10c — Device pass and docs

`qa-runner`: `qa relaunch --fresh --seed tool/qa/fixtures/calendar.json`,
`qa flows calendar` (05, 23 and 24 green; 19 red as before), the matrix
(`qa set theme=dark locale=de text-scale=2.0`) on the three modes with the
search open and closed, the title's menu at 200 % (on screen, nothing
clipped), the options sheet, both phone sizes, `qa errors` clean. Docs:
the feature doc's addendum, `references/subsystems.md` § Overview (the
chrome paragraph), the `calendar-ui` catalogue (the ids, the
`AgendaPeriodNav` line, the flows), the master's row, this status line.

### Slice 11 — The years scroll (implementer, Opus 5.5, high)

§3.14 whole but the scrubber and the benchmark: `AgendaYearScroll` and its
controller, the shared tile builder lifted out of `AgendaYearGrid`,
`YearMonthTile.columnsFor`, the `OverviewListMetrics` numbers
(`yearHeaderHeight`, `yearHeaderFontSize`, `yearSectionGap`,
`yearScrollPadding`), `yearBoundsOf`'s ceiling, the page's Year case on
the scroll with the viewport queue and the synchronous open and landing,
the two `SemanticsIds`, the new suite and the re-targeted Year block, the
two flows' Year steps edited (not run). Gate: `dart analyze lib`, the
whole `flutter test`, no ARB expected (`gen-l10n` if one is touched).
Reviewer after it: the §4.1 bullet, the D26–D30 letters, the "never in
build" rule, one marks call per run, the first frame on the right year.

### Slice 12 — The scrubber, the benchmark, the device pass, the docs (implementer; qa-runner; docs-writer)

The Year-mode `ListScrubber` (D29) with its tests; `overview_years_benchmark_test.dart`;
`qa relaunch --fresh --seed tool/qa/fixtures/calendar.json` then `qa flows
calendar`, the matrix (dark, `de`, 2.0, both sizes), `qa errors`; then the
feature doc's addendum, `references/subsystems.md` § Overview, the
`calendar-events` rule lines, the `calendar-ui` file table and device
pass, this record's status line and ledger.

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

- ~~**D1 · B — the detail sheet over the list.**~~ Shipped on 2026-10-13 as
  D14 · A (slice 8b, `EventSheetsFlow`, §3.11): the "rework of its own" was
  one slice once it was noticed that the overview already reads the
  app-wide bloc.
- **A guard for declared-but-unworn ids** (the 2026-10-13 review's finding
  2): the rework declared `overview-nav-previous` / `-next` / `-today` /
  `-title` in `SemanticsIds` and the catalogue listed them, but no widget
  passed them until slice 8c's fix pass, and only a device run would have
  shown it. A test that every `SemanticsIds` constant (and every helper's
  prefix) has a reader under `lib/` other than the constants file would
  have caught it at the gate; it belongs to the QA harness's suites
  (`test/qa/`), not to this record's area.
- **The list at the extreme cell** (slice 9a): at German 200 % on
  360 × 780 the band under the filter group — a two-line nav box (every
  period label wraps there, not only the cross-year span) over a two-line
  totals slot — leaves the list a 50 dp viewport (471 at en 1.0 on 412),
  so the pinned label always yields there. A one-line totals slot past
  160 % (`FormChip`'s own threshold) would give 40 dp back at the cost of
  an ellipsized caption; the owner decides after living with it. The
  pinned-label de 2.0 case runs on the 412 phone since this slice.
- **Stale semantics on a page after a popup leaves — a navigator observer**
  (2026-10-14, the review's finding 1, CONFIRMED by the fix pass: in Year
  mode a title-menu pick of Last 90 days switches to List and grows the
  band from one line to two while the menu route is still leaving;
  `overview-nav-next` is painted at `LTRB(308, 170, 356, 218)` and its
  semantics node reports `LTRB(308, 160, 356, 208)`, 10 dp stale, the
  totals caption 20 dp; the reproduction is
  `calendar_overview_page_test.dart` ~1769, kept `skip: true` with the
  reason). `FormSheetSemanticsRefresh` cannot help a page: it listens to
  the route's `secondaryAnimation`, and a `PageRoute`'s only follows other
  page routes (`canTransitionTo` is `nextRoute is PageRoute`), so a
  popup's leaving never reaches it. The fix that works for every page and
  every sheet at once: a `NavigatorObserver` registered in `main.dart`
  beside the app's `RouteObserver` whose `didPop(route, previousRoute)`
  awaits `route.completed` (a `TransitionRoute`'s future, resolved on its
  dispose, after the leaving transition and the barrier's removal) and
  then walks `previousRoute.subtreeContext?.findRenderObject()` with
  `markNeedsSemanticsUpdate()` (hoist `FormSheetSemanticsRefresh._markSubtree`
  into a shared helper); `markNeedsSemanticsUpdate` returns at once while
  no semantics owner exists, so with TalkBack off it costs nothing, and
  with it on one subtree geometry pass per pop. It subsumes
  `FormSheetSemanticsRefresh` on the two sheets. About thirty lines plus
  the un-skipped test; app-wide, so the owner's call. Until then the stale
  rects last until the band's next layout (a mode switch, the keyboard
  fold, a scale or locale change); a tap by id still lands inside the
  48 dp button, TalkBack's highlight is drawn 10 dp off.
- **`FormSheetSemanticsRefresh` beyond the two sheets that carry it**: the
  framework bug it works around (a sheet resizing while the dialog or
  menu above it is still leaving keeps stale semantics geometry — a
  TalkBack defect, not only a harness one) can hit any content-tall
  sub-sheet that resizes on a dialog's answer and any `FormSheetFrame`
  sheet that adds rows after a picker; adopting it inside
  `FormSheetFrame` and the sub-sheet chrome is an app-wide decision for
  `docs/ui-language-adoption-roadmap.md`, and the bug deserves an
  upstream report with the minimal sheet the investigation wrote.
- ~~**The Categories row's value can wrap at 200 %**~~ — the row moved
  into the options sheet on 2026-10-14 (D22 · A) and took `singleLine`
  there, so the sheet never re-lays out on the picker's answer; the price
  is the review's finding 2: at German 200 % beside a long read-back
  ("Kraft, Gesundheit +2 weitere") the label "Kategorien" can ellipsize,
  as the day list's single-line read rows can. The owner decides after
  living with it; the alternative is the wrap layout under
  `FormSheetSemanticsRefresh`, which would move the rows below on a pick.
- **The search button and the chips at a large text scale** (2026-10-14,
  the review's finding 7): the button takes 48 dp from the chip row, so
  "Jahr · Monat · Liste" wraps onto a second run from about 150 % rather
  than 180 %; the fold still travels over the 1.0-scale `_chipRowHeight`,
  the existing rule, and the page fits at 360 × 780 × 2.0 with the
  keyboard up. And while the keyboard is up the chips fold away with the
  button, so closing the search takes the keyboard's back first — the
  spec's "fold unchanged", which the owner may notice. Both for the owner
  after the device pass.
- **`filterPresetLimitReached` in Romanian** has the same missing "de" as
  the views' key had ("50 de filtre"); the presets are not this record's.
- **The fold under a steady small inset** (finding 6a): a floating
  keyboard's strip or a hardware keyboard's toolbar leaves the chip row
  half-folded and its visible half live; snapping to whole or folded past a
  threshold would need a measured row height per text scale.
- ~~**D11 · B — a stepping nav in list mode.**~~ Asked for by the owner on
  2026-10-13 and built as D15 (slice 9a, §3.12).
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
- **Collapsible months**, **Last 30 days / Year to date** (D2 · B).
  ~~Per-category totals~~ and ~~saved views~~ were asked for on 2026-10-13
  and built as D16 and D17 (slices 9a and 9c, §3.12).
- **The jump picker's day wheel** and the **two-line sheet header at 200 %**
  (Tier 3 §8) stay open.
- **Four Mark presence tests log `Presence write error:
  MissingPluginException(…path_provider)`** (`calendar_overview_page_test.dart`):
  they emit the presence bump by hand, so routing their write through
  `EventPresenceService.forTesting(db)` (as the years scroll's forget test
  does) would double-bump; a shared fake write for the four is the fix.
- **List mode's `_listMore` still runs `store.ensure` during the build
  phase** on the `didChangeDependencies` path (a locale change or a
  category-label refresh); the years scroll's `_rebuild(duringBuild: true)`
  defers its resolve to a post-frame callback and the list's first batch
  should do the same.
- **Formatter drift.** The installed `dart format` (Dart 3.10's) rewrites
  about 145 files the tree was not formatted with; whether to format the
  tree in one commit is the owner's decision — until then nobody formats
  beyond their own lines.
- **New files on LF** (`agenda_year_scroll.dart`, `agenda_year_scroll_test.dart`,
  `overview_years_benchmark_test.dart`, and `overview_list_metrics.dart`
  rewritten): `core.autocrlf=true` normalizes them on commit and they
  come back CRLF on the next checkout; nothing to do unless a tool checks
  the working copy's endings.
- **Back with an empty summoned Search pops the page** (device pass
  2026-10-15, every mode): `key back` with the Search row open and no
  query leaves the overview instead of closing the row first; a
  `PopScope` that closes the row when it is open is the fix, with the
  flow step that pins it.
- **The year tiles' month labels at 2.0 in de** ellipsize to "Jan. …" /
  "März…" / "Sept.…" (device pass 2026-10-15, the pager had the same): the
  tile's one-line `labelLarge` label shares its row with the count; a
  shorter de label form at large text, or the count under the label past
  a scale, is a `YearMonthTile` decision for the tile's three surfaces at
  once.
- **Flow `19_fasting_schedule` is stale**: red before and after the
  rework at step 17 (`expect id:fasting-extra-days`, the dump has
  `fasting-days-off` only), and its open dialog poisons every later flow
  of a one-shot run; the flow (or the id) needs the fasting sheet's owner
  to look.
- **The 360-wide device check** of Year mode was not run (the emulator
  was up as the 412 profile and `qa boot --phone` refuses beside an
  attached device); the arithmetic says the fourth tile row fits a
  780 dp screen with 38 dp to spare (§2.6), the widget suite pins
  360 × 780, a phone pass still owes the look.
- **The scrubber lane lands between years** (it maps the drag
  proportionally, as the list's does); a snap to the nearest header on
  release is a possible refinement, not asked for.
- **Flow 23's native swipe is one device's** (the 2026-10-17 device pass,
  on `Medium_Phone_API_36.1`, 1080 × 2400 @ 420, the AVD on the Mac): step
  82's `swipe up --from 1208,1800 --dist 1000` is in the Pixel_9_Pro's
  physical pixels (its own comment says so); on the smaller AVD x clamps to
  1032 and the drag ends inside the lane, so the checkup at today − 40 is
  not reached and the flow is red at step 82, before the presence steps.
  With the swipe alone changed to `--from 1032,2200 --dist 1900` every one
  of the 128 steps passed, the presence steps and `23_overview_list_marked`
  included. The fix is a per-device swipe, or a logical-coordinate `swipe`
  in the harness; the repo flow is unchanged.
- **Flow 24's step 32 races the "Saved as" snackbar** (the same pass):
  `tap "Ninety days"` finds two matches — the saved view's row and the
  snackbar still up from the save — and a plain tap on the row is swallowed
  by the overlay for about six seconds; after a wait the rest of the flow
  passed. A `wait --gone` on the snackbar's text, or the harness preferring
  the match outside the overlay, is the fix.

## 9. Ledger

- **2026-10-11 — PLAN.** Read of the list mode at `a4f783a`; one
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
- **2026-10-13 — follow-up IN PROGRESS.** The owner committed the rework as
  `c4f5697` on 2026-10-12 and used it on the phone: the twelve-month mode
  "gone" (the switch in the title menu, the mode persisted), the Period row
  disabled (month mode), back after a row tap onto the pushed calendar.
  D12–D14 asked and answered A, A, A (§2.3); §3.11, the §4.1 addition and
  slices 8a–8c written; at dispatch nothing was in the tree beyond this
  record and the master's row.
- **2026-10-13 — slices 8a and 8b done, the review, the fix pass.** Slice 8a
  (`implementer`, Opus 5.5): `_buildModeChips` (Year · Month · List,
  `FormChipRow(indented: false)` under the bar), `CalendarViewMenu` without
  `presentation`, the Period row live in every mode (`_selectPeriod`
  resolves the period first, `_listPeriod` switches), the robot on the
  chips, flows 05 and 23 on the chips; one deviation accepted by the lead —
  the chip row folds with the keyboard (the page overflowed by 50 px at
  360 × 780 × 2.0 with it up), changed on the lead's word from a
  `Visibility` pop to an inset-coupled `Align(heightFactor)` over
  `_chipRowHeight`; `+7527 ~8 -1`. Slice 8b (`implementer`, Opus 5.5):
  `SheetGuard` → `lib/utils/sheet_guard.dart`, the trip → `EventSheetsFlow`
  (`openDetail` / `openEditor` / `editorSheet` / `openLinkedNote`,
  `setOccurrencePresence` public for the panel's toggle), the calendar page
  delegating, the overview owning a guard, a flow, a Keep listener and the
  palette (`getCalendarOverviewSettings` gained it — the loaded state holds
  none), `forTesting(onStore:)`, six new tests, four re-targeted from the
  push to the alert path, flow 23 with one back; `+7532 ~8 -1`. Review
  (`reviewer`, Opus 5.5, read-only, the two untracked files included): 11
  findings — (1) PLAUSIBLE and real: the overview taking the Keep notice
  defeated the pushed calendar's `_predatesKeep`, so an Open event right
  after a Keep could open the sheet on the copy still marked remove-after;
  (2–3) CONFIRMED: the four `overview-nav-*` ids declared by the rework were
  never wired, so both flows' waits would fail, and flow 05's month wait was
  satisfied by the year nav; (4) a vacuous offset test; (5) test gaps; (6)
  the fold — a steady small inset half-folds, 2.0 folds faster than the real
  height, a sheet's keyboard folded the row behind it; (7) PLAUSIBLE: a
  whole-period re-resolution per tick under the sheet; (8) three stale
  comments; (9) a `path_provider` handler and a closed cached database left
  behind by one group; (10) a scan worth a line; (11) four LF files
  (normalized by the lead through temp files). Fix pass (the 8b
  implementer resumed): the overview never `take()`s — count, reload while
  pending (three tests); the four ids wired in both navs (one test); the
  offset test on a mid-list row; the fold gated on `ModalRoute.isCurrent`
  (one test); states parked while the guard is open and adopted once at the
  trip's end (two tests re-targeted, one new on the `onStore` seam); the
  comments; `tearDownAll` through `AppDatabase.deleteAllData()`; the line
  on `_openOn`; `+7536 ~8 -1`. Flow 05 rewritten by the lead to Year → List
  → Month → Year, Year waited on two tile labels (`Jan {{year}}`,
  `Jul {{year}}` — the tiles read `DateFormat.yMMM`, the month nav spells
  its month out). Docs placed by the lead: this record (§2.3, §3.11, §4.1,
  §4.2, §6, §8), the feature doc's addendum 2026-10-13, `references/
  subsystems.md` § Overview, the `calendar-events` and `calendar-ui` rule
  lines, the master's row. Device pass: next.
- **2026-10-13 — slice 8c done; IMPLEMENTED, uncommitted.** Device pass
  (`qa-runner`, Sonnet 5.5, Pixel_9_Pro, `ANTA_QA_VIA=agent`): `qa run`,
  `qa relaunch --fresh --seed`, `qa flows calendar` 23 / 24 —
  `19_fasting_schedule` red at its known step (its sheet left open cascaded
  into 20–23 in the full run; the four re-run alone all passed, 23 with the
  row tap, `event-detail-close` and one `key back`), `05_overview` green in
  the full run; `qa errors` clean twice. Matrix at de · dark · 2.0 and ro ·
  light · 1.0 at 427 × 952 and 360 × 800 (the wrapper's `--phone` size;
  360 × 780 and 412 × 915 are not settable): the chips, the Period menu, the
  detail sheet over the list in List and in Month mode, one back onto the
  row — right at both sizes. Two "clips" the runner reported (the pinned
  label reading "OMBRIE 2026", the caption's number hidden, the German year
  nav's count "overlapping" the chevrons) are the harness's semantics-overlay
  badges painted over the first characters — the English shots read
  "#16 OBER 2026" the same way; the screens are intact. Not verified on the
  device: the chip row's fold under a real keyboard — the harness never
  raises one (the agent owns text entry) and the VM-service inset recipe was
  refused by the permission classifier, so the fold rests on the widget
  tests (half at half, gone past, whole at zero, whole under a sheet's
  keyboard). Final gate on the lead's own run: `dart analyze lib test tool
  test_driver` clean, `flutter test` `+7536 ~8 -1`, `untranslated.txt` `{}`.
  19 uncommitted files; the owner reviews and commits.
- **2026-10-13 — second follow-up IN PROGRESS.** The owner asked for three
  §8 items and one new one ("decide each with Fable first, then implement
  with whatever you see fit"): D15–D18 decided by the lead (§2.4), §3.12,
  the §4.1 addition and slices 9a–9d written on the facts one `explorer`
  (Haiku 5.5) gathered; at dispatch nothing in the tree beyond this record.
- **2026-10-13 — slice 9a done (the period band).** `OverviewPeriod.stepped`,
  `AgendaPeriodNav.titleTemplates` (the LRU key gains `templates`), the
  list nav with the count as its subtitle (`_buildCount` gone), `_home` /
  `_step` / `_goHome`, the title tap into the range picker, the totals slot
  in every mode (`OverviewListMetrics.namedTotals = 3`, `totalsMaxLines =
  2`), four ARB keys ×3, flow 23's nav steps; `+7556 ~8 -1`. Deviations the
  lead accepted: the band folds with the keyboard as the chips do (the
  keyboard case at 360 × 780 × 2.0 overflowed by 126 dp otherwise — the
  year nav folds while a search is typed now); Month mode's nav stays in
  its scroll view with the totals under it; Year mode's totals come from
  the tiles' marks (`_markedKept` per category per month, cleared with the
  store) so the marks-only tiles stay marks-only, and from rows once a
  month is loaded as rows or a query is live; Month mode's totals cover the
  whole month; list totals are counted as each batch lands; `_home`
  follows New Year in every mode; `_setPeriod` sets `_home` before its
  unchanged-pick return; the span templates are "MMM 10 – MMM 28" on the
  widest month and that month's 28th to the same date a year later; de and
  ro carry placeholder metadata blocks. Decided by the lead on the report:
  the 50 dp list at de 2.0 on 360 × 780 accepted (§8) and the pinned-label
  de 2.0 case moved to the 412 phone; the nav's height unified across the
  three modes — one `_titleTemplates(l10n)` (the presets, a year, the two
  spans and this year's twelve month titles, cached per locale and year)
  handed to all three navs, the month nav keeping `month:`; the list nav's
  title tooltip `overviewPeriod`, the range mode's own header title. Flow
  23 steps ► first (the seed holds nothing in the ninety days before Last
  90 days). Not verified: the device.
- **2026-10-13 — slice 9b done (Mark presence).**
  `OverviewListOptions.markPresence` (session-only), the options sheet on
  `mode:` with the switch (`how_to_reg_outlined`, `overview-mark-presence`;
  enabled in List with every-occurrence rows and in Month; a Rows change
  to One per event turns it off), `FormPickerRow.onLongPress` and `hint`
  (the second field a deviation the lead accepted: a `MergeSemantics` from
  outside would have merged the day list's pencil into the row),
  `AgendaDayListRowBuilder.onEntryLongPress` / `entryHint`, the page's
  `_marks` / `_onEntryTap` (a tap marks through
  `EventSheetsFlow.setOccurrencePresence`, a long press opens the sheet,
  the hint `eventMarkMissed` / `eventMarkPresent`), the tune button
  selected while marking can act — not in Year mode, the lead's fix of the
  implementer's literal reading — one ARB key ×3, flow 23's marking steps
  (checked through Missed only by id: the day header's count depends on
  the weekday and the harness cannot express its newline); `+7570 ~8 -1`,
  the two suites `+154` after the fix. Not verified: the device,
  TalkBack's reading of the hint, the long press on Android.
- **2026-10-13 — slice 9c done (saved views).** `overview_views` (v41, the
  presets table's shape with the blob as `payload`, a frozen `CREATE TABLE
  IF NOT EXISTS` in `_migrateV40ToV41`, `DatabaseSchema.currentVersion =
  41`), `OverviewViewDao` (the preset DAO's twin, stamping in the DAO),
  `OverviewView` (`toJson` / `fromJson`: the period as `{kind, year |
  preset | start, end}`, options by name, sorted categories, `markPresence`
  never written; unknown kind, preset or date → this year; `matches`
  ignores `markPresence`), `OverviewViewService` (`maxViews = 50`,
  `matching`, `create` → null when full, the serialized write chain, export
  / import, the lifecycle reset), the backup key `overviewViews` (additive,
  no strand rule, archive version 1), `OverviewViewSheet` (the preset
  sheet's chrome: search past `listSearchThreshold`, the save row disabled
  while the shown list is saved or a query is live, the ✓ on the match, the
  ⋮ with Rename / Update to current list — disabled while in use / Move to
  top / Delete, drag reorder; the preset sheet's name dialog reused as it
  stands — it already takes a title), the bar's `_buildViewsButton`
  (selected on a match, disabled until the service loads), `_openViews`,
  `_applyView` (List mode; the period, options and categories restored and
  persisted as a pick would; the store rebuilt when the allowlist changed,
  as `_pickCategories` does; `_year` and `_selectedDay` reset;
  `markPresence` carried), ten ARB keys ×3, eleven ids, flow 24, the
  lineage reference's v41 line; tests: 11 model, 18 service, 10 sheet, 4
  page, the upgrade chain, the schema parity, the backup round trip, the
  clearance entry; `+7618 ~8 -1`. Deviations the lead accepted: the row
  caption and the save dialog's suggested name are the period's
  `menuValue`; "Update to current list" stores `markPresence` false; the
  ⋮ and handle ids carry the view's id. Not verified: the device (flow 24's
  `type` into the dialog and the ⋮ by tooltip are assumptions), dark, ro,
  412 × 915, an upgrade of a real v40 database through the app.
- **2026-10-13 — the review of 9a–9c and the fix pass.** Review
  (`reviewer`, Opus 5.5, read-only; it hit its turn limit once and was
  resumed to report): no data-loss or compatibility defect; 12 findings —
  (1) PLAUSIBLE and real: a presence mark bumped `presenceRevision`, the
  page dropped the whole store and relisted the first `syncMonths`
  synchronously, so on All time scrolled far down the list shrank under
  the finger and a second tap could mark the wrong day; (2) with the
  missed display hidden a mark removed its row with no way back; (3)
  marking could read "on" in List mode with One per event (a mode switch,
  a per-event view); (4) a "This year" view pinned the year's number —
  decided by the lead: rolling, a `thisYear` kind; (5) ◄ then ► left a
  custom span equal to the preset; (6) the widest month by character
  count, not pixels; (7) flow 24's `wait "Save"` ambiguous under the
  harness's substring pass; (8) flow 23's totals text too loose and ► on
  Dec 31; (9) `dart format` drift in seven new files; (10) the Romanian
  "50 de vizualizări"; (11) two stale doc lines (fixed by the lead); (12)
  very low: a double tap dispatching missed twice, two taps on the views
  sheet popping twice (the presets share it), an unlabeled empty totals
  node. Not covered by the review: `query_count_test` for the views DAO,
  a line-by-line ⋮ comparison with the preset sheet, the stale-`///`
  sweep. Fix pass (a fresh `implementer`, Opus 5.5): `AgendaMonthStore.forget(month)`
  and the page's `_pendingMarks` — a bump that only moves
  `presenceRevision` by as many marks as are pending forgets their months
  and re-resolves them at once, the store kept, every other bump the full
  rebuild as before (the frame-by-frame test fails with the fix reverted:
  the offset fell from 305 431 to 128 175 on the first frame);
  `missedHidden` on the options sheet and marking turned off when the
  appearance hides missed entries; `_dayRowsShown` gating the tune button,
  `_selectMode` and `_applyView`; the `thisYear` kind (`toJson({today})`,
  decode with today); `_step` landing on `_home` when the spans match;
  span templates for all twelve months; `filterPresetName` /
  `filterPresetNameSave` ids on the shared name dialog and flow 24 waiting
  on them; flow 23's `expect "Gym 4 · Other" "Strength 8"` and the order
  ► Today ► ◄; the seven files formatted; the Romanian value; the empty
  totals node excluded; `+7630 ~8 -1`. Deviations accepted: pending marks
  are consumed as many as the revision moved, cleared when a state is
  parked, and a bump larger than the pending list falls back to a new
  store; a forgotten listed month is re-resolved in `_forgetMarked`
  itself; renaming or updating a view re-encodes its period with today's
  date, so a future year's view edited in that year becomes "this year".
- **2026-10-13 — the device pass of 9a–9c** (`qa-runner`, Sonnet 5.5,
  Pixel_9_Pro): a plain `qa run` over the emulator's v40 database upgraded
  it to v41 with nothing in `qa errors`; `qa flows calendar` 24 / 25 —
  `19_fasting_schedule` red as known (20–22 re-run alone, green), `23_overview_list`
  green with the nav steps, the totals text and the marking through Missed
  only, **`24_overview_views` red at step 24 and reproduced on a fresh
  relaunch**: right after the name dialog saves a view the sheet's ✕ does
  nothing (the scrim and back close it; reopened, the ✕ works) — an app
  defect; `qa errors` clean three times. In words: a ◄ tap at en 1.0 moves
  nothing; at de 2.0 the Period row's value wraps for a stepped span and
  the whole filter group grows by about 40 dp, moving the nav and the list
  under the finger — the row, not the nav; a row tap while marking flips
  the hint and the dimming at once and the totals follow; a tap on the
  totals does nothing. Matrix (de · dark · 2.0 and ro · light · 1.0, the
  default size and 360 × 800): the Mark presence row wraps to two lines and
  clips nothing; the view row's ⋮ has its four items; the saved view shows
  in de and ro; the Romanian page title is clipped at 1.0 ("Prezentare
  gene…") now that the bar has three actions, the German one at 360 × 2.0;
  in Month mode the Period row read the stepped span while the nav read
  the month; the "cut" first day card in the English shot is a row
  half-scrolled under the viewport's top, normal. Second fix pass
  dispatched for the ✕, the Period row's one height (`singleLine`),
  `_shownPeriod` in Month mode and the Romanian title ("Sumar").
- **2026-10-13 — the second fix pass** (the same `implementer` resumed):
  the dead ✕'s root cause is `OverlaySnackbar`'s box — a coloured
  `Material` 76 dp tall, 80 dp above the bottom, absorbing every tap
  inside it, so on a short sub-sheet it covered the lower part of the
  header's ✕ until the message timed out; fixed once in
  `lib/widgets/overlay_snackbar.dart` (a transparent `Material` over a
  `PhysicalModel`; only the text line and the ✕ take taps; the text stays
  tappable because nine existing suites pin "where a finger can reach the
  message") with a regression test that failed before the fix (a ✕ whose
  tap point falls on the text line itself would still be blocked — the
  device's sits above it). `FormMenuRow.singleLine` added and set on the
  Period row (the nav's top unchanged across a year, a preset and a
  stepped span at de 2.0 on both widths — 40 dp of movement before);
  `_shownPeriod` in Month mode reads `OverviewYearPeriod(_month.year)`
  (the range picker, "Save the current list" and the views' match follow
  it there); the Romanian `calendarOverview` "Sumar"; `+7635 ~8 -1`.
- **2026-10-13 — the device re-run** (`qa-runner`): 24 / 25 again —
  `23_overview_list` green (122 steps), the three checks green: after ◄ at
  de 2.0 on 360 × 800 the nav and the list stay put (1956 both before and
  after; the Period row one line with an ellipsis on a long span); the
  Romanian bar reads "Sumar ▾" unclipped beside its three actions; a real
  touch on the painted ✕ closes the views sheet on the first tap with
  "Salvat ca …" still up. **`24_overview_views` still red at step 24, for
  a new reason**: after the sheet resizes (a saved view adds a row; a
  deleted one removes it) the semantics tree the harness taps by reports
  the old geometry — the ✕ at y 2328–2472 while it is painted at about
  2210, the save row at 2307 while painted at 2566 — and the dump stays
  stale 25 s later, so an id tap misses while a raw tap at the painted
  position works at once. App semantics or harness snapshot: unknown;
  an investigation with a widget test (the painted rect against the
  semantics node's global rect after a save and a delete) dispatched —
  if the app's tree is stale it is an accessibility defect the preset
  sheet shares. `qa errors` clean twice. Also noted: the "Salvat ca …"
  message covers most of the saved view's row on a short sheet while it
  is up.
- **2026-10-13 — the stale-semantics investigation** (a fresh
  `implementer`, Opus 5.5): **the app was at fault, and it is a Flutter
  3.44.2 framework bug.** `await showDialog(...)` resumes as soon as the
  dialog pops, while its barrier is still animating out and its
  `BlockSemantics` still blocks the sheet beneath; a sheet that resizes
  in that window has its geometry pass skipped for the blocked branch
  (`PipelineOwner.flushSemantics` drops it), and once unblocked nothing
  marks the branch dirty — `_RenderObjectSemantics._updateGeometry`
  rebuilds a node only when its size or visibility changed, so a node
  that merely moved keeps its old transform until its next layout. A
  minimal sheet with no app code shows it; a plain `setState` resize is
  fresh. In the widget test the ✕ was painted at y 757 and reported at
  820 after a save (one row), the save row painted at 876 and reported
  at 813 after a delete; the preset sheet showed the same (695 against
  758). Fix: `FormSheetSemanticsRefresh` (`lib/widgets/form_sheet_frame.dart`)
  listens to the sheet route's `secondaryAnimation` and, when the route
  above has finished leaving, walks the sheet's render subtree once with
  `markNeedsSemanticsUpdate()`; both sheets' `show` builders wrap their
  box in it. Tests: a save and a delete on the views sheet, a save on the
  preset sheet (painted and reported centres within 1 px; red before the
  fix), the helper `test/widgets/support/semantics_geometry.dart`;
  `+7638 ~8 -1`. Flow 19 is probably not this (no route leaves over the
  fasting sheet before its failing step; its id more likely sits just
  past the viewport, where Flutter drops a scrollable's clipped nodes).
- **2026-10-13 — IMPLEMENTED, uncommitted.** The device re-run
  (`qa-runner`): `24_overview_views` green, all 70 steps, `23_overview_list`
  green again (122 steps), `qa errors` clean. The lead's own gate on the
  final tree: `dart analyze lib test tool test_driver` clean, `flutter
  test` `+7638 ~8 -1`, `untranslated.txt` `{}`; 71 uncommitted files; the
  owner reviews and commits.
- **2026-10-14 — PLAN, the third follow-up.** The owner's read of the chips
  after a day (§2.5); the numbers from the tree (404 dp above the first
  tile against 504 for the tiles on 360 × 780; the two-line title box in
  every mode); one mock (https://claude.ai/artifact/GSMUfABr93vsP1cyknoGsp);
  D19–D25 answered "Okay, you may start implementation" — the recommended
  A stands for each; §3.13, §4.1's and §4.2's bullets, slices 10a–10c. 71
  files were already uncommitted from the two follow-ups when this started;
  the owner commits.
- **2026-10-14 — slice 10a built** (one `implementer`, Opus 5.5): §3.13
  as written, with these deviations kept: the robot's `periodChoice` and
  `categoriesValue` are async (they open the menu and the sheet);
  `_toggleSearch` clears when the field's text *or* the query is non-empty,
  so a keystroke still on the 200 ms debounce never applies behind a closed
  row; the exact 134 dp geometry pin runs at 412 × 915 because the test
  font's square glyphs wrap the chips onto a second run at 360 (there the
  test pins the nav at 52, the totals at 26 and the December tile above
  the fold); Month mode's nav is pinned relative to Year's and List's,
  not at 52, for the same font reason; flow 23 takes one more screenshot
  (`23_overview_options_categories`). Gate: `dart analyze lib test tool
  test_driver` clean, `flutter test` `+7652 ~8 -1` (the known Windows-only
  `host_devices_test` case), no ARB touched.
- **2026-10-14 — slice 10b review** (one `reviewer`, Opus 5.5, read-only):
  no data-loss, persistence or crash defect; D13 · A, `_setPeriod`,
  `_listPeriod`, `_step`, `_goHome`, `_home`, `_applyView` and Mark
  presence as before. Findings, most severe first: (1) PLAUSIBLE — a
  title-menu pick in Year or Month mode runs `_listPeriod` while the menu
  route is still leaving, and with the title box per mode the band grows
  from one line to two, so the nav's buttons and the totals move under a
  blocked semantics tree (the 2026-10-13 Flutter stale-geometry case; the
  page carried no `FormSheetSemanticsRefresh`); (2) PLAUSIBLE — the
  options sheet's Categories label can ellipsize at German 200 % beside a
  long read-back, the price of `singleLine`; (3) CONFIRMED — dead code,
  `FormMenuRow.singleLine` with no caller once the row went; (4) CONFIRMED
  — a circular import, `form_menu_item.dart` importing `form_rows.dart`
  for `FormMenuItem`; (5) CONFIRMED — flow 05's wait after the Month tap
  passed at once (List's nav wears the same id) so the Month screenshot
  could catch the cross-fade; (6) CONFIRMED — stale comments naming the
  Period row in five files; (7) PLAUSIBLE, low — the search button takes
  48 dp from the chips, which wrap onto a second run sooner at a large
  text scale; (8) low — the page-level menu-position test pinned "below
  the title" only, and no test read an archived chosen category back
  through `visiblePlus`. Clean: `_openPeriodMenu` and `_toggleSearch`'s
  lifecycle, `_onCategoriesChanged` against `_applyView`, the moved
  picker, the badge, the `Builder` around the title (no extra node, id and
  tooltip kept), the per-mode boxes and the templates' cache key, the
  totals, the Search group outside the fold and the page at 360 × 780 × 2.0
  with the keyboard up, the flows' ids and verbs, `FormMenuRow`'s
  behaviour, no new strings. Fix pass (one `implementer`, medium): 1 as a
  test first and the wrap only if red, 3, 4 (`FormMenuItem` moved into
  `form_menu_item.dart` and re-exported from `form_rows.dart`), 5, 6, a
  sheet-height-unchanged-across-a-pick test for 2, the right-edge pin for
  8; 2's label and 7 to the device pass and §8.
- **2026-10-14 — slice 10b fix pass** (one `implementer`, Opus 5.5,
  medium): `FormMenuItem` moved into `form_menu_item.dart` and re-exported
  from `form_rows.dart` (the cycle gone); `FormMenuRow.singleLine` deleted;
  flow 05 waits for `overview-list --gone` after the Month tap; the stale
  "Period row" comments rewritten in seven files (the agenda filters
  sheet's own Period row keeps its name); the options sheet keeps its
  height across a pick (382 dp, and 408 with `singleLine` off, so the test
  bites); an archived chosen category reads back through `visiblePlus`;
  the menu's right edge pinned to the title's — with the route's 8 dp
  clamp where the test font's 280 dp menu does not fit beside a short
  title. **Finding 1 is real and not fixed here**: the test is red, the
  `FormSheetSemanticsRefresh` wrap leaves it red (a page route's
  `secondaryAnimation` never follows a popup), the wrap was taken out and
  the test kept `skip: true`; the observer that fixes it app-wide is in §8.
  Gate: `dart analyze lib test tool test_driver` clean, `flutter test`
  `+7654 ~9 -1` (the known Windows-only `host_devices_test` case; two new
  sheet cases, one skipped), no ARB touched.
- **2026-10-14 — slice 10c device pass and docs — IMPLEMENTED,
  uncommitted.** `qa-runner` (Sonnet 5.5) on the Pixel_9_Pro: the first
  installed build was stale (the old filter rows), so a plain `qa run`
  preceded the results; flows 00–18 green, 19 red as before and its open
  dialog failing every later flow's first step in the one-shot run, 20–24
  green one by one, 23 red twice on data the earlier flows had mutated
  (Gym 5 · Strength 9: today's two entries once more) and green from a
  fresh seed, with a six-point bisect of its own steps (the custom span,
  the preset, ►, Today, ►, ◄) reading 13 entries at every point — no
  defect in the step, home or landing logic; the matrix as the status
  line says; `qa errors` clean throughout. Docs: the feature doc's
  addendum, `references/subsystems.md` § Overview, the `calendar-events`
  rule lines, the `calendar-ui` file table, nav bullet, ids and device
  pass, the master's row, this status line.

- **2026-10-15 — §2.6 decided, slices 11–12 opened.** The owner asked for
  several years in Year mode ("months separated by years in a continuous
  scroll"); one mock ("Overview years mock",
  https://claude.ai/artifact/HW9tTTqBo1xanRoRr29PUb); the owner answered
  "choose for me and make it really performant so we can have it as a
  flagship feature", so the lead took every recommended option as
  D26–D30 and wrote §3.14. Slice 11 to one `implementer` (Opus 5.5),
  one `reviewer` after it; slice 12 the scrubber, the benchmark, the
  device pass and the docs.
- **2026-10-15 — slice 11 IMPLEMENTED and reviewed** (one `implementer`,
  Opus 5.5, high; one `reviewer`): `AgendaYearScroll` and its controller,
  `AgendaYearTileBuilder` lifted out of `AgendaYearGrid`,
  `YearMonthTile.columnsFor` (the delegate's own rule, pinned against
  `getLayout` at 328 and 580), the four `OverviewListMetrics` numbers,
  `yearBoundsOf`'s ceiling, the page's queue, two ids, fifteen scroll
  tests, the Year block re-targeted, flows 05 and 23 edited. Gate
  `+7676 ~9 -1` (the Windows-only host test). The review's eleven
  findings: an open-ended series starting past the ceiling cut out of the
  span (CONFIRMED), every keyboard frame rebuilding the sections through
  the height-reading `LayoutBuilder` (PLAUSIBLE on SDK source), runs not
  tied to frames, an animated landing resolving the years it passes, a
  dropped run in `_setOptions`, a resolve inside `didChangeDependencies`'s
  build, fold work in the builder under a query, five test gaps,
  `cacheExtent: 0` as a literal on a weak trade-off. The implementer's
  `dart format lib test` reformatted ~145 unrelated files, restored with
  `git checkout --`.
- **2026-10-15 — slices 12 and 12b IMPLEMENTED, uncommitted** (one
  `implementer` each, one `reviewer` between): the eleven fixes, the
  Year-mode scrubber (`overviewYearScrubberLabel` ×3), the budgets and the
  timed benchmark, flow 24; gate `+7689 ~10 -1`. The second review: the
  D28 ceiling leaking into List, Month and the range picker through
  `_years` (CONFIRMED → `yearSpansOf`, `_scrollYears`), the budgets
  skipped by the `benchmark` tag (CONFIRMED → untagged counts, tagged
  timings), the scrubber's step bypassing the page, a mid-landing pixel
  correction not retargeting the animation, a covered `duringBuild` scan,
  stale query tiles for far years, two scans in the first Year frame,
  every run rebuilding every section (→ `AgendaYearTileSource`, a section
  rebuilds alone), missing `///`. Gate after 12b `+7700 ~10 -1`. The
  device pass is the next entry.
- **2026-10-15 — device pass** (`qa-runner`, Sonnet 5.5, Pixel_9_Pro,
  `ANTA_QA_VIA=agent`): the first installed build was stale (flow 05 red
  on `wait id:overview-years` against the old pager), so a plain `qa run`
  preceded the results; flows 00–18 green in the batch, 19 red as before
  (its dialog poisoning 20–24 in the one-shot run), 20–24 green one by one
  from a fresh seed (22 red once on a scroll position, green on the
  re-run); Year mode by hand: the resting frame (this year's header at the
  top, twelve tiles, next year's header at the bottom edge; `overview-years`,
  `overview-year-2026` / `-2027` as heading nodes and `overview-scrubber`
  "Scroll by year" in the dump), native swipes showing two years on one
  screen, a swipe in the lane, ◄ ► and Today landing with the header at the
  top and the chevrons disabled at the span's ends, the Period menu's This
  year; the matrix dark · de · 2.0 (the headers "2026, 119 Einträge · 63
  verpasst", the lane "Nach Jahr scrollen"; the tiles' month labels and the
  totals line ellipsized as before, §8); the keyboard fold not raisable by
  the harness (the widget suite pins it); `qa errors` clean. Docs in the
  same slice: this record, the feature doc's addendum, `subsystems.md`
  § Overview, the `calendar-events` rule lines, the `calendar-ui` file
  table, ids and device pass.
- **2026-10-17 — D31, the presence button (the owner's own ask).** The
  owner found Mark presence "always disabled, never on" (the sheet opened
  from Year mode, where the switch was off by design) and asked for the
  day panel's toggle on the event's row in Month view. §2.7 D31 · A: the
  button in the row's trailing slot wherever a row is a day and its event
  tracks presence, the switch and the tap-to-mark mode retired (§3.15).
  One implementer (Opus 5.5), one reviewer (Opus 5.5), one device pass
  (Sonnet 5.5). Gate on the final tree: `dart analyze lib test tool
  test_driver` clean, `flutter test` `+8036 ~10` all passed (8034 after
  the slice; two tests after the review — the button's own semantics
  node, and a press under Missed only taking the row out),
  `untranslated.txt` `{}`. The review found no code issue; its docs
  findings (`row-primitives.md`'s `onLongPress` / `hint` line, this
  record's §3.12 mark) are placed; its two low notes stand as they are —
  a failed presence write leaves its pending mark until a later bump
  consumes it (the tap-to-mark path had the same), and the
  `overview-row-presence-` prefix cannot clash with a UUID event id. The
  device pass on the Mac's `Medium_Phone_API_36.1` (1080 × 2400 @ 420):
  05 green; 23 red at step 82 on the Pixel_9_Pro swipe coordinates and
  green on all 128 steps with that one swipe adjusted (§8); 24 red at step
  32 on the "Saved as" snackbar race and green after a wait (§8); by hand
  in Month mode — the button's node beside the row's in the dump ("Mark as
  missed"), the press fading the row and flipping the tooltip, the day's
  and the month's counts following, the second press restoring, the row
  tap opening the detail sheet, the options sheet ending with Missed only;
  the matrix en · light · 1.0 and de · dark · 2.0 (the button in place on
  the faded row too, "Als anwesend markieren"); 360 wide not reachable on
  that AVD (a density override, which the wrapper lacks); `qa errors` only
  the known month-pager `computeMaxScrollOffset` precision assertion. Not
  verified: TalkBack's reading order on a device. Docs: this record, the
  feature doc's addendum, `subsystems.md` § Overview, the `calendar-events`
  and `calendar-ui` rule lines, `row-primitives.md`, the context log.
- **2026-10-17 (later) — D32, the picked day under the hidden display
  (the owner's second screenshot).** The owner's phone runs the missed
  display on `hidden`: their Month-mode screenshot showed a daily Gym
  event with a bar on exactly its kept days, tomorrow not pickable and no
  button on the picked day's row ("I can't mark it present for tomorrow;
  the dedicated presence button doesn't appear"). §2.8 D32 · A on their
  yes: the picked day in Month mode is the day panel's twin (§3.16) — a
  one-day scan converted with `faded` behind the picked day's rows and
  counts, an occurrence mask behind the grid's pickable days, the button
  offered on the picked day's rows under every display; the whole-month
  rows, the bars, the counts, Year and List untouched. One implementer
  (Opus 5.5), one reviewer (Opus 5.5), one fix pass by the same
  implementer, one device pass (Sonnet 5.5). Gate on the final tree:
  `dart analyze lib test tool test_driver` clean, `flutter test` `+8044
  ~10 -1` (8041 after the slice, three tests after the review; the one
  failure the known Windows-only `host_devices_test` case), no ARB
  touched. The review: seven findings, none above low; both declared
  deviations accepted (`_toggleSelectedDay` always lets the picked day go,
  so the ✕ works once a query has emptied it; the flow targets today's
  Lifting, since the seed's one assume-absent event runs on workdays only
  and a flow has no conditionals). Fixed: flow 25 scrolls to the "Hidden"
  / "Faded" segments themselves (`scroll-to` stops at the row's title,
  50–70 dp above the segment under its two-line description) and to the
  Lifting row's button before each check; `_hasOccurrence` answers true
  for the picked day while its rows are non-empty, so under a live query
  the picked cell agrees with the rows it lists (`faded` + `_matches`)
  instead of drawing disabled; the picked day's kept and missed counts are
  folded in `_recompute` (`_takePicked`), never in build, and reset in
  every other branch; three tests added (the picked cell under a matching
  query, the ✕ after a query has emptied the picked day, Missed only on a
  hidden picked day). Accepted as they are: under a live query every other
  hidden-only day stays inert (§3.16's rule); a future month under
  `hidden` draws its pickable days over the whole-month rows or the "No
  entries" caption (a caption inviting a pick would be three strings —
  the owner's call); the one-day scan also runs on the
  `didChangeDependencies` → `_rebuild(duringBuild: true)` path, the month
  branch's pre-existing shape. The device pass on the Pixel_9_Pro
  (Windows; `ANDROID_HOME` set by hand from `android/local.properties`,
  the cold boot's WHPX false refusal as known): flow 25 green 72/72 on the
  agent transport (`ANTA_QA_VIA=agent`) — on adb it stops at `wait
  "Search settings"` after the appearance page, because the adb matcher
  does not read a field's hint, a transport effect flow 22 shares; 23 green
  from a fresh seed (the swipe step included), 05 green; by hand under
  Hidden — days with only missed or assumed-absent occurrences
  full-strength and tappable, 22 Oct picked reading "1 entry · 1 missed"
  with the faded Standup row's `overview-row-presence-qa-cal-standup-
  2026-10-22` "Mark as present", the press making it "2 entries", the nav
  30 → 31, the day's bar drawn, the tooltip "Mark as missed", the second
  press restoring it, Whole month with no presence node, November's
  workdays pickable with 10 Nov behaving the same; the de · dark · 2.0
  matrix ("Als anwesend markieren", the header "1 Eintrag · 1 verpasst",
  everything in place, the row subtitle ellipsized); a plain `scroll-to`
  in Month mode moves the month body; `qa errors` clean three times, the
  month-pager assertion absent this run. Seen, not this slice's: at 2.0 the
  scrolled month body slides the totals strip under the chip row without a
  fade (an ordinary scroll-under). Not verified: TalkBack's reading order.
  Docs: this record (§2.8, §3.16, the status line), the feature doc's
  addendum, `subsystems.md` § Overview, the `calendar-events` and
  `calendar-ui` rule lines, the context log.
- **2026-10-17 (later still) — D33, the conformity pass, with the snackbar
  surface (decision 9 of the master record).** The owner: "sometimes white
  snackbars and many things not in conformity with the design — correct
  them." The snackbars: both bars painted `inverseSurface` (near-white in
  the dark theme); settled app-wide as decision 9 of
  `docs/ui-language-adoption-roadmap.md` §3 — one `snackBarTheme` on
  `menuSurface`, read by `CustomSnackbar` and `OverlaySnackbar` — built by
  one implementer (Opus 5.5). The overview: one read-only audit (reviewer,
  Opus 5.5, no tests — a device pass held the build) against the
  `ui-language` rulebook plus a two-theme screenshot set of every overview
  surface (qa-runner, Sonnet 5.5, 45 shots `ovw_*`) gave twenty
  deviations; §2.9 D33 · A fixed the sixteen rule breaches and listed the
  rest for the owner; one implementer (Opus 5.5), one review over both
  slices (Opus 5.5 — it hit its turn limit and delivered on request: eleven
  findings, none above low), one fix pass by the same implementer, two
  device-pass rounds (Sonnet 5.5). Gate on the final tree: `dart analyze
  lib test tool test_driver` clean, `flutter test` `+8074 ~10 -1` (8052
  after the snackbar slice, 8074 after D33 and its fix pass; the one
  failure the known Windows-only `host_devices_test` case), no ARB touched.
  The review's findings, fixed: the two bars drew different text
  (`SnackBar` replaces the inherited style, the overlay merged into
  `bodyMedium`) — the overlay now wraps its message in `DefaultTextStyle`;
  `AppBar(iconTheme:)` also recolours the actions to `onSurface` (as the
  browser bars do) — now explicit through `actionsIconTheme` and said in
  the comments; the dialog no-growth test measured the route-filling
  `Align`, not the card — it measures the `Material`; the warning line in
  `FormCaption`'s 18 px grew the dialog by ~2 dp beside the 16 px counter —
  it takes the counter's own metrics in the error colour; `FormCaption` and
  four rows read `FormMetrics.captionLineHeight` instead of their literal
  18; the `yearTile*` names stay in `OverviewListMetrics` with the why; the
  overlay ✕'s tooltip is `l10n.close`; the saved filters sheet's ⋮ is
  `more_vert` too (header D14); flow 24 waits for the "Saved as …" message
  to go before it taps a view by label. Record wording corrected: the
  calendar page's bar keeps `surface` (its own ground); the name dialog's
  outlined field is the dialog layer's own look, the master record's
  inventory item, listed under "left"; the suites named where the pins
  are. The review's declared-deviation verdicts: the menu centred on its
  floor width, `captionLineHeight`, `allowEmpty` (default true keeps every
  one of the twenty `textInput` callers) and `savedListNameWarning` +
  `_askName` — all accepted. Line endings: the index is LF throughout with
  `autocrlf=true`, so the Write tool's LF working copies change nothing
  committed. The device pass on the Pixel_9_Pro (3×, 48 dp = 144 px):
  round one — 05, 17, 23, 25 green, 24 red at step 32 (`tap "Ninety
  days"` ambiguous: the view row and the "Saved as" message's text, the
  pre-existing race the D31 pass had met on another AVD); the `ovw2_*` set
  in both themes with the dumps: the bar's buttons 144 px (48 dp) on both
  pages, `overview-search-open` 144 × 144, the Period menu `[238,558]
  [898,1254]` centred on the title's centre x 568, Missed only
  `disabled` in Year mode, the Categories value two lines at 162 px, the
  views ✕ "Close", the name dialog's Save `disabled` while empty and the
  duplicate warning shown with Save enabled, the "Saved as" bar a
  dark-grey card with light text in dark and light-grey with dark text in
  light, the page bar ("Occurrence skipped · UNDO") the same; round two
  after the fix pass — 05, 23, 24 green, the dialog's card `[220,1068]
  [1060,1800]` before and after the duplicate warning (no growth), the
  overlay ✕ "Close", the three bar actions one colour with the back arrow;
  `qa errors` clean after every round. Not verified: TalkBack's reading of
  the nav title's new hint; 2.0 text scale in German on a device for the
  13 px count line. Docs: this record (§2.9, §3.17, the status line), the
  master record (decision 9, §4.8), `ui-language` § Sheet chrome and §
  Dialogs, `sheet-chrome.md`, `row-primitives.md`, `calendar-ui` (the nav,
  the tiles), `calendar-events` (the rule line, `subsystems.md` § Overview,
  the context log).
