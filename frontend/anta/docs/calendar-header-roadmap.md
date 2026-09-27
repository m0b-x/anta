# Calendar Header — Roadmap & Slice Prompts (2026-09-26)

**Status: SHIPPED 2026-09-26** (uncommitted on top of `4ffac29`; the owner
reviews and commits). Slices 1–4 are done: the menus, the navigator switch
and the export controller; the two pages and the filter sheet; the deleted
widget and key; the flows, the device pass on the Android emulator, the
independent reviews and the docs (`calendar-events-feature.md`'s header
addendum, `COPILOT_CONTEXT.md`, the `calendar-events`, `calendar-ui` and
`qa-emulator` skills, `docs/qa-harness.md`). Line numbers in §5 are as of
`4ffac29`.

**Deviations from this document, and why:**
- `_CalendarMenuAction` went in slice 2, not 3: once the ⋮ was rebuilt it
  was an unused private enum, which the analyzer flags.
- The title also carries `header` and a platform-aware `namesRoute`, and
  both pages set `AppBar.excludeHeaderSemantics` (D15 below). Found on the
  device pass: `AppBar` wraps its title in a header annotation that names the
  route, and with the title a button node of its own that annotation had no
  label — the dump showed an empty `Header` over the button — so Android,
  which announces a route by the first named node's label, would have opened
  both pages to silence.
- The overview suite's harness now registers `AppNavigator.routeObserver`
  and puts both blocs above the app: without the observer `didPopNext` never
  fired in tests, and a route pushed over the page could not see the blocs.
- The calendar page suite builds its bloc in `setUp`, outside the test's
  fake-async zone, so its emissions reach the builders only through
  `tester.runAsync` (`deliver` in `calendar_header_test.dart`).
- D16–D18 came out of the design review (below) and amend §3.
- Only the 427 dp emulator was available, so the 360 × 780 and 412 × 915
  sizes are covered by the widget suites (German at 360 dp, the page pushed
  so its bar carries the back button) rather than by device shots. The
  widget tests' font is wider than the device's, so "reads in full at 360"
  rests on the device measurement: "Calendar ▾" is 123 dp against a 148 dp
  title slot.

**Independent reviews (two fresh Opus subagents, read-only, briefed with
this record and the diff).**

*Code review — no high or medium defects.* One low: the ⋮'s focus test
passed with or without the focus drop, because an open popup route takes
focus anyway — both focus tests now check after the menu closes, and a
mutation run (the drop removed) failed both. Its gaps, closed: the page's
export wiring now has a test (a recording bloc: the dispatch and one
answer); the 360 dp test pushes the page so its bar has a back button.
Its nits, fixed: two inaccurate phrases in `CalendarViewMenu`'s doc, the
padding made directional, two helpers made private, two page comments, and
doc drift — the format is not "reset on every visit" (the app-wide bloc
keeps it until the app restarts), the filter sheet no longer "shows" it, the
`.github` skill's gear and format toggle, the ledger's filter-sheet section
order, links to the deleted widget, "the only place" in the skill (the
grid's swipe still changes it), and the export paragraph now says a failure
also reaches the folder page's listener. Left, with reason: the overview's
event reload after its own settings trip has no test (the settings page
cannot be pushed in a widget test without its services; it mirrors the
calendar's path).

*Design review — no visible deviation from this record, nothing to revert.*
Three defects, all fixed: TalkBack never spoke "Switch view" (D16); menu
labels were cut off at 200 % (D17); the device evidence predated D15 — the
nine flows, the dump and the text-scale matrix were re-run on the final
build (the dump now shows one `header` button node with its hint and no
empty header). Recommendations taken: the glyphs (D18). Not taken: titling
the settings page "Calendar settings" (the page and its drawer row predate
this change; §8), and a "Grid" label over the formats (new menu anatomy;
only if the two checks confuse in use).

Design source: the canvas **"Calendar Header Mocks"** —
https://claude.ai/artifact/MmPvg8YuaQ6PWE54aJEhKz. Every board is 390 × 844.

| Board | Shows |
| --- | --- |
| Today | the shipped bar: back · "Calend…" · saved filters · filter · overview · settings · ⋮ |
| Proposed | back · `Calendar ▾` · saved filters · filter · ⋮ |
| Proposed · title menu open | Calendar ✓ · Overview · divider · Month ✓ · 2 weeks · Week |
| Proposed · ⋮ open | Alerts · Export events (.ics) · divider · Calendar settings |
| Overview · title menu open | `Overview ▾` · ⋮, the menu with Calendar · Overview ✓ only |
| second row | the same in dark |

## 0. How to run this

Load `anta-context`, `calendar-events`, `calendar-ui`, `ui-revamp`, `verify`
and `l10n` (plus `qa-emulator` for slice 4). Work the slices in §6 in order;
never start a slice with anything red. The gate in §6.0 runs after every
slice. Do not commit.

## 1. Why

The calendar's app bar carried five buttons — saved filters, filter,
overview, settings, overflow — and at 390 dp the title read "Calend…"
(`ScrollableAppBarActions` kept 152 dp for the leading button and the title;
four icons plus the ⋮ left 74 dp for a 22 px "Calendar"). The overview
(2026-09-26) had just added the fifth. Meanwhile the grid's Month / 2 weeks /
Week choice — a way of *looking*, never persisted — sat as the first
section of the *filter* sheet, behind Apply; and the Alerts hub, whose every
entry belongs to a calendar event, could only be reached from the drawer at
the root.

The owner asked (2026-09-26) to fold the "yearly" calendar (the overview)
into a dropdown on the title, like the month title's, and to put settings
in the menu. The proposal added three recommendations; the owner answered
"implement all of it".

## 2. Decisions

| # | Decision | Reason | Who |
| --- | --- | --- | --- |
| D1 | The app-bar title is a view menu: `Calendar ▾` on the calendar, `Overview ▾` on the overview. Its first group is Calendar · Overview, the current page checked. The ▦ button goes. | The two pages are one feature; a dropdown like the month title's. | owner, 2026-09-26 |
| D2 | Calendar settings leaves the bar for the ⋮ menu, as its last row, below a divider, labelled "Calendar settings". | Owner's request. Every other ⋮ in the app ends with Settings, but those open the app's settings, so this row says which. | owner, 2026-09-26 |
| D3 | Month / 2 weeks / Week moves from the filter sheet into the view menu, below a divider, on the calendar page only. A pick applies at once. The filter sheet loses its "View range" section. | It changes how the grid is looked at, not what it shows; it is session state (`CalendarPageLoaded.format`, never persisted), so a draft-and-Apply sheet was the wrong home. | recommended, approved 2026-09-26 |
| D4 | Alerts joins the ⋮ menu, first row. | The hub was reachable from the drawer only. | recommended, approved 2026-09-26 |
| D5 | The overview carries the same ⋮ menu: Alerts · Export events (.ics) · Calendar settings. | One header shape for one feature. | recommended, approved 2026-09-26 |
| D6 | Switching never stacks: when the page asked for sits **directly beneath** the current one, the switch returns to it; otherwise it pushes, as the ▦ button did. The ⋮ menu's Alerts row follows the same rule. | Calendar → Overview → Calendar is one back step, never a pile. Only the page directly beneath: collapsing onto a deeper one would throw away pages the user walked through. | proposed, approved 2026-09-26 |
| D7 | Both menus are `PopupMenuButton`s (a popup route, like the ⋮ already was), never `MenuAnchor`. | `MenuAnchor` items expose no semantics nodes on iOS (`calendar-ui`). | delegated |
| D8 | Both menus drop focus before they open (`onOpened`). | The `calendar-ui` rule: a menu's return would otherwise re-raise the agenda search's keyboard. | delegated |
| D9 | Row anatomy is the app's overflow menus' (44 dp rows, 20 px glyph in `onSurfaceVariant`, the theme's 15/400 label, 13 dp dividers), 236 dp minimum, but **intrinsic width up to 280** (`AppTheme.menuMaxWidth`). The current choice wears a trailing 20 px check in `primary` and is a `menuItemRadio` node. | "Ereignisse exportieren (.ics)" does not fit 236. A radio role tells a screen reader which view is on. | delegated |
| D10 | `ScrollableAppBarActions` is deleted. | Two buttons never need to scroll; the calendar was its only user. | delegated |
| D11 | Each page answers only for the `.ics` export it started. | Both pages can be mounted at once and `ImportExportBloc` is app-wide: one export would otherwise show its snackbar twice. | delegated |
| D12 | The overview re-reads its appearance on every return (`didPopNext`) and reloads events after its own settings trip. | It can now reach the settings page; the calendar page already does both. | delegated |
| D13 | `calendar-overview-open` moves to the view menu's Overview row (the contract survives). New ids: `calendar-view-menu`, `calendar-view-calendar`, `calendar-format-month`, `calendar-format-two-weeks`, `calendar-format-week`, `calendar-more`, `calendar-alerts-open`, `calendar-export`, `calendar-settings-open`. | QA flows target controls by id; "Calendar" is not a unique label on the calendar page. | delegated |
| D14 | The ⋮ glyph is `Icons.more_vert` on every platform. | Matches the folder and note menus; the old calendar menu used the adaptive glyph (⋯ on iOS). | delegated |
| D15 | The view menu's node carries `header` and `namesRoute` (as `AppBar` would, platform by platform); the pages set `excludeHeaderSemantics`. | Added on the device pass: the app bar's own header annotation lost its label once the title became a button node, and the route announcement with it. | delegated, 2026-09-26 |
| D16 | On Android the title's node also carries the tooltip's words as its `hint`; not on iOS. | Design review: Android 9+ hands a tooltip beside a label to `setTooltipText`, which TalkBack never reads on focus (`AccessibilityBridge.java`); iOS already folds the tooltip into the label, so a hint there would say it twice. | review, 2026-09-26 |
| D17 | Menu labels wrap as far as they need to (no line cap); a row grows past 44 dp only when its label wraps. Supersedes D9's one-line label. | Design review: at 200 % text a German or Romanian label was cut off at the 280 dp cap ("Ereignisse exp…", "Prezentare g…"), a WCAG 1.4.4 failure; a menu item's height is a minimum. | review, 2026-09-26 |
| D18 | Glyphs: Export `share_rounded` (the app's share/export glyph; `ios_share` was only ever this menu's), Alerts `notifications_active_rounded` (the drawer's, for the same page), the formats one outlined family (`calendar_view_month_outlined`, `view_agenda_outlined`, `view_day_outlined`). Supersedes those names in §3.2. | Design review: the solid 2-weeks and Week bars outweighed the checked Month row, and the other two named the same things differently from the rest of the app. | review, 2026-09-26 |

## 3. The spec

### 3.1 Geometry and tokens

- `AppBar.titleSpacing` = `CalendarViewMenu.titleSpacing` (8): the title's ink
  starts 8 dp left of where the text sits, and the text stays at x = 72.
- The title button: min height 48 (`kMinInteractiveDimension`), padding
  `CalendarViewMenu.titlePadding` (8 left, 4 right), stadium ink
  (`CalendarViewMenu.titleRadius` 24). Label: the app bar's title style
  (22/28, `onSurface`), one line, ellipsis. Glyph:
  `Icons.arrow_drop_down_rounded`, `CalendarViewMenu.glyphSize` 24,
  `onSurfaceVariant`.
- Menus: `AppTheme.menuWidth` (236) minimum, `AppTheme.menuMaxWidth` (280)
  maximum, rows `AppTheme.menuItemHeight` (44), dividers
  `AppTheme.menuDividerHeight` (13), glyphs `AppTheme.menuIconSize` (20). The
  view menu opens **under** the title (`PopupMenuPosition.under`); the ⋮ menu
  opens over its button like every other ⋮.

### 3.2 The calendar page's bar (glyphs amended by D18, label wrapping by D17)

`← | Calendar ▾ | [saved filters] [filter] | ⋮`

- Saved filters and filter are unchanged (order, badge, `buildWhen`s, the
  sheet guard).
- View menu (calendar): Calendar ✓ (`calendar_month_rounded`) · Overview
  (`grid_view_rounded`) · divider · Month (`calendar_view_month_rounded`) ·
  2 weeks (`view_agenda_rounded`) · Week (`view_day_rounded`), the grid's
  current format checked. Before the page has loaded the format rows are
  disabled, never hidden.
- ⋮: Alerts (`notifications_active_outlined`) · Export events (.ics)
  (`ios_share_rounded`, disabled while there are no events) · divider ·
  Calendar settings (`settings_outlined`).

### 3.3 The overview's bar

`← | Overview ▾ | ⋮` — view menu with the page group only; the same ⋮
(export disabled until the calendar has loaded, or while it has no events).

### 3.4 The filter sheet

The "View range" label and its segmented control go; categories become the
first section. `CalendarFilterSheet.show` returns `CalendarGridFilters?`;
`CalendarFilterResult` goes.

### 3.5 Copy and l10n

- New: `calendarViewMenuTooltip` — "Switch view" / "Ansicht wechseln" /
  "Schimbă vizualizarea" (the title button's tooltip and hint).
- Retired: `calendarViewRange`.
- Reused: `calendar`, `calendarOverview`, `calendarFormatMonth`,
  `calendarFormatTwoWeeks`, `calendarFormatWeek`, `alertsTitle`,
  `exportEventsIcs`, `calendarSettingsRow`. Their English descriptions are
  updated to name the menus.

## 4. Behaviour

### 4.1 Must not change

- `CalendarPageLoaded.format` stays session state: never persisted, kept by
  the app-wide bloc until the app restarts, month on a cold start; the
  keyboard still forces a week while it is up; `table_calendar`'s own
  vertical swipe still changes the format.
- `ChangeCalendarFormat` is the one writer of the format; the bloc's no-op
  guard for an equal format stays.
- The filter sheet's draft-and-Apply contract, Reset, save-as-preset, the
  category picker, the presence/layers/panel sections, and
  `_applyFilters` as the one funnel.
- Saved filters and filter buttons: position, badge, icons, tooltips, the
  press-time state reads, `SheetGuard`.
- `_openSettings` on the calendar still reloads events unconditionally after
  the settings page pops; `didPopNext` still re-reads the page settings.
- The export still goes `ImportExportBloc` → `ExportCalendarRequested(events:
  allEvents, share: true)`; its snackbars are the same strings.
- The drawer's Calendar / Overview / Calendar settings / Alerts rows, and
  `AppNavigator.toCalendar`, `toCalendarOverview`, `toCalendarSettings`,
  `toAlerts` (plain pushes) — the new switch helpers wrap them.
- `toCalendarOccurrence` (an overview row tap) still collapses onto a live
  calendar anywhere in the stack.
- The overview's persisted mode and allowlist; its year, search and a
  drilled-into month survive a trip to another page and back.
- Launch restore: every page is still pushed or popped under its own stamp.

### 4.2 Deliberately changes

- The ▦ and ⚙ buttons leave the calendar's bar; the title opens a menu.
- Month / 2 weeks / Week applies from the view menu, at once; the filter
  sheet no longer carries it.
- The overview gets a ⋮ menu and a view menu; it re-reads its appearance on
  every return.
- The calendar's ⋮ uses the app's menu row anatomy (it was a `ListTile`) and
  `Icons.more_vert` on iOS too.
- A page answers only for its own export (the calendar used to answer any
  calendar export).

## 5. Facts from the tree (re-grep before editing)

- `lib/pages/calendar_page.dart`: `_CalendarMenuAction` :84; the app bar
  :1036–1157 (`ScrollableAppBarActions` :1049, overview button :1110, gear
  :1118, ⋮ :1125); `_exportCalendar` :1454; `_onImportExportState` :1460;
  `_filterSheetBody` :1943 (format hand-back :1954); `_openSettings` :1983.
- `lib/pages/calendar_overview_page.dart`: `didPopNext` :174;
  `_loadSettings` :182; the app bar :598.
- `lib/widgets/calendar_filter_sheet.dart`: `CalendarFilterResult` :22,
  `initialFormat` :42, `show` :55, `_format` :75, `_reset`'s doc :173,
  `_formatLabel` :178, `_apply` :266, "View range" :340.
- `lib/services/app_navigator.dart`: `_livePageRoutes` :275, `_collapseOnto`
  :287, `toCalendarOverview` :511, `toCalendarSettings` :519, `toAlerts` :527.
- `lib/constants/semantics_ids.dart`: `calendarOverviewOpen` :57.
- `lib/widgets/scrollable_app_bar_actions.dart` and
  `test/widgets/scrollable_app_bar_actions_test.dart` — deleted in slice 3.
- `tool/qa/flows/calendar/05_overview.txt` :3 taps `id:calendar-overview-open`.
- Tests on the retired API: `test/widgets/category_filter_sheets_test.dart`
  (`CalendarFilterResult` :119, :169, :201).

## 6. Slices

### 6.0 The gate, after every slice

`dart analyze lib test` clean; the whole `flutter test` green, one run at a
time; `flutter gen-l10n` with an empty `untranslated.txt` when an ARB
changed; §4.1 re-read against the diff.

### Slice 1 — Primitives

`lib/widgets/calendar_header_menus.dart`: `CalendarViewMenu`,
`CalendarOverflowMenu`, their rows (a radio row for the view menu).
`AppTheme.menuMaxWidth`. The `SemanticsIds` of D13. `calendarViewMenuTooltip`
in the three ARBs. `AppNavigator.returnOrPush` (D6) with
`switchToCalendar`, `switchToCalendarOverview`, `toAlertsFromCalendar`.
`lib/controllers/calendar_export_controller.dart` (D11). Suites:
`test/widgets/calendar_header_menus_test.dart`,
`test/widgets/app_navigator_calendar_switch_test.dart`,
`test/controllers/calendar_export_controller_test.dart`.

### Slice 2 — The screens

The calendar page's bar (§3.2) and its export through the controller; the
filter sheet without the format (§3.4); the overview's bar (§3.3), its
settings trip and its `didPopNext` appearance read (D12). Suites: the
calendar page's header (`test/widgets/calendar_header_test.dart`), the
overview page suite extended, `category_filter_sheets_test.dart` on the new
return type.

### Slice 3 — Delete the old UI

`ScrollableAppBarActions` and its suite, `_CalendarMenuAction`,
`calendarViewRange`, dead imports.

### Slice 4 — Device pass, independent review, docs

`05_overview.txt` switches through the menus; a new `08_header.txt` walks
the view menu, the format rows and the ⋮ rows. The matrix (dark, de, 2.0),
360 and 412 wide. A fresh reviewer with this record and the diff. Docs: the
feature doc's addendum, `COPILOT_CONTEXT.md`, the `calendar-events` skill,
`.github/skills/anta-context`.

## 7. Definition of done

1. The bar holds exactly: back, the view menu, saved filters, filter, ⋮ — on
   a 360 dp phone in German at text scale 1.0 the title reads in full.
2. Calendar → Overview → Calendar through the menus leaves one calendar route
   and no overview route; Overview (from the drawer) → Calendar pushes.
3. Month / 2 weeks / Week from the menu changes the grid at once; the check
   follows a vertical swipe on the grid; the keyboard still forces a week.
4. The filter sheet opens on the categories; Apply, Reset and saving a preset
   behave as before.
5. ⋮ → Alerts, Export, Calendar settings from both pages; the export's
   snackbar shows once; the overview re-reads its accent after settings.
6. Light and dark; en, de, ro; text scale 2.0: the title ellipsizes before
   the glyph, no overflow, menus no wider than 280.
7. Semantics: the title is one button node with its tooltip and id; the
   view rows are radio items with a checked state; every row has its id.
8. `untranslated.txt` is `{}`; the saved calendar flows pass.

## 8. Deferred

- The folder and note menus keep their own `_row` builders; moving them to
  the shared row is a change for when one of them is opened (the
  `calendar-ui` adoption rule).
- The folder page's app-wide import/export listener still shows its own
  failure snackbar and loading dialog for a calendar export (pre-existing),
  so a failed export shows its error twice.
- The calendar settings page is titled "Calendar" while every row that opens
  it (the drawer, now the ⋮) says "Calendar settings" — `calendarSettings`
  vs `calendarSettingsRow`; one reference to change, predates this work.
- The folder and note menus still cut labels off at 200 % text; they take
  D17's wrap when one of them is opened.
- A single German compound wider than the menu at 200 % ("Kalendereinstel-
  lungen") still breaks mid-word; only hyphenation or a smaller label would
  avoid it.
- A "Grid" label over Month / 2 weeks / Week, if the two checks confuse in
  use (design review, recommendation 4).
