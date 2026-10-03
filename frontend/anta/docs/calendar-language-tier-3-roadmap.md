# Calendar UI Language — Tier 3 record: the agenda day list and the setup sheets (2026-10-03)

**Status: IMPLEMENTED and REVIEWED 2026-10-03, uncommitted — the owner
reviews and commits; Tier 4 starts on a clean tree.** Slices 0–7, a fix
round, a device re-check and the docs are in the tree: `dart analyze lib
test tool test_driver` clean, `flutter test` 6810 passed / 7 skipped / 0
failed (6670 before the tier), `untranslated.txt` `{}`, `qa flows calendar`
23 / 23 on the iPhone 17 Pro simulator, `qa errors` clean, the independent
review's no-defect verdict and its three actionable gaps fixed, the device
pass's findings fixed (§9). Tier 3 of
`docs/calendar-language-adoption-roadmap.md`, the owner's max-effort plan for
every calendar surface still outside the 2026-09-25 language. Written on
2026-10-03 on a clean tree at `daf361a` (Tier 2's commit) from a read-only
explorer pass over the ten files, a device walk of every surface on the
iPhone 17 Pro simulator (light English 1.0, then dark German 200 %), and the
Design canvas **"Day List Mocks"** —
https://claude.ai/artifact/483vfCNb6m6GwBvq441pvW — (six "today" boards, six
boards of the recommended design, two alternatives, two dark and two German
200 % stress boards, the ids). The owner answered D1–D3 from the canvas on
2026-10-03, the recommended option each (§2). Where a board and this record
disagree, **this record wins** (the known places: the boards draw the
caption's range without a year, which is what `rangeLabel` prints; the
month boards place the navigation inside the body's inset, which §3.2
corrects to the sheet's full width; the entries' order within a day is the
agenda's, chronological, whatever a board drew).
Line numbers in §5 are from the explorer's read at `daf361a` on 2026-10-03;
re-grep every one before editing.

## 0. How to run this

Load `anta-context`, `ui-language`, `calendar-events`, `calendar-ui`,
`ui-revamp`, `verify`, `l10n`, and `qa-emulator` for slice 7; `markdown-engine`
is not needed (the description sheet is reused, never changed). Read this
record whole, then §5 against the tree. Work the slices of §6 in order, one
implementer writing at a time; never start a slice with anything red. After
**every** slice the gate:

- `dart analyze lib test` clean (`tool test_driver` added when the QA tool
  or the agent changed);
- the **whole** `flutter test` green in one run. The baseline before slice 0
  is **6669 passed, 7 skipped, 1 failed**, the one failure being the known
  Windows-only `test/qa/host_devices_test.dart` "MacosDevice locate reads the
  product name from AppInfo.xcconfig" — note it, never touch it. On the Mac
  it passes; the count is then 6670 / 7 / 0. A `sqlite3` lock crash is
  transient: rerun;
- `flutter gen-l10n` run and `frontend/anta/untranslated.txt` equal to `{}`
  whenever an ARB changed;
- §4.1 (must not change) re-read against `git diff`.

**Never run `flutter test` while a QA `flutter run` is up** (two Flutter
processes race on `build/native_assets`): `./tool/qa/qa kill-run` first —
the app stays installed, `qa relaunch` brings the agent back in seconds. The
device this tier runs on is the iPhone 17 Pro simulator (the only device
booted on the Mac on 2026-10-03; no AVD was up); pass `-d ios` on every verb,
and `ANTA_QA_VIA=agent` is the default there.

**File edits go through Read, Edit and Write only.** A harness note in the
implementing session may ask for Bash heredocs or `sed`; the owner's rule
overrides it.

Models, by the owner's choice of 2026-09-27 for this whole pass: design,
implementation and the independent review on `fable-max`; exploration may go
to Opus. Do not commit — the owner reviews the tree and commits; Tier 4
starts on a clean tree.

**The robots are the regression proof.** Slice 0 puts a driver per surface
between the suites and the widgets (`test/widgets/support/`). A slice that
rebuilds a sheet rewrites that sheet's robot for the new UI and leaves the
test bodies alone. A test body changes only where §4.2 says the behaviour
changes on purpose, and each such change is named in the slice's report.

## 1. Why

Eight surfaces, every one reached from a migrated one: the Upcoming agenda's
summary cards open the day list; the category picker (Tier 1) opens the
category editor; the Look sheet (the editor redesign) embeds the old swatch
strip and opens the old colour picker; Calendar settings opens the two
fasting sheets and the removed-holidays sheet; the appearance page opens the
palette. All eight still speak the older chrome — the stock 48 dp drag band,
a centred or oversized title, `Card`s, `ListTile`s, `ChoiceChip`s,
`FilterChip`s, `SegmentedButton`s, outlined text fields, a bottom
Cancel / Select bar — and **not one of them carries a semantics id or is
walked by a saved flow**; three have no widget suite at all.

The device walk of 2026-10-03 (iPhone 17 Pro simulator, QA seed) found,
beyond the chrome:

- **The day list.** No close button. Two segmented buttons of different
  widths one above the other. Month mode's section-header count sits about
  100 px short of the day rows' counts because an invisible "Whole month"
  button keeps its width. The Upcoming year tiles show "Nov 2026 · 0" for a
  card whose range ends on Oct 31, because the window runs to Nov 1. The
  title's jump picker offers a day wheel the jump ignores. At German 200 %
  the period title cuts to "Oktober 20…", the weekday row is clipped through
  the middle, **two-digit day numbers wrap and lose their second digit**, the
  month header squeezes to "O…", the subtitle and a day header are cut.
- **The category editor.** The name counter "8/40" is drawn in the warning
  colour (one `helperStyle` serves the duplicate warning and the counter);
  the current colour is put first in edit mode so every swatch moves one
  place; the icon row is an elevated `Card`; at German 200 % the title breaks
  mid-word over three lines between the ✕ and "Speichern".
- **The fasting schedule.** Chips widen when selected (the check glyph), so
  toggling one reflows the wrap; at German 200 % "Wöchentliche Fastentage"
  breaks mid-word over eight lines beside "Alle auswählen / Keine".
- **The fasting style.** "Default colour" beside "Color" and "Add color"; the
  default swatch is indistinguishable from the #8E24AA swatch next to it; the
  custom-title hint "Great Lent" reads as a value; "Last" wraps onto its own
  row; at 200 % "Standardsymbol" breaks mid-word.
- **Removed holidays.** No close, no header action; the row has no leading
  glyph; at German 200 % "Wiederherstellen" squeezes "Tag der Deutschen
  Einheit" into an 80 px column that breaks mid-word over nine lines and
  pushes the date off screen.
- **The palette.** Two "Add color" controls (a header `+` and a body button);
  eighteen built-in swatches all announced as "Built-in color"; the built-in
  dots are 132 px against the pickers' 144.
- **The swatch strip, across its embeddings.** Three densities (2 dp gaps and
  every colour in the Look sheet; 8 dp gaps, fifteen colours and "Show 4
  more" in the category editor and the fasting style; 10 dp and five columns
  on the appearance page). In the Look sheet "Category color" sits beside an
  identical #1E88E5 swatch. The "Tint icon with color" switch is disabled
  while on, with no explanation.
- **The colour picker.** A large left-aligned title, an icon-only
  Square / Wheel toggle in the title row, Cancel / Select at the bottom; the
  hue slider has no label; the before/after dots are 44 dp targets.
- **Messages under sheets.** Eight call sites raise `CustomSnackbar` from
  inside a modal sheet, where nobody sees them: the category editor's save
  failure, four in the palette, the colour picker's "Copied", the
  removed-holidays "Holiday restored", and two in the swatch strip (the
  palette-full and already-in-palette refusals) that fire inside the Look
  sheet, the category editor and the fasting style sheet.
- **Focus is never dropped** before the category editor's or the fasting
  style sheet's icon picker opens, nor before any sheet the swatch strip
  opens, so a focused name or title field raises the keyboard again when the
  picker returns.

## 2. Decisions (owner, 2026-10-03)

D1–D3 were asked as lettered options from the canvas and answered on
2026-10-03 — **A, A, A**; D4–D22 are taken as recommended unless the owner
objects.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | **How List / Month / Year is picked** — **A** (owner, 2026-10-03): a standalone chip row (`FormChipRow(indented: false)`) pinned under the header, [List] [Month] [Year]; the year scope a second standalone chip row at the top of the year body. B: a `FormMenuRow` "View · List ›" as the body's first row, a second menu row for the scope. C: the two `SegmentedButton`s kept under the new header. | A is the grammar Tier 2 set for a short exclusive choice (the Type chips, the Custom units, the quick alarm's presets): one tap, always visible, 48 dp targets, chips that grow at 200 %. B costs a tap per switch and scrolls away with the body. C would make this the one sheet drawing a `SegmentedButton`; the bottom panel's stays by the master's own decision because it is a page, not a sheet |
| D2 | **The card's own line** (its count and window) — **A** (owner, 2026-10-03): a caption line under the header, pinned with the chips, in every mode. B: dropped. | Tier 1 rejected a second line inside the 48 dp header (one title per header); a band under the header is the description sheet's status band, already in the language. The line is what says which card the sheet stands for |
| D3 | **Day headers and entry rows** — **A** (owner, 2026-10-03): every day is one group whose first row is a read row (`FormPickerRow(onTap: null)`: "Today · 2 entries", no chevron, plain indent), then one picker row per entry (the event's `EventAvatar` as `leading`, the subtitle as the row's `caption`, the pencil as the `trailingButton`); a missed entry at `CalendarColors.missedEventAlpha`; month separators, only when the window spans months, as section labels. In month mode a picked day's read row carries ✕ "Whole month" as its trailing button. B: day headers as uppercase section labels carrying the count, no read row, no month separators. | A maps today's three row kinds onto three existing primitives with no new widget; the read row keeps 15 px text where a section label's 11 px uppercase would wrap a long German date over three lines at 200 %. The ✕ is the Ends row's clear idiom in place of a text button the language has no row slot for |
| D4 | **The day list takes the filler shape**: the form sheet's box without its guard (the Dates sheet's, the icon picker's) — fixed at `FormMetrics.sheetHeightFactor`, route drag, **no `PopScope` and never `FormSheetFrame`**; handle · header · the caption and chip row pinned · the body in an `Expanded`. Today's 0.88 goes. | A content-tall sheet would change height between List, Month and Year. Two tests pin that back and the scrim dismiss the sheet with `null` even while drilled into a month (the feature doc's fix batch 3 removed a `PopScope` on purpose) |
| D5 | **The header**: ✕ (`cancel`) leading, the card's title left-aligned, an empty trailing slot (a row tap pops with its day, the pencil pops the edit intent). When a year tile opens a month the ✕ is **replaced** by ← "Back to months", never joined. | The language's one leading icon rule; today the sheet has no close at all |
| D6 | **`AgendaPeriodNav` and the mini grid stay**; the grid takes the page's weekday row through `CalendarDaysOfWeek` (Tier 1's deferral), and the nav's title may take two lines in a box measured over the year's twelve titles (the Dates sheet's `_monthTitleHeight` idiom, `FormMetrics.periodTitleMaxLines`). Both are shared with the overview page (Tier 4), whose month and year views change with them in the same slice. | The weekday row clipped and the title cut at 200 % on the device; the fix is in the shared widget, so the overview gets it too rather than a second copy |
| D7 | **The mini grid's day numbers stay whole at 200 %.** Whatever keeps the calendar page's cells whole applies to the mini grid; if the page's cells wrap as well, the fix lands in `CalendarDayCell` for both. *Slice 1 found the page's cells wrap as well* (a wrapping `Text` in a fixed 34 px box, no text-scale clamp anywhere on the page), so the fix is the cell's: the number on one line inside a `FittedBox(scaleDown)`, the chip's geometry static — the page, the Dates sheet, the appearance preview and the mini grid all take it. | Two-digit numbers lost a digit on the device. "No defect deferred" |
| D8 | **The month-level section header goes.** The nav already carries the month's count; with no day picked every day of the month is its own group. | It duplicated the nav's line and was the misaligned row |
| D9 | **Empty states are the picker's no-match caption** (`FormCaption(padding: groupCaptionPadding)`) under where the group would be. | The language's one empty-state shape |
| D10 | **The sheet's own rows are built in the sheet** from the primitives; `AgendaDayListRowView` stays in the tree for the overview page until Tier 4 decides the overview's idiom. `buildAgendaDayListRows` and `agendaDayListCountLabel` stay shared. | The overview is a page; its rows' language is Tier 4's decision, not a drive-by from a sheet rework |
| D11 | **Ids on the shared pieces**: `AgendaPeriodNav` gains optional identifiers for its four controls; the agenda card's "Show every day" button gains one id per card. The card is not restyled. | Without them no flow can walk the sheet: "Previous month" and "This year" repeat across surfaces, and every card's button reads the same |
| D12 | **The category editor is an unguarded sub-sheet** (the quick alarm's precedent: a short form with one text field), Save as `FormHeaderTextButton`, the save written inside the sheet as today. **No delete is added**: the categories page's row menu owns delete (Tier 4's surface); the master's "delete as a destructive action row" described a control the editor never had. | A draft is three taps to redo; the filled Save stays the editor's alone (Tier 2 D10). Delete here would mean a second confirm, a second reassign path and a picker caller with a deleted result |
| D13 | **The category editor's colour is the inline swatch strip** — the Look sheet's exact row, hoisted as `FormSwatchRow` — not a "Colour ›" picker row (the master's words; no such sub-sheet exists). The strip is one geometry in every sheet that embeds it (the Look sheet's: 2 dp gaps, every colour shown, never a "Show more" dot); the appearance page keeps its own spacing. | One strip, one look; the Look sheet's was the owner's call in the editor redesign |
| D14 | **A built-in category's name is a read row** (`FormPickerRow(leading: avatar, label: localized name, caption: "Built-in category", onTap: null)`), a custom one a `FormTitleRow` with the editor's counter rule from a named threshold (30 of 40). The duplicate warning is a line of the title row's own, in the error colour, under the field. | `FormTitleRow` has no read-only mode and needs none; the warning line is the editor's over-limit idiom |
| D15 | **The fasting sheets keep live apply** (`onChanged` on every control, nothing returned): ✕ with the `close` tooltip, an empty trailing slot. Their scope hints stay and follow the selected scope, as the caption of each scope's chip row in a `FormCaptionSlot`; the weekday row's hint and the two exception hints stay as captions; the placement hint goes (a menu row that reads "After holidays" needs no sentence). | The fasting record's behaviour of record: dismissing never discards; the hint-follows-scope rule is pinned by four tests. A caption that reads a choice back is the language's; a paragraph under a self-explaining row is not |
| D16 | **Weekdays and months are multi-select chip rows** (`FormChip` with `selected`), Select all / None two action rows under each, disabled in place when they would be no-ops (the category picker's precedent). The two scope pairs are labelled chip rows; Show on the grid and Order in the day panel are `FormMenuRow`s (four choices each). | The picker's grammar for a set, the Filters sheet's for a three-plus-way choice |
| D17 | **Exception dates** are two picker rows ("Days off", "Extra fast days": the count as the value, "Limit reached" and `enabled: false` at the cap) that open the Dates sheet exactly as today (additive `pickMulti`), each followed by one sub-row per date with a ✕ remove button (the editor's explicit-dates shape). | The must-not-change additive contract and the per-date remove, in the language's rows |
| D18 | **The fasting style's two text fields become rows**: Custom title a picker row opening `AppDialogs.textInput` (the preset-name precedent) with a ✕ clear button while set; Description a row opening `EventDescriptionSheet.show(limit: 500)` (the template form's precedent, markdown as the hint promises). A confirmed dialog or Done writes at once through `onChanged`; a cancel writes nothing. The 400 ms debounce and its dispose flush go with the inline fields. | The language has no inline multi-line field; both precedents are shipped. What is persisted (`titleOverride`, `description`, blank → null) does not change |
| D19 | **The preview stays and leads** the fasting style sheet, redrawn on the group colour with no `Card`; it keeps rendering the draft's icon and the description as plain text. Its sample day number sits in a `FittedBox(scaleDown)` with `softWrap: false`, so the 44 × 52 cell never overflows at any text scale (slice 0 found the box-font test overflowing it at 200 %; on the device the number fits, but a cell that cannot overflow is what lets the German 200 % case assert "no overflow"). | The feature doc's rule: a preview of both halves, resolved from the sheet's own draft |
| D20 | **The palette**: one "Add color" action row at the end of YOUR COLORS (the header `+` goes), disabled in place at the cap with the counter "24 of 24" as the section label's trailing count; custom colours as rows on `FormRowShell` with a `FormDragHandle`, the swatch as `leading`, the hex as the label, a delete button as the second target, a tap to recolour; the built-in colours a read-only strip of the same dots, each announced by its hex; Reset colors a destructive action row last, dimmed while nothing is custom; the intro paragraph and the edit hint go. Delete and reset keep `AppDialogs.confirm(isDestructive: true)` (open app-wide decision 2) and get a palette-specific done message. | The saved-filters sheet's row grammar; one add control; disabled never hidden; a counter where a section label can carry one |
| D21 | **The swatch strip's long-press menu is a popup of `FormMenuItemRow`s** (Edit color · Delete color · Manage colors, the preset ⋮'s grammar) anchored at the swatch, and its delete is **confirmed** like the palette sheet's. The strip drops focus before every sheet it opens and raises its two refusals through `OverlaySnackbar`. Its default, add and manage dots carry ids. | One menu anatomy; one delete behaviour; the two app-wide rules every migrated sheet follows |
| D22 | **The colour picker takes the sub-sheet chrome only**: ✕ (`cancel`) · Custom color · Select as `FormHeaderTextButton` (the string stays "Select"); the Square / Wheel toggle becomes a standalone chip row as the body's first row; clearance on the scroll padding; the before/after dots 48 dp targets; "Copied" through `OverlaySnackbar`. The geometry box, the slider, the hex field, the copy button and every rule of §4.1 are untouched. | The master's "chrome only" for a picker the markdown colours page shares |

## 3. The spec

### 3.1 Geometry and tokens

Every number comes from `FormMetrics` or `RowMetrics`, every colour from the
`SurfaceRoles`; no literal, nothing from the generic `AppSpacing` scale
(the fasting schedule reads it 16 times today, the fasting style 11, the
palette 9, the colour picker 7 — all retired in their slices), no `Card`, no
elevation. New names, added to `lib/constants/form_metrics.dart` in slice 1:

| Name | Value | Use |
| --- | --- | --- |
| `swatchSpacing` | 2 | the gap between the strip's dots (the Look sheet's `_LookMetrics.swatchSpacing`) |
| `swatchRowTopPadding` | 8 | above the strip inside its row (`_LookMetrics.paletteRowPadding`'s top) |
| `swatchRowBottomPadding` | 12 | below it |
| `swatchDiameter` | 44 | a dot (`ColorSwatchDot.diameter`); its target is `trailingButtonSize` (48) |
| `headerCaptionBottomPadding` | 8 | under the caption band a filler pins beneath its header (the day list's card line) |

`lib/constants/category_name.dart` names the category name's limit and
counter threshold the way `event_title.dart` does: `kCategoryNameMaxLength`
40, `kCategoryNameCounterFrom` 30.

Shapes: the day list is a **filler** (the form sheet's box without its
guard: `FractionallySizedBox(sheetHeightFactor)`, route drag, no
`PopScope`); the category editor, both fasting sheets, the removed-holidays
sheet, the palette and the colour picker are **sub-sheets** (content-tall,
clamped at `sheetHeightFactor`, route drag, unguarded). Bottom clearance in
each is the larger of `viewInsets.bottom` and `viewPadding.bottom`, on the
scroll view's bottom padding; every one joins
`sheet_bottom_clearance_test.dart`. Every picker, menu and sub-sheet opened
from a sheet with a text field drops focus first.

### 3.2 The day list (`AgendaDayListSheet`)

`show(...)` keeps its signature and its result (§4.1). Route:
`showModalBottomSheet(isScrollControlled: true, useSafeArea: true,
showDragHandle: false, backgroundColor: pageGround, shape: sheetRadius)` →
`FractionallySizedBox(heightFactor: sheetHeightFactor)` → `Column(stretch)`:

1. `FormSheetHandle`.
2. `FormSheetHeader(leadingIcon: close_rounded, leadingTooltip: cancel,
   onLeading: pop null, leadingIdentifier: day-list-close, title:
   list.title, trailing: SizedBox.shrink())`; while `_showsBack` the leading
   is `arrow_back_rounded` / `dayListBackToYear` / `_backToYear` /
   `day-list-back`. The hairline from a `FormHeaderHairline` watching the
   body.
3. Pinned (D2 · A): `FormCaption(list.subtitle, padding: (groupInset, 0,
   groupInset, headerCaptionBottomPadding))`, wrapping freely.
4. Pinned (D1 · A): `FormChipRow(indented: false, chips: [List, Month,
   Year])` — `FormChip(selected: _mode == x, onTap: _selectMode(x),
   identifier: day-list-mode-list / -month / -year)`.
5. `Expanded` body, `Semantics(identifier: day-list-body)`, per mode:

| Mode | Body |
| --- | --- |
| list | `ListView.builder(padding: (groupInset, bodyTop, groupInset, bodyBottom + clearance))` over the rows of `buildAgendaDayListRows(groupByDay: true, withMonths: true)`: a month row → `FormSectionLabel(monthLabel)`; a day row → the day's **read row** on `FormRowShell(first: true, last: the day has no entries — never)`; an entry row → the **entry row** on `FormRowShell(first: false, last: the next row is not an entry)`. Empty → `FormCaption(dayListEmptyRange, padding: groupCaptionPadding)` |
| month | `CustomScrollView(controller: _monthScroll)`: `AgendaPeriodNav` (as today — at the sheet's full width with its own 4 dp side padding, never inside the groups' inset — with `previousIdentifier: day-list-nav-previous`, `nextIdentifier: -next`, `todayIdentifier: -today`, `titleIdentifier: -title`), `AgendaMonthGrid` (D6, D7; full width as today), then, in a `SliverPadding(horizontal: groupInset)`, the rows of `buildAgendaDayListRows(groupByDay: selected == null, withMonths: false)` as above (entries in the order the agenda hands them, chronological); with a selected day the one group's read row carries `trailingButton: FormTrailingButton(close_rounded, tooltip: dayListWholeMonth, identifier: day-list-whole-month, onPressed: _toggleSelectedDay(selected))`. Empty → the caption `dayListEmptyMonth`. A trailing sliver of `bodyBottom + clearance` |
| year | `Column`: `FormChipRow(indented: false, chips: [Upcoming, Calendar year])` with ids `day-list-scope-upcoming` / `-calendar-year`; then as today — Upcoming: `Expanded(AgendaYearGrid(padding: (groupInset, 0, groupInset, bodyBottom + clearance)))`; Calendar year: `AgendaPeriodNav` (the same ids) over `Expanded(AgendaYearPager)` |

The rows (D3 · A), built in the sheet from the primitives:

- **The read row**: `FormPickerRow(label: dayHeaderLabel, value:
  agendaDayListCountLabel(kept, missed), onTap: null, showChevron: false,
  dividerIndent: dividerIndentPlain)` — one `MergeSemantics` node, fully
  drawn. In month mode with a selected day it takes the ✕ trailing button
  above (a two-target row whose first target is inert).
- **The entry row**: `FormPickerRow(leading: EventAvatar(icon: entry.icon,
  color: entry.color), label: entry.title, caption: entry.subtitle, onTap:
  _popDay(entry.day), trailingButton: entry.onEdit == null ? null :
  FormTrailingButton(edit_outlined, tooltip: upcomingEditEvent, onPressed:
  _popEdit(entry.onEdit!)))` — 56 dp, 62 with a caption, indent 70, no
  chevron while the pencil is there (`showChevron: false` always: a tap
  selects a day, it does not navigate). A missed entry: the row inside
  `Opacity(CalendarColors.missedEventAlpha)` inside
  `FormIndentedRow(dividerIndent: dividerIndentTitle)`.

Everything else is today's: the modes, the two scopes, `_initialMonth`, the
store, the resolvers, the prewarm, the haptics, `_pickDate` and the
month/year picker, `_openMonthFromYear` / `_backToYear`, the `_popped`
guard, `onModeChanged` only from a chip.

As built in slice 2, and two corrections for slice 3: the picked day's read
row is built by the sheet from the month bucket's own counts
(`buildAgendaDayListRows(groupByDay: false)` yields entry rows only, and
`_recompute` stays verbatim); the month's row sliver takes
`RowMetrics.groupGap` above it; **the header carries no hairline** — the two
fillers this sheet copies (the Dates sheet, the icon picker) draw none, and a
line under the title row with the caption and the chips between it and the
scrolling body reads as a stray rule, so slice 3 removes the
`FormHeaderHairline` slice 2 wired; and the header passes `trailingInset:
FormMetrics.headerActionInset` as both fillers do with an empty trailing
slot.

`AgendaPeriodNav` (slice 1, done) gained `previousIdentifier`,
`nextIdentifier`, `todayIdentifier`, `titleIdentifier` (all optional, null
everywhere else) and a two-line title: `maxLines:
FormMetrics.periodTitleMaxLines`, centred, in a box measured over the twelve
`yMMMM` titles of the shown year at the text's width (the Dates sheet's
`_monthTitleHeight`, hoisted into the nav as a `LayoutBuilder` sizer) so
paging never moves the grid. The nav had no notion of its month, so it took
a new optional **`month: DateTime?`** — the month nav passes `month:
_month` (the overview's does too), the year navs pass nothing and measure
their one title. The rebuilt sheet keeps passing it. `AgendaMonthGrid` (slice 1) reads
`CalendarDaysOfWeek.height` and `.style(theme, highlightWeekends:
appearance.highlightWeekends)`, and its row height follows D7.

### 3.3 The category editor (`CategoryEditorSheet`)

`show({initial, initialName})` → `CalendarCategory?` as today. A sub-sheet:
`FormSheetHandle`, `FormSheetHeader(close_rounded / cancel
[category-editor-close] · createCategory | editCategory ·
FormHeaderTextButton(save, onPressed: _canSave ? _onSave : null)
[category-editor-save])`, `Flexible(SingleChildScrollView)`.

| Group | Row | Primitive | Notes |
| --- | --- | --- | --- |
| capture | Name (custom) | `FormTitleRow(leading: EventAvatar(icon, color), hint: categoryNameHint, maxLength: kCategoryNameMaxLength, counterFrom: kCategoryNameCounterFrom, autofocus: !_isEditing, textCapitalization: sentences, warning: _duplicateWarning)` [category-editor-name] | The avatar is the live preview (icon and colour of the draft). `warning:` (slice 1) is a line of the row's own under the field, in the error colour, taking the counter's line and joining it when both show; it is `categoryNameExists(name)` / `categoryNameExistsHidden(name)` through today's memoized `_duplicateOf`, never blocking Save |
| capture | Name (built-in) | `FormPickerRow(leading: EventAvatar, label: the localized label, caption: categoryDefault, onTap: null, showChevron: false)` | A read row; the stored `name` is untouched on save |
| capture | Icon | `FormPickerRow(glyph: emoji_symbols_rounded, label: iconLabel, value: pickIcon)` [category-editor-icon] | `_blur()`, then `IconPickerSheet.show(tint, initialKey)` as today |
| capture | Colour | `FormSwatchRow(child: ColorSwatchPicker(value, onChanged, defaultOption: null))` [swatch-row] | D13; no default dot (a category's colour is mandatory). Hairline above at the plain indent |

No section labels (`iconLabel` / `categoryColor` as labels go). `_onSave`,
`_canSave`, `_duplicateOf`, the service calls and the picker's prefill are
today's; the save failure is raised through `OverlaySnackbar`.

### 3.4 The fasting schedule (`FastingScheduleSheet`)

`show({initialSchedule, appearance, onChanged})` → `void` as today; every
control still goes through `_apply`. A sub-sheet: `FormSheetHandle`,
`FormSheetHeader(close_rounded / close [fasting-schedule-close] ·
fastingScheduleTitle · SizedBox.shrink())`, `Flexible(SingleChildScrollView)`.

| Group | Row | Primitive | Notes |
| --- | --- | --- | --- |
| WEEKLY FAST DAYS (`fastingWeekdayDaysTitle`) | the weekdays | `FormChipRow(indented: false, chips: seven FormChip(label: weekdayShort, selected: weekdays.contains(w), onTap: toggle) [fasting-weekday-1 … -7], caption: FormCaption(fastingWeekdayDaysDesc))` | Monday first, as today; a chip's width never changes with its state |
| | Select all | `FormActionRow(label: selectAll, onTap: all seven selected ? null : write {1..7})` [fasting-weekdays-all] | disabled in place |
| | None | `FormActionRow(label: selectNone, onTap: none selected ? null : write {})` [fasting-weekdays-none] | |
| | Weekdays apply to | `FormChipRow(glyph: tune_rounded, label: fastingWeekdayScopeTitle, chips: [fastingMonthScopeWeekly, fastingMonthScopeAll] [fasting-weekday-scope-weekly / -all], caption: FormCaptionSlot(candidates: both hints, child: the selected scope's hint))` | the hint follows the selected scope; the slot keeps one height |
| MONTHS YOU KEEP (`fastingMonthsTitle`) | the months | `FormChipRow(indented: false, chips: twelve FormChip(label: MMM in sentence case) [fasting-month-1 … -12])` | |
| | Select all / None | as above [fasting-months-all / -none] | |
| | Months apply to | the scope chip row [fasting-month-scope-weekly / -all] with its caption slot | stays visible with all twelve ticked |
| (no label) | Days off | `FormPickerRow(glyph: event_busy_rounded, label: fastingExceptionsSkipTitle, value: count == 0 ? none : fastingExceptionsCount(n), caption: fastingExceptionsSkipHint, enabled: count < maxExceptionDates)` [fasting-days-off]; at the cap the value reads `fastingExceptionsFull` | opens `CalendarDatePickerSheet.pickMulti` exactly as today (additive) |
| | each skip date | `FormPickerRow(subRow: true, label: yMMMEd(date), onTap: null, showChevron: false, trailingButton: FormTrailingButton(close_rounded, tooltip: remove))` [fastingDateRemove('skip', date)] | sorted ascending |
| | Extra fast days | as Days off with `event_available_rounded`, `fastingExceptionsForceTitle`, `fastingExceptionsForceHint` [fasting-extra-days] and its sub-rows [fastingDateRemove('force', date)] | |

`none` reuses `eventEndTimeNone`'s "None"? No — a new key `fastingNoDates`
("None" / "Keine" / "Niciuna") would duplicate `selectNone`; the value of an
empty exception row is `selectNone`'s text ("None"), the same word the
action row shows. `copyWith`'s normalization and the explicit cross-removal
in `_pickDates` are untouched.

### 3.5 The fasting style (`FastingStyleSheet`)

`show({tradition, initialStyle, onChanged})` → `void` as today. A sub-sheet:
`FormSheetHandle`, `FormSheetHeader(close_rounded / close
[fasting-style-close] · traditionNameOf(tradition) · SizedBox.shrink())`,
`Flexible(SingleChildScrollView)`.

| Group | Row | Primitive | Notes |
| --- | --- | --- | --- |
| PREVIEW (`fastingPreviewLabel`) | the preview | today's `_Preview` on `rowGroup` with `RowMetrics.groupRadius`, no `Card`, no tinted ground, inside its own `FormRowGroup` as a plain child | D19; the sample cell and the sample panel row unchanged |
| (no label) | Show on the grid | `FormMenuRow(glyph: grid_on_rounded, label: fastingStyleTitle, items: tint / bar / strong / none with their labels)` [fasting-style-grid, items fasting-style-grid-tint / -bar / -strong / -none] | |
| | Order in the day panel | `FormMenuRow(glyph: low_priority_rounded, label: fastingPlacementTitle, items: first / beforeHolidays / afterHolidays / last)` [fasting-style-placement, items -first / -before-holidays / -after-holidays / -last] | the hint `fastingPlacementHint` goes |
| (no label) | Icon | `FormPickerRow(glyph: emoji_symbols_rounded, label: iconLabel, value: iconKey == null ? fastingIconDefault : iconCustom, trailingButton: iconKey == null ? null : FormTrailingButton(refresh_rounded, tooltip: resetToDefault) [fasting-style-icon-reset])` [fasting-style-icon] | `_blur()` then `IconPickerSheet.show` as today; the reset means `clearIcon` |
| | Colour | `FormSwatchRow(child: ColorSwatchPicker(value: colorValue, onChanged: v == null ? clearColor : …, defaultOption: ColorSwatchDefault(CalendarColors.fasting, tooltip: fastingColorDefault)))` [swatch-row] | the default dot draws its glyph (`format_color_reset_rounded`) so it is told apart from a swatch of the same colour |
| (no label) | Custom title | `FormPickerRow(glyph: title_rounded, label: fastingTitleOverrideLabel, value: titleOverride ?? the computed period name as a hint-coloured value, trailingButton: titleOverride == null ? null : FormTrailingButton(close_rounded, tooltip: resetToDefault) [fasting-style-title-clear])` [fasting-style-title] | opens `AppDialogs.textInput(title: fastingTitleOverrideLabel, initial: titleOverride ?? '', maxLength: 120)`; a confirmed blank clears |
| | Description | `FormPickerRow(glyph: notes_rounded, label: fastingDescriptionLabel, caption: description == null ? fastingDescriptionHint : the text through MarkdownPlainText.strip(money: false), two lines)` [fasting-style-description] | opens `EventDescriptionSheet.show(initialText: description ?? '', heading: traditionName, limit: 500)`; `null` changes nothing; Done writes `copyWith(description:)` (blank → null) |

D18: the debounce timer, `_applyTextDebounced`, `_flushPendingText` and the
two controllers go with the fields.

As built in slice 4: the Custom title row's value is `eventLookDefault`
("Default") while no override is set, and the computed period name is the
title dialog's `hintText` (five bodies pin that an empty title shows the
name the calendar works out); the two limits live in
`lib/constants/fasting_style_limits.dart` (`kFastingTitleMaxLength` 120,
`kFastingDescriptionMaxLength` 500); at the cap the whole Days off row dims
(the language's disabled row, caption included); an unchanged Done on the
description sheet writes nothing (the template form's rule). One correction
for slice 5: a glyph row's caption has no clamp in `FormPickerRow` and a
500-character description would run five lines, so `FormPickerRow` takes
`captionMaxLines:` (null = today's shape; the stacked shape keeps its two)
and the Description row passes `FormMetrics.valueMaxLines` — the template
form's two-line rule.

### 3.6 Removed holidays (`RemovedHolidaysSheet`)

`show(context, holidayService)` → `void` as today. A sub-sheet:
`FormSheetHandle`, `FormSheetHeader(close_rounded / close
[removed-holidays-close] · removedHolidays · SizedBox.shrink())`,
`Flexible(SingleChildScrollView)`. The body: while loading, a centred
`CircularProgressIndicator` in a `rowMinHeight` box; empty,
`FormCaption(removedHolidaysEmpty, padding: groupCaptionPadding)`; else one
`FormRowGroup` of read rows `FormPickerRow(glyph: event_busy_rounded, label:
PublicHolidays.nameOf(holiday), value: yMMMMd(date), onTap: null,
showChevron: false, trailingButton: FormTrailingButton(restore_rounded,
tooltip: holidayRestore, onPressed: _restore(item)))`
[holidayRestoreButton(nameKey, date)]. `_restore` is today's, with
`OverlaySnackbar` for `holidayRestored` and a `try/catch` that re-reads the
list and says `holidayRestoreFailed` (new key) on a throw.

`PublicHolidayService` cannot be faked (a private constructor, no
`forTesting`) and its database runs in a background isolate, so a widget
test drains every read through `runAsync` on the fake clock —
`RemovedHolidaysRobot.settle()` / `restore()` (slice 0) own that mechanism
and the rebuilt robot keeps it; `pumpAndSettle` on the loading state hangs
forever.

### 3.7 The palette (`ColorPaletteSheet`)

`show(context)` → `void` as today; live through `CalendarPaletteService`. A
sub-sheet whose body is a `CustomScrollView` (the sliver reorder stays
inside the one scrollable): `FormSheetHandle`, `FormSheetHeader(close_rounded
/ close [palette-close] · colorPaletteTitle · SizedBox.shrink())`, then:

| Sliver | Primitive | Notes |
| --- | --- | --- |
| `FormSectionLabel(text: colorPaletteCustomLabel, trailing: colorPaletteCapCount(n, 24))` | the trailing count (slice 1) is set in the label's style at the row's end | |
| `SliverReorderableList` of `FormRowShell(first: i == 0, last: false)` → `FormPickerRow(handle: FormDragHandle(index: i, label: colorReorder, identifier: paletteHandle(hex)), leading: ColorSwatchPreview(color), label: '#RRGGBB', onTap: _edit(color), showChevron: false, trailingButton: FormTrailingButton(delete_outline_rounded, tooltip: deleteColor, onPressed: _delete(color)), identifier: paletteRow(hex))` | `FormPickerRow(handle:)` (slice 1, done) mirrors `FormCheckRow(handle:)`: a `dragHandleSlot` at the row's start, the text at `dividerIndentGlyph`; with a `leading` as well the text sits past the 48 dp slot plus the leading column and the hairline at the title indent — the palette's rows are that case (the saved-filters rows carry a handle and nothing before the label), accepted as is; `proxyDecorator: reorderDragProxy` over `ClipRRect(reorderProxyRadius)` as the saved-filters sheet. The three palette id helpers fold `#` and lower-case, so `CalendarPalette.hexOf(color)` is passed straight | every row carries the handle; a long press lifts too |
| `FormRowShell(first: n == 0, last: true)` → `FormActionRow(glyph: add_rounded, label: addColor, onTap: n < 24 ? _add : null)` [palette-add] | disabled in place at the cap; the `colorPaletteFull` refusal never fires from here | |
| empty: `FormCaption(colorPaletteEmpty, padding: groupCaptionPadding)` under the group | | |
| `FormSectionLabel(colorPaletteDefaultsLabel)` and a `FormRowGroup` holding one `FormSwatchRow` of the eighteen built-in `ColorSwatchDot`s, bare (no tap), each `semanticLabel` its hex | the read-only strip | |
| `FormRowGroup(trailingGap: false)` → `FormActionRow(glyph: refresh_rounded, label: colorPaletteReset, destructive: true, onTap: custom.isEmpty ? null : _resetToDefaults)` [palette-reset] | the confirm as today; done → `OverlaySnackbar(colorPaletteResetDone)` | |

`_add`, `_edit`, `_delete`, `_reorder` and `_resetToDefaults` are today's
with `OverlaySnackbar` for every message. `colorPaletteDesc` and
`colorPaletteEditHint` are not shown.

### 3.8 The swatch strip (`ColorSwatchPicker`) and `FormSwatchRow`

`FormSwatchRow(child:)` (slice 1, `form_rows.dart`) is the Look sheet's
`_PaletteRow` hoisted: a `FormDividedRow` at the plain indent, `Padding(
groupInset, swatchRowTopPadding, groupInset, swatchRowBottomPadding)`, a
`Semantics(identifier:)` **container** (never a merge) over the strip —
`look-color` on the Look sheet, `swatch-row` elsewhere. The Look sheet uses
it with its suite's height formula unchanged (8 + runs × 48 + (runs − 1) × 2
+ 12).

`ColorSwatchPicker` keeps its constructor and `onChanged` contract. Inside a
`FormSwatchRow` it is called with `spacing: FormMetrics.swatchSpacing,
collapsible: false` (D13) by every sheet; the appearance page passes what it
passes today. Done in slice 1: `FocusManager.instance.primaryFocus?.unfocus()`
before `ColorPickerSheet.show`, `ColorPaletteSheet.show` and the menu; the
two `CustomSnackbar.showError` calls became `OverlaySnackbar`; the
long-press `_menuBody` became `showMenu` at `formMenuPosition` of
`FormMenuItemRow`s (`editColor` with `edit_outlined`, `deleteColor` with
`delete_outline_rounded` in the error colour, `manageColors` with
`palette_outlined`), each item carrying its id through
`FormMenuItemRow(identifier:)` — `swatch-menu-edit` / `-delete` / `-manage`
(a `PopupMenuItem` merges its subtree; that is where every menu of the
language carries an id); delete asks `AppDialogs.confirm(title: deleteColor,
content: deleteColorConfirm, confirmText: delete, isDestructive: true)` first
(D21). The default dot always draws a glyph (`format_color_reset_rounded`
when the caller passes none). Ids `swatch-default`, `swatch-add`,
`swatch-manage` on those dots through `ColorSwatchDot(identifier:)`. One
leftover for slice 3: the menu's floor is `FormMetrics.menuWidth` (220, a
`FormMenuRow`'s) where the preset ⋮ — the named precedent for an actions
menu — floors at `AppTheme.menuWidth` (236); the strip's menu takes the ⋮'s
floor, a one-word change.

### 3.9 The colour picker (`ColorPickerSheet`)

`show({initialColor})` → `int?` as today, the mode resolved before the push.
A sub-sheet: `FormSheetHandle`, `FormSheetHeader(close_rounded / cancel
[color-picker-close] · eventColorCustomTitle · FormHeaderTextButton(select,
onPressed: pop(_color.toARGB32())) [color-picker-select])`,
`Flexible(SingleChildScrollView(padding: (groupInset, bodyTop, groupInset,
bodyBottom + clearance)))` holding, in order: `FormChipRow(indented: false,
chips: [colorModeSquare, colorModeWheel])` [color-mode-square /
color-mode-wheel] driving `_setMode`; then today's `_GeometryBox`,
`_GradientSlider`, the preview-and-hex row (the two `_PreviewDot` targets at
`trailingButtonSize`, the hex field with `identifier: color-hex`, the copy
button `color-copy-hex`). The Cancel / Select bar goes. "Copied" through
`OverlaySnackbar`.

### 3.10 Copy and l10n

New keys, three locales:

| Key | en | de | ro |
| --- | --- | --- | --- |
| `colorPaletteResetDone` | Palette reset | Palette zurückgesetzt | Paleta a fost resetată |
| `holidayRestoreFailed` | Couldn't restore the holiday | Der Feiertag konnte nicht wiederhergestellt werden | Sărbătoarea nu a putut fi restaurată |

Changed, en only: `fastingColorDefault` "Default colour" → "Default color";
`calendarCellStyleDesc`'s "colour" → "color" (the app's en spelling is
American everywhere else). The duplicated `resetToDefault` entry (en :878
and :2033, de :204 / :654, ro :201 / :486) is reduced to the first in each
ARB; the text in effect was the later "Reset to Default" — the kept one
reads "Reset to default" (ro "Resetează la implicit", de unchanged) at its
five readers: the Markdown Shortcuts page's Reset-all item
(`markdown_settings_page.dart:2252`, outside the calendar), the Look sheet's
Icon-row reset (`event_look_sheet.dart:185`), the fasting style's icon reset
and title clear (`:228`, `:250`), the editor's Absent-from clear
(`event_editor_sheet.dart:2554`). Two tests pinned the capitalised string
and changed with it (§4.2 item 13). Done in slice 1.

Retired in slice 6, each only after a grep shows no reader left:
`colorPaletteDesc`, `colorPaletteEditHint`, `fastingPlacementHint`,
`categoryColor`, `colorPaletteBuiltIn`, `colorShowAll` (no sheet collapses
any more; the appearance page may still read it — keep it if it does).

### 3.11 Semantics ids (`lib/constants/semantics_ids.dart`)

Kebab-case, never renamed. Kept: `look-close`, `look-done`, `look-icon`,
`look-color`, `category-pick-*`, `month-year-*`, `icon-pick-*`,
`date-picker-*`. New:

| Surface | Ids |
| --- | --- |
| Day list | `day-list-close` · `day-list-back` · `day-list-mode-list` / `-month` / `-year` · `day-list-scope-upcoming` / `-calendar-year` · `day-list-whole-month` · `day-list-body` · the nav's `day-list-nav-previous` / `-next` / `-today` / `-title` (one set; the month nav and the year nav never share a screen) · the agenda card's `agendaCardDays(key)` = `agenda-card-days-<key with ':' as '-'>` |
| Category editor | `category-editor-close` · `category-editor-save` · `category-editor-name` · `category-editor-icon` |
| Swatch strip | `swatch-row` (the container, where the Look sheet has `look-color`) · `swatch-default` · `swatch-add` · `swatch-manage` · `swatch-menu-edit` / `-delete` / `-manage` |
| Fasting schedule | `fasting-schedule-close` · `fastingWeekday(n)` = `fasting-weekday-<1..7>` · `fasting-weekdays-all` / `-none` · `fasting-weekday-scope-weekly` / `-all` · `fastingMonth(n)` = `fasting-month-<1..12>` · `fasting-months-all` / `-none` · `fasting-month-scope-weekly` / `-all` · `fasting-days-off` · `fasting-extra-days` · `fastingDateRemove(kind, date)` = `fasting-<skip|force>-remove-<yyyy-MM-dd>` |
| Fasting style | `fasting-style-close` · `fasting-style-grid` with `-tint` / `-bar` / `-strong` / `-none` · `fasting-style-placement` with `-first` / `-before-holidays` / `-after-holidays` / `-last` · `fasting-style-icon` · `fasting-style-icon-reset` · `fasting-style-title` · `fasting-style-title-clear` · `fasting-style-description` |
| Removed holidays | `removed-holidays-close` · `holidayRestoreButton(nameKey, date)` = `holiday-restore-<nameKey>-<yyyy-MM-dd>` |
| Palette | `palette-close` · `palette-add` · `palette-reset` · `paletteRow(hex)` = `palette-row-<rrggbb>` · `paletteHandle(hex)` · `paletteDelete(hex)` |
| Colour picker | `color-picker-close` · `color-picker-select` · `color-mode-square` / `-wheel` · `color-hex` · `color-copy-hex` |

Flows (slice 7, the next free numbers): `17_day_list.txt` (sets the agenda's
Event rows to Summary through `agenda-filter-event-rows` →
`agenda-filter-event-rows-summary` → `agenda-filter-apply`, opens the
Strength card's days through its id, walks List / Month / a picked day /
Whole month / Year / Calendar year / a tile / Back to months, then resets
the filters through `agenda-filter-reset` → apply and leaves the mode on
List), `18_category_editor.txt`, `19_fasting_schedule.txt`,
`20_fasting_style.txt`, `21_removed_holidays.txt` (the seeded suppression
restored and the empty caption checked — the flow consumes the seed, since
the seeded date is no computed holiday and cannot be removed again from the
day panel; a lone re-run needs `qa relaunch --fresh --seed`), `22_palette.txt`
(the palette's rows, the colour picker from the Look sheet's add dot, the
swatch menu).

The fixture (slice 0, done) gained a **suppressed German built-in**
(`{"dateMs": "{{today+60}}", "nameKey": "christmasDay", "profile":
"germany", "suppressed": true}` — `importData` reads `dateMs` as an int and
the placeholder grammar has no fixed-calendar-date form, so the row sits on
a relative day; `suppressedHolidays()` lists any suppressed built-in
whatever its date) and **one custom colour** (`calendar_custom_colors`
`"4282339765"`, #3F51B5), so the removed-holidays row, the palette's rows,
its reorder and the swatch menu are reachable;
`test/qa/calendar_fixture_test.dart` pins both.

## 4. Behaviour

### 4.1 Must not change

**The day list**

- `AgendaDayListSheet.show` — its signature (`list`, `resolve`,
  `resolveMarks`, `yearBounds`, `appearance`, `today`, `windowStart`,
  `windowEnd`, `initialMode`, `onModeChanged`, `hapticFeedback`,
  `agenda_day_list_sheet.dart:95–131`) and `AgendaDayListResult` =
  `({focusDay, edit})`; the one caller `upcoming_agenda_view.dart:1017`
  (`_showDayList`, `:1011–1041`) and what it does with the result.
- The two scopes apart: list mode and the Upcoming tiles read only
  `AgendaDayListIndex` and never resolve; month mode and the Calendar-year
  tiles read only `AgendaMonthStore`, whole months (`:21–41`, tested).
  Entries pre-resolved; the sheet reads no facade.
- A row tap pops `(focusDay: day, edit: null)`; the pencil pops `(focusDay:
  null, edit: callback)` and the sheet never runs it (`:455–465`); the
  `_popped` guard; drag, barrier, back and the hardware back pop `null`
  **including while drilled** — **no `PopScope`, never `FormSheetFrame`**
  (`agenda_day_list_sheet_test.dart:384–417`).
- Only a mode pick persists the mode (`_selectMode`, `:317–330` →
  `onModeChanged`); a tile drill-down and the back arrow do not
  (`:399–419`); the key `calendar_day_list_mode`, default `list`; the year
  scope session-only, opening on `upcoming`.
- `_initialMonth` (`:217–225`): today's month clamped into the window
  months, then the bounds; month mode resolves its month before the first
  frame (`:201`); bounds `CalendarBounds`; resolve on navigation only; the
  store's one call per run; the prewarm 250 ms after settling (`:301–311`);
  haptics only when `hapticFeedback` (`:313–315`).
- Every count printed is attendance plus " · N missed"
  (`agendaDayListCountLabel`); missed rows at `CalendarColors.missedEventAlpha`
  (0.35); the header repeats the card's title **and** subtitle; the card's
  `color` tints tiles and matrix.
- `_pickDate` (`:370–397`) and `MonthYearPickerSheet.show`'s arguments; a
  pick moves month mode or lands the pager with the tile flashed.
- An unmarked day is inert; a marked day narrows the rows and toggles off on
  a second tap; Whole month restores (`_toggleSelectedDay`, `:436–443`).
- The mini grid's data contract (`AgendaMonthGrid`: cache-only `hasEntry` /
  `barsFor`, `enabledDayPredicate`, `outsideDaysVisible: false`, horizontal
  swipe only), `AgendaYearGrid`, `AgendaYearPager`, `YearMonthTile`.
- The overview page's use of `AgendaMonthGrid`, `AgendaPeriodNav`,
  `AgendaDayListRowView`, `buildAgendaDayListRows` and
  `agendaDayListCountLabel` keeps working unchanged in behaviour; its suite
  (`calendar_overview_page_test.dart`, 16) passes unedited.
- `_AgendaCard` is not restyled (the `calendar-events` rule); it gains an
  id and nothing else.

**The category editor**

- `show({initial, initialName})` → `CalendarCategory?`
  (`category_editor_sheet.dart:31–45`); the saved category is **written
  inside the sheet and then returned** (`_onSave`, `:151–182`); the three
  callers (`calendar_categories_page.dart:144`, `:150`,
  `category_picker_sheet.dart:201`) and what each does with the result.
- `create` vs `updateCategory` (`category_service.dart:196–236`,
  `:259–271`): a built-in keeps its stored `name`; the three absent columns.
- `initialName` prefill; autofocus on create only; the trimmed name required
  for customs; the 40-character cap; `_canSave` (`:126–130`); the soft
  duplicate warning, hidden variant included, never blocking Save
  (`:96–110`); a failed save re-enables Save and says why; no default colour
  dot; no hide or delete control.
- The icon picker's call (`:133–137`).

**The fasting schedule** (`docs/fasting-schedule-roadmap.md` whole, the
feature doc §4.5 `:840–878`)

- `show({initialSchedule, appearance, onChanged})` → `void`
  (`fasting_schedule_sheet.dart:36–53`); the caller
  `calendar_settings_page.dart:271` and its `onChanged`; `_apply` on every
  control, live, no Save, no debounce, dismissing never discards.
- One schedule under `calendar_fasting_schedule`; the seed rule (`null` ≠
  `''` for the retired CSV); the defaults; subtracts never invents; the two
  scopes and their meaning; `forceDates` wins, the sets disjoint, the cap of
  200 with the add control disabled and "Limit reached"; `pickMulti` used
  purely additively with `initialSelection: const {}` and the cross-removal
  in `_pickDates` (`:89–125`); removal per date; labels from `intl`; the
  weekday options reusing the month-scope keys; the hint following the
  selected scope (`fasting_schedule_sheet_test.dart`, 4 tests, bodies kept);
  the month scope selector visible with all twelve months ticked; an empty
  month set legal.

**The fasting style** (the feature doc §4.5 `:814–832`,
`fasting_appearance.dart`)

- `show({tradition, initialStyle, onChanged})` → `void`
  (`fasting_style_sheet.dart:34–51`); the caller
  `calendar_settings_page.dart:254`; `_apply` live; dismissing never
  discards.
- What is persisted under `calendar_fasting_appearance`: `style`,
  `placement`, `colorValue` (null = the shared violet, through `clearColor`),
  `iconKey` (null = the tradition's icon, through `clearIcon`),
  `titleOverride` and `description` (blank normalised to null in
  `copyWith`); the defaults tint / afterHolidays; the placement → priority
  map; appearance display-only; the limits 120 / 500.
- The preview leads, resolves its icon from the draft, draws the description
  as plain text; the sample period and regime per tradition.

**Removed holidays**

- `show(context, holidayService)` → `void` (`removed_holidays_sheet.dart:19–33`),
  the caller `calendar_settings_page.dart:415`; `suppressedHolidays()` as
  the source; `_restore` → `restoreSuppressed(date, holiday)` **deletes** the
  suppression row (`:48–59`); customs never listed; a profile switch drops
  suppressions.

**The palette** (the feature doc `:4171–4344`, `:4403–4469`)

- `show(context)` → `void` (`color_palette_sheet.dart:30–41`); the callers
  `calendar_appearance_page.dart:829`, `color_swatch_picker.dart:144`,
  `:211`.
- Built-ins never stored or deletable; the custom half insertion-ordered,
  capped at 24, a refusal explained; `add` / `update` / `remove` /
  `resetToDefaults` / `move` and their bools; **row order = picker-dot
  order**; the reorder as a sliver list inside the one scrollable; the
  handle with a label, never a tooltip; delete and reset confirmed; reset
  drops only the custom half; `lastRecolor`; no widget holds the service;
  `calendar_custom_colors` on the backup allow-list.

**The swatch strip** (the feature doc `:4222–4233`, `:4450–4459`)

- The constructor (`value`, `onChanged`, `defaultOption`, `spacing`,
  `collapsible`, `color_swatch_picker.dart:37–60`); `onChanged(null)` only
  from the default dot; the orphan dot; **the add dot adds what it picks to
  the palette permanently and selects it** (`:113–135`); the manage dot;
  long-press only on custom swatches; the selection following a recolour
  (`:107–111`); the `_sheetOpen` guard; 48 dp targets around 44 dp dots;
  every swatch named by its hex; the four embeddings' arguments
  (`calendar_appearance_page.dart:795`, `event_look_sheet.dart:191`,
  `fasting_style_sheet.dart:198`, `category_editor_sheet.dart:308`) and the
  Look sheet's `_setColor` (`:126–132`); the Look sheet's own suite
  (`event_look_sheet_test.dart`, 12) and `template_form_robot.dart:598–619`
  pass unedited.

**The colour picker** (the feature doc `:4279–4401`, `:4437–4469`)

- `show({initialColor})` → `Future<int?>`, opaque alpha; the mode resolved
  before the push and the `_opening` flag (`color_picker_sheet.dart:70–88`);
  square by default, the wheel persisted under `color_picker_mode`; one
  fixed-height geometry box so switching moves nothing below it; one slider
  (hue / brightness); the hex contract (`^#?[0-9a-fA-F]{6}$`, live on six
  digits, inline error, `maxLength: 9`, a grey keeps the hue); the
  before/after pair only when replacing and the revert; copy; the drag
  taking focus from the hex field; the semantics steps; arrow keys, Shift ×
  5; Select returns what the preview painted. The six callers
  (`color_swatch_picker.dart:117`, `:151`, `color_palette_sheet.dart:63`,
  `:73`, **`markdown_colors_page.dart:76`, `:83`**) and what they do.
- `calendar_sheet_double_tap_test.dart:116–171` passes unedited.

**Around them**: the Look sheet's look and behaviour (it gains a hoisted
row and nothing else); the icon picker, the Dates sheet, the description
sheet, the month/year picker; the categories page, Calendar settings and
the appearance page beyond the one-line call sites; the schema, the backup
format, every service.

### 4.2 Deliberately changes

Each of these changes a test on purpose; the slice that makes the change
names the test in its report.

1. **The day list's rows are the language's** (D3): finders by `ListTile`,
   `CircleAvatar`, `Opacity` ancestor and the raw `Text`s move into the
   robot; `find.text('Whole month')` becomes the ✕ by id; the month-level
   section header is gone (the count is read from the nav); `modeControl`
   and `scopeControl` become the chip rows; the pinned header rect is
   re-pinned at its new geometry; the clearance cases read the new
   paddings.
2. **✕ and ← in the header** (D5): a new way out, and the back arrow in the
   header's leading slot (its 48 dp target test moves with it).
3. **The fasting style's text fields** (D18): a confirmed dialog or Done
   writes at once; the debounce tests slice 0 writes flip to "writes on
   confirm, never on cancel".
4. **The fasting schedule's bulk actions are action rows** disabled in place
   (D16); the hints move into captions and the placement hint goes.
5. **The palette's one add control** (D20), the counter's place, the empty
   caption; the built-in dots announced by hex.
6. **The swatch menu's delete is confirmed** (D21); the strip never
   collapses inside a sheet (D13) — `color_swatch_picker_test`'s collapse
   cases keep testing the widget with `collapsible: true` directly.
7. **The colour picker's actions move to the header** (D22): eight finders
   and the clearance case move into the robot; "Switching moves nothing
   below the picker" compares the hex field and the geometry box, no longer
   a bottom button.
8. **The category editor's counter and warning** (D14): the counter appears
   from 30, the warning on its own line in the error colour.
9. **Messages over sheets**: eight `CustomSnackbar` sites become
   `OverlaySnackbar`; tests that found a `SnackBar` find the overlay.
10. **Focus dropped** before every picker and sheet the four surfaces open.
11. **Ids everywhere** (§3.11) and the nav's optional identifiers.
12. **The mini grid's weekday row and the nav's title** (D6, D7) change on
    the overview page too, without a behaviour change there.
13. **"Reset to Default" reads "Reset to default"** (§3.10) at its five
    readers; `event_look_sheet_test.dart:37` and
    `event_editor_redesign_test.dart:1541` pinned the capitalised string and
    now pin the kept one (slice 1).

## 5. Facts from the tree (`daf361a`, re-grep before editing)

The explorer's full report is the source (one section per surface, (a)–(k));
what the slices touch:

**Day list** — `lib/widgets/agenda_day_list_sheet.dart` (854): route
`:109–130` (0.88); header `:500–588` (the slot `:160`, the back arrow
`:512–522`, the title and subtitle `:527–543`, the mode button `:551–584`);
body `:590–655`; the row builder `:657–665`; the month nav `:667–692`; the
grid `:694–707`; the section header `:709–765` (the `Visibility` `:749–760`);
the year body `:767–843` (the scope button `:778–794`); `_pickDate`
`:370–397`; the exits `:451–465`. `lib/widgets/agenda_day_list_rows.dart`
(208): the row model `:9–93`, `agendaDayListCountLabel` `:97–101`,
`AgendaDayListRowView` `:105–208` (also the overview's). The opener
`upcoming_agenda_view.dart:1017`; the card's button
`agenda_list_view.dart:1295–1300`; the card builder `:841–857`.
`lib/widgets/agenda_period_nav.dart` (118, no identifiers);
`lib/widgets/agenda_month_grid.dart` (137; `daysOfWeekHeight: 24` `:79`, no
`daysOfWeekStyle`; also `calendar_overview_page.dart:852`);
`lib/utils/calendar_days_of_week.dart` (35). The overview's copy of the
section header `calendar_overview_page.dart:986–998`.

**Category editor** — `lib/widgets/category_editor_sheet.dart` (339): route
`:31–45`; header `:215–240`; body `:241–316` (the avatar `:248–258`, the
built-in field `:260–270`, the custom field `:271–287` with the tertiary
`helperStyle` `:283`, the icon `Card` `:289–303`, the strip `:308–312`);
`_duplicateOf` `:96–110`; `_canSave` `:126–130`; `_pickIcon` `:133–137`;
`_onSave` `:151–182` (the snackbar `:180`); `_SectionLabel` `:322–339`.

**Fasting schedule** — `lib/widgets/fasting_schedule_sheet.dart` (440):
route `:36–53`, the 0.86 in `build` `:137–138`; header `:142–159`; body
`:161–265`; the exceptions `:89–125`; `_ExceptionSection` `:368–440`; the
helpers `:275–353`.

**Fasting style** — `lib/widgets/fasting_style_sheet.dart` (464): route
`:34–51`, the 0.86 `:144–145`; header `:149–166`; body `:168–302` (the
preview `:172–181`, the style chips `:182–196`, the strip `:197–209`, the
icon `Card` `:210–235`, the title field `:236–259`, the description
`:260–272`, the placement chips and hint `:273–300`); the debounce `:67`,
`_applyTextDebounced` / `_flushPendingText`; `_pickIcon` `:124–128`;
`_Preview` `:342–464`.

**Removed holidays** — `lib/widgets/removed_holidays_sheet.dart` (124):
route `:19–33` (0.6); `_restore` `:48–59` (the snackbar `:58`); header
`:78–85`; body `:86–120`.

**Palette** — `lib/widgets/color_palette_sheet.dart` (373): route `:30–41`;
`_add` `:57–70` (snackbars `:60`, `:69`); `_edit` `:72–84` (`:80`);
`_delete` `:86–98`; `_reorder` `:100–102`; `_resetToDefaults` `:104–118`
(`:117`); header `:136–158`; body `:163–296`; `_CustomColorRow` `:309–353`;
`_Label` `:355–373`.

**Swatch strip** — `lib/widgets/color_swatch_picker.dart` (447):
`ColorSwatchDefault` `:16–22`; the constructor `:37–60`; `_collapsedRuns`
`:69`; `_onPaletteChanged` `:107–111`; `_addFromPicker` `:113–135` (the
snackbar `:128`); `_openPaletteSheet` `:144`; `_editCustom` `:146–157`
(`:156`); the menu `:174–213`; the build `:229–302`; `ColorSwatchDot`
`:347–427`; `ColorSwatchPreview` `:430–447`. The Look sheet's `_PaletteRow`
`event_look_sheet.dart:282–301` and `_LookMetrics` `:45–54`.

**Colour picker** — `lib/widgets/color_picker_sheet.dart` (1104): `show`
`:70–88`; the clearance wrap and scroll view `:370–377`; the header row
`:378–411`; `_GeometryBox` `:413–464`; the slider `:469–501`; the preview
and hex row `:503–555`; the bar `:557–570`; `_copyHex` (the snackbar
`:232`); `_PreviewDot` `:1088–1092`.

**Tests** — `agenda_day_list_sheet_test.dart` (1599; 63 cases; the helpers
`:146–188`, `scrollMonthBody` `:159–173`, `wholeMonthActive` `:175–188`, the
pinned rect `:629–659`); `upcoming_agenda_view_test.dart` (9 cases open the
sheet by `find.byTooltip('Show every day')`, `scrollSheetBody` `:116–130`,
`tapThisYear` `:135–147`); `sheet_bottom_clearance_test.dart` (the day list
`:240–316`, the category editor `:384–425`, the palette `:369–382`, the
colour picker `:349–367`); `category_picker_sheet_test.dart:282–333`;
`fasting_schedule_sheet_test.dart` (4); `color_palette_sheet_test.dart`
(5); `color_swatch_picker_test.dart` (11); `color_picker_sheet_test.dart`
(19; the `FilledButton 'Select'` finders `:71, :115, :171, :258, :359,
:368–376`, `TextButton 'Cancel'` `:205, :336`);
`calendar_sheet_double_tap_test.dart:116–171`; `event_look_sheet_test.dart`
(12; the height formula `:328–359`, the ids `:382–411`);
`template_form_robot.dart:598–619`; `calendar_overview_page_test.dart` (16);
`calendar_fixture_test.dart:157–171`. No suite: the category editor, the
fasting style, removed holidays.

**Deleted by the end of slice 6** — in the sheets: both `SegmentedButton`s,
the `Visibility` header, the hand-drawn header and its 48 dp slots, the
`ListTile` + `CircleAvatar` entry row *inside the sheet* (the shared
`AgendaDayListRowView` stays for the overview), `_SectionLabel`, the icon
`Card`s, the outlined fields, `_labelRow` / `_label` / `_hint`,
`_ExceptionSection`, the `OutlinedButton`s, the `ChoiceChip`s and
`FilterChip`s, the preview `Card`, the debounce, the palette's header `+`
and its `OutlinedButton`, `_CustomColorRow`, `_Label`, the colour picker's
bar and title row, the swatch strip's `ListTile` menu, the Look sheet's
`_PaletteRow` and `_LookMetrics`, every height factor other than
`sheetHeightFactor` (0.88, 0.85, 0.86, 0.86, 0.6, 0.86), every `AppSpacing`
read in the four files that have them, every `CustomSnackbar` call in the
eight files.

## 6. Slices

### Slice 0 — The safety net

Tests only, against the old UI, green. In `test/widgets/support/`: a robot
per surface — `DayListRobot`, `CategoryEditorRobot`, `FastingScheduleRobot`,
`FastingStyleRobot`, `RemovedHolidaysRobot`, `PaletteRobot`, `SwatchRobot`
(the strip inside any sheet and on its own), `ColorPickerRobot` — each a
thin driver (open through the static `show`, act by the old finders, read
back) so that every suite's body names what it does, never how. Move the
existing suites onto them with names, order and expected values unchanged
(`agenda_day_list_sheet_test.dart`, `upcoming_agenda_view_test.dart`'s nine
openers, `fasting_schedule_sheet_test.dart`, `color_palette_sheet_test.dart`,
`color_swatch_picker_test.dart`, `color_picker_sheet_test.dart`,
`event_look_sheet_test.dart`'s swatch cases, `category_picker_sheet_test`'s
two). New suites pinning what each writes today, against fakes or the
in-memory settings backend: `category_editor_sheet_test.dart` (create,
edit, a built-in's fixed name, `initialName`, the duplicate and hidden
warnings, Save disabled on blank, a failed save, every exit returning
null), `fasting_style_sheet_test.dart` (every control's `onChanged`
payload, the debounce and its flush — pinned under "today:" names that
slice 4 flips, the preview's draft icon, the icon reset, blank text → null),
`removed_holidays_sheet_test.dart` (loading, empty, rows, restore and its
message). The three missing clearance entries. The fixture's two additions
(§3.11) with `calendar_fixture_test.dart`. Gate: analyze clean; the suite
count rises; nothing else changes.

### Slice 1 — Primitives, ids, copy, the shared pieces

1. `FormMetrics`: the names of §3.1; `category_name.dart`.
2. `form_rows.dart`: `FormSwatchRow` (§3.8, hoisted from the Look sheet,
   which uses it — its suite passes unedited); `FormSectionLabel(trailing:)`;
   `FormPickerRow(handle:)`; `FormTitleRow(warning:)`; each with its cases
   in `form_rows_test.dart`.
3. `AgendaPeriodNav`: the four optional identifiers and the two-line
   measured title (§3.2); `AgendaMonthGrid` on `CalendarDaysOfWeek` with its
   row height following D7 (after the page's cells are checked at 200 % —
   the fix lands where the defect is); tests in a new
   `agenda_period_nav_test.dart` and in the overview and day-list suites.
4. `ColorSwatchPicker`: the focus drop, the overlay messages, the popup
   menu, the confirmed delete, the glyph on every default dot, the ids
   (§3.8); `color_swatch_picker_test` gains cases for each.
5. `SemanticsIds` (§3.11), the agenda card's id, the ARB keys and fixes
   (§3.10) in three locales, `gen-l10n`.

No sheet changes its look except through the hoisted row, which is
pixel-equal.

### Slice 2 — The day list

After the owner's D1–D3. Rebuild `AgendaDayListSheet` (§3.2). Rewrite
`DayListRobot`; the bodies change only for §4.2 items 1, 2, 11 and 12. New
cases: the ✕ and ← paths; the chip rows' ids and selection; a picked day's
✕; German at text scale 2.0 and a 360 × 780 surface in every mode with
nothing clipped (the weekday row, two-digit day numbers, the nav's title on
two lines); the clearance cases.

### Slice 3 — The category editor

Rebuild `CategoryEditorSheet` (§3.3). Rewrite `CategoryEditorRobot`; the
bodies change only for §4.2 items 8, 9, 10 and 11. New cases: the built-in
read row; the warning line; the swatch row inside the editor (ids, no
collapse); focus dropped before the icon picker; German 2.0 / 360 × 780.

### Slice 4 — The two fasting sheets

Rebuild `FastingScheduleSheet` (§3.4) and `FastingStyleSheet` (§3.5).
Rewrite both robots; the bodies change only for §4.2 items 3, 4, 10 and 11.
New cases: every chip's id and width constancy across its state; the bulk
rows disabled in place; the caption slot's constant height across the
scope; the exception rows and their removes; the cap; the menu rows' items
by id; the title dialog and the description sheet round trips; German 2.0 /
360 × 780; the clearance cases.

### Slice 5 — Removed holidays, the palette, the colour picker

Rebuild the three (§3.6, §3.7, §3.9). Rewrite the three robots; the bodies
change only for §4.2 items 5, 7, 9 and 11. New cases: the restore row and
its failure; the palette's rows with handle, delete and recolour, the
disabled add at the cap, the counter, the read-only built-in strip's
labels; the colour picker's header actions, the mode chips, the 48 dp
dots, "Copied" over the sheet; the markdown colours page still receiving
the picked colour (a widget test through `markdown_colors_page.dart`'s
`_addColor` path); German 2.0 / 360 × 780; the clearance cases.

### Slice 6 — Delete the old UI and the dead keys

Everything §5's last paragraph names that is still in the tree, each after a
grep for its last reader; the retired ARB keys (§3.10); `gen-l10n`;
`untranslated.txt` `{}`. No literal number and no `AppSpacing` value remains
in the nine sheet files.

### Slice 7 — Device pass, review, docs

1. **Device pass** through the `qa-emulator` skill on the iPhone 17 Pro
   simulator: `./tool/qa/qa run --fresh --seed tool/qa/fixtures/calendar.json
   -d ios`, then `qa flows calendar` — the seventeen saved flows green
   before anything else, then the six new ones; the matrix `qa set
   theme=dark locale=de text-scale=2.0` with every board of the canvas shot
   beside it and every setup sheet shot in both cells; the day list's month
   mode at 200 % (the weekday row, two-digit numbers, "Oktober 2026" on two
   lines, the groups); the removed-holidays row in German at 200 % whole;
   the fasting schedule's chips at 200 %; `qa errors` clean; `qa set
   theme=light locale=system text-scale=off` at the end.
2. **Independent review** by a fresh read-only `fable-max` that has not seen
   the session: this record and the diff, confirmed defects only; fix what
   it confirms; a device re-check; re-run the gate.
3. **Docs in the same change**: an addendum in
   `docs/calendar-events-feature.md`; `COPILOT_CONTEXT.md`'s calendar
   sections; the rule lines in `calendar-events` (the day list, the fasting
   sheets, the palette), the hoisted row and the primitives' new parameters
   in `ui-language`'s table, the new ids and the flow count in
   `calendar-ui`, the flow count in `qa-emulator`;
   `calendar-language-adoption-roadmap.md` §9 and its §2.4 corrections
   (the editor's delete, the Look sheet's strip, the palette's sharing, the
   two extra snackbar sites, the day-list memory note); this record's
   status line and §9.

## 7. Definition of done

1. For the same input each surface returns or writes what its old version
   did: every robot-driven test passes with its body unchanged, except the
   bodies §4.2 names.
2. Day list: List, Month, Year, both scopes, a picked day, Whole month, a
   tile into its month and ← back, a row tap returning its day, the pencil
   returning its edit, ✕ / drag / back / barrier returning null (drilled
   included); only a chip persists the mode; the header never moves across
   modes.
3. Category editor: create, edit, a built-in, from the picker; the duplicate
   warning never blocks; a failed save re-enables Save with its message over
   the sheet; the strip's add dot still adds to the palette.
4. Fasting schedule: every control writes the schedule it wrote before,
   live; the hints follow the scope; the cap disables the add rows in
   place; dates removable one by one.
5. Fasting style: every control writes its style live; the title dialog and
   the description sheet write on confirm and nothing on cancel; the preview
   follows the draft.
6. Removed holidays: a row restores and disappears; the message is over the
   sheet; empty and loading states.
7. Palette: add at the cap disabled with the count visible; edit, delete
   (confirmed), reorder by handle and by long press, reset (confirmed, only
   the custom half); the markdown colours page still picks a colour.
8. One-handed at 360 × 780: every chip, dot, handle, button and row has a
   48 dp target; the header reachable without scrolling.
9. Light and dark; en, de and ro; text scale 1.3 and 2.0 with no clipped
   label and no overflow — the day list's month mode at 200 % included.
10. Keyboard up and down in the category editor and the colour picker: the
    clearance rule holds, nothing shifts, nothing under the navigation bar.
11. Every string through `AppLocalizations` in three ARBs;
    `untranslated.txt` `{}`; no retired key referenced in `lib`, `test`,
    `tool`.
12. One semantics node per row (two for a two-target row); every id of
    §3.11 seen on its control in a device dump; tooltips on every icon
    button.
13. Nothing §5 lists for deletion is referenced; no literal number and no
    generic `AppSpacing` value in the nine sheet files.
14. The seventeen saved flows and the six new ones green; `qa errors` clean
    after the matrix.

## 8. Deferred

- **The overview page's rows** (`AgendaDayListRowView`, its section header
  with the `Visibility` button, its Year / Month / List order) — Tier 4.
- **The confirm dialog's style** — open app-wide decision 2; the palette's
  and the swatch menu's confirms keep `AppDialogs.confirm(isDestructive:)`.
- **A two-line `FormSheetHeader` at 200 %** — still the owner's open call
  from Tier 1; "Kategorie bearbeiten" ellipsizes.
- **The Upcoming year tile "Nov 2026 · 0"** for a window that ends on the
  first of a month: the window is the agenda's (`windowEnd`), not the
  sheet's; a window that ends on the 1st is the Period's doing. Raise with
  the owner at Tier 4 together with the agenda's period labels.
- **The jump picker's day wheel** (`MonthYearPickerSheet` always shows a day
  wheel) — Tier 1's surface; a `showDay: false` mode is a feature.
- **The colour picker's hex field** keeps its outlined label; the picker's
  body is chrome-exempt by the master.
- **The appearance page's swatch strip** (five columns, 10 dp) and the
  preview's empty marker labels — a settings page, out of scope (app-wide
  decision 1).
- **The Text colors page** (no route from Settings, an unlabelled FAB,
  inert preset rows, a monospace name) — not the calendar's.
- **Calendar settings' "Holiday set" row** wrapping as "Holiday / set" at
  1.0 — seen on the way, Tier 2's capped tile; the owner may look at it.
- **The Markdown Shortcuts page** overflowing at German 200 % ("Symbol after
  amount", `markdown_settings_page.dart:1463`) — Tier E of the app-wide
  master.
- **German copy** mixes "Termin" (the day list's count) with "Ereignis"
  elsewhere — a copy question for the owner.
- **`OverlaySnackbar` over a short sheet** (slice 7's device pass): the bar
  sits a fixed 80 dp above the screen's bottom (`bottomOffset`) for its
  duration, and on a content-tall sheet of one row — the removed-holidays
  sheet right after its restore — that is the header, so the sheet's ✕ is
  under "Holiday restored" for the 2 s it shows (the bar's own dismiss stays
  reachable, and the flow `21_removed_holidays` waits the bar out). An
  app-wide overlay (`lib/widgets/overlay_snackbar.dart`), not a Tier 3 file;
  an app-wide call — raise the bar above a short sheet, or shorten its life
  over one.
- **`YearMonthTile` titles ellipsize beside the count** at German 1.3 and
  2.0 ("Jan. 20…", "Okt…") in the day list's year scopes, and through the
  same tile on the overview and in the Dates sheet's year view. §4.1 keeps
  the tile as it is; Tier 4's surface, with the overview's rows.
- **Seen on the device and left by the language's rules**: the fasting
  preview's sample title ("Große Fastenz…") keeps its one-line clamp at
  German 2.0 — a second line there would move every row under the preview
  the moment the user sets a longer custom title, and the row's node carries
  the whole text; the day list's entry captions clamp at two lines with an
  ellipsis at German 2.0 ("Woche 5 · Wöchentlich · Mo,…"), the stacked row's
  own rule, the node reading the whole subtitle; the sheet headers' titles
  ellipsize at 2.0 ("Kategori…", "Eigene …", "Symbol & F…"), the open
  two-line-header call above.

## 9. Ledger

| Slice | Date | Result |
| --- | --- | --- |
| — | 2026-10-03 | Record written after the explorer pass, the device walk and the canvas; D1–D3 asked of the owner and answered A, A, A |
| 7 · fixes | 2026-10-03 | **Fix round, done, uncommitted**, on the independent review's gaps 1, 2 and 6 (the review confirmed no defect). **(1) `AgendaPeriodNav`'s measurement cached** (`agenda_period_nav.dart`): a month nav formatted and laid out its year's twelve `yMMMM` titles — thirteen `TextPainter`s with the shown one — on every rebuild, and every `setState` of the day list or the overview rebuilds it (a day tap, a scope change). The tallest of the twelve now lives in a static `LruCache<_YearTitlesKey, double>` (`lib/utils/lru_cache.dart`, the map the editor's span caches and the note repository use; `yearTitleCacheSize` 32, least recently used dropped) keyed on the locale name, the year, the available width, the `TextScaler` itself (value-equal for the linear, the system and the clamped scaler), the title's whole `TextStyle` (its size and weight and every other attribute that lays it out — the colour costs one entry per theme), the text direction and `FormMetrics.periodTitleMaxLines` (a static outlives a hot reload that edits it); a static rather than a `State` field, which would die with the day list. The shown title stays one layout per build, the count's one-line box too, and a year nav never asks the cache; `@visibleForTesting static int get measurementCount` counts the misses; `package:intl` is imported `show DateFormat` (its own `TextDirection` collides with Flutter's once the key names the type). `agenda_period_nav_test.dart` +2, the eight existing cases unedited: "a year's twelve titles are laid out once per key…" (the same nav rebuilt and a page inside the year lay out nothing — the paged title drawn, the box unchanged —, a year nav asks nothing, another year, text scale, locale and width each lay them out once more, the first width again none) and "the remembered boxes are bounded…" (one year past `yearTitleCacheSize`, the least recently shown is laid out again while the newest is still remembered). **(2) `FormPickerRow.handle`'s doc** (`form_rows.dart`) says what the code does: the row's content starts 4 dp past the 48 dp slot, at `dividerIndentGlyph`; with nothing before the label the text starts there and the hairline indents to it (the saved filters' check rows), with a `leading` the text starts past the slot and the leading column and the hairline takes `dividerIndentTitle`, as under any `leading` (the palette's rows); the inline comment over `leftInset` said "the text" of that column and now says "the content". No code change. `FormCheckRow.handle`'s doc keeps its sentence: the combination it misdescribes (a handle beside a `leading`) has no caller there. **(3) The strip's two refusals** (`color_swatch_picker.dart`, `_refuse`: `colorPaletteFull`, `colorAlreadyInPalette`) pass `duration: AppConstants.snackbarErrorDuration` (3 s), the palette sheet's duration for the same two messages, where they took `OverlaySnackbar`'s 4 s default. No test asserted the default; `color_swatch_picker_test.dart` +1, "a refusal comes down after the error duration the palette sheet gives the same message, not the overlay's longer default". **Each new case seen to fail without its fix** (the cache never hitting; the refusal at 4 s — 3 failed, 25 passed) and to pass with it. Gate: `dart analyze lib test` clean; `flutter test` **6810 passed / 7 skipped / 0 failed** (6807 before, +3). **Device re-check** on the iPhone 17 Pro simulator, the fixed tree built fresh (`qa run --fresh --seed`, 63 placeholders resolved): `00_open` then `17_day_list` green (55 / 55 steps, `errors` clean). At dark German 200 % through the agenda (Demnächst · `agenda-filter-open` · `-event-rows` · `-event-rows-summary` · `-apply` · `agenda-card-days-category-qa-cal-strength` · `day-list-mode-month`): "Oktober 2026" on two lines over "8 Einträge" whole, and the row's height unchanged — the dump's title box [975, 1275] px and count [1275, 1371], the grid from 1383 and its week rows from 1455 to 2385, "Heute · 1 Eintrag" at 2439, the boxes the `look` of `20261003_142400_fix_nav_month_de.png` drew at the same places (`build/qa/shots/20261003_144620_fixes_nav_month_de.png`). The year scope (`day-list-mode-year` → `day-list-scope-calendar-year`): `View "32 Einträge · 1 verpasst"` its own node between the chevron and the today slot, `id=day-list-body` without a label, the count whole in the shot (`20261003_144657_fixes_nav_year_de.png`). `qa errors` clean after the matrix and again after the restore: the mode chip back on List (the re-check's two chip taps had persisted Year), `set theme=light locale=system text-scale=off`, the agenda's filters reset, the panel on Day (`20261003_144723_fixes_restored.png`). The app was left up on the fixed build |
| 7 · review | 2026-10-03 | **Independent review** by a fresh read-only `fable-max` (the working tree against `daf361a`, one `dart analyze lib test`, no other command). **No confirmed defect**: every §4.1 line held against the new and old code — the day list's `show` and result, the `_popped` guard, dismissal with `null` while drilled with no `PopScope`, only a chip persisting the mode, the two scopes apart, `_initialMonth`, the prewarm and haptics, the counts; the category editor's save-then-return, `create` vs `updateCategory`, the built-in's stored name, the never-blocking warning, the cap and counter; both fasting sheets' live `_apply`, the additive `pickMulti` with the explicit cross-removal, the hint following the scope through the caption slot, the month scope row with all twelve ticked, the cap, blank → null, `clearColor` / `clearIcon`, the preview from the draft; `restoreSuppressed` and the failure path; the palette's five service calls, row order = dot order, the sliver reorder in the one scrollable, the labelled handle; the strip's `onChanged` contract, the add dot adding permanently, long-press on customs only, the recolour follow, the focus drop, the `AppTheme.menuWidth` floor, the confirmed delete; the colour picker's `show`, `_opening`, the mode before the push, the hex contract, one slider, the geometry box, the pair and revert, the semantics steps, the six callers; `CalendarDayCell`'s fitted number static at 1.0; `AgendaPeriodNav`'s candidates in the shown format with the locale and scaler honoured; every new primitive parameter optional behind an `if` (existing callers build the same tree); every id of §3.11 present, unique, on the right node; the three ARBs consistent, no reader of a retired key, `untranslated.txt` `{}`; the clearance suite covering every sheet of the tier; the fixture test pinning both seed additions; the §4.2 body changes matching the ledger and no other old body changed. **Ten gaps**, three taken to the fix round: the nav's twelve-title measurement ran on every rebuild (uncached), `FormPickerRow.handle`'s doc described the no-`leading` geometry only, the strip's two refusals used the overlay's 4 s default where every other error site passes 3 s. Noted, not acted on: the day list's ✕ pops outside the `_popped` guard (every sub-sheet's ✕ does; a route animating out ignores pointers); the German 200 % day-list case proves the two-line title box, not a whole title (the device pass proved the whole title); two `today:`-named cases in the template suite are Tier 2's grandfather rules; the hex field's `AutomationId` folds the decorator's label into the field's node (the `FormSearchRow` precedent); the overview's weekday row and nav title changed with the shared widgets (D6, §4.2 item 12) |
| 7 · device | 2026-10-03 | **Device pass** on the iPhone 17 Pro simulator (402 × 874 dp, iOS 26.2, the tree of slices 0–6 built fresh with `qa run --fresh --seed`, 63 placeholders resolved). `qa flows calendar`: 15 / 17 on the first run, then **17 / 17** after two changes that were neither a screen change nor an app defect — (1) `15_templates` stopped at `wait "New template"`: on this simulator `scroll-to` returned 150 ms after its last swipe while the settings list was still flinging (the agent's swipe op settles for at most 500 ms, a fling under iOS physics runs longer), so the row ended at the viewport's edge and the next tap's pointer-down stopped the list instead of pressing it — fixed in the tool, `ScrollToCommand` now settles until no frame is scheduled (`_flingSettleMs` 2500, returned early the moment the frames stop) before every dump, which also ends the "overshoot" the brief named; `dart analyze tool test_driver` clean; (2) the same flow's `expect "Leg day B"` after "Keep editing" counted the name absent because the form stays scrolled to Priority from the step before and on 874 dp the title row is then above the fold (the Pixel's 952 dp never scrolled it off) — the flow scrolls the name back first. `16_alert_defaults` had failed only because 15 left the app on the settings page. **Six new flows** (§3.11, every control by id where it has one, each ending in expects, a shot and `errors`): `17_day_list` (the agenda's event rows set to One card, the Strength card's `agenda-card-days-category-qa-cal-strength`, List · Month with today picked by `{{longdate}}` and Whole month · Year in both scopes · a tile by `{{year}} --nth 0` drilled and ← back · List; ✕; the filters reset and the panel on Day; the mode left on List), `18_category_editor` (the Strength edit form, the icon picker, the create form with the duplicate warning; "Categories" is the settings page's section header on the exact pass, so the row is named by its second line), `19_fasting_schedule` (Monday toggled twice, the weekday scope's two hints, the exception rows, Days off into the Dates sheet and Cancel), `20_fasting_style` (the grid menu's four items, the title dialog's "Great Lent" hint and Cancel), `21_removed_holidays` (the seeded `holiday-restore-christmasDay-{{day+60}}` restored, "No holidays removed", ✕ after the bar has left — consumes the seed), `22_palette` (the appearance page's row by "of your own" — "Colors" matches four nodes there and the page has its own "Search settings" field — the custom row's three ids, Add color into the picker's Square and Wheel, the Look sheet's swatch menu by long press). Each green alone after `00_open`, then **23 / 23** twice: on the slices' build and again on the fixed build at the end; `qa errors` clean after both and after the matrix (no engine noise on the simulator). **Every id of §3.11 seen on its control in the dumps**: the day list's thirteen and the card's; the editor's four; `swatch-row` / `-default` / `-add` / `-manage` and the three menu items; the schedule's close, 1–7, 1–12, the four bulk rows, the four scope chips, the two exception rows and `fasting-skip-remove-2026-10-04` (a date added through the Dates sheet and removed again; the `force` kind shares the builder and is pinned by the suite, not exercised on the device); the style sheet's close, `-grid` with its four items, `-placement` with its four, `-icon`, `-icon-reset` (an icon picked, then reset), `-title`, `-title-clear` (a title set, then cleared), `-description`; `removed-holidays-close` and the restore; `palette-close` / `-add` / `-reset` and the row's `palette-row-3f51b5` / `-handle-` / `-delete-`; the picker's six. **The matrix** (`set theme=dark locale=de text-scale=2.0`, every surface shot and read, `build/qa/shots/20261003_14*_m_<surface>_de.png`: `m_17_list` / `_month` / `_month_day` / `_year_upcoming` / `_year_calendar` / `_drilled`, `m_18_edit` / `_create_dup` / `_long_dup`, `m_19_top` / `_exceptions` / `_with_date` / `_date_row`, `m_20_top` / `_placement` / `_text_rows` / `_title_set` / `_icon_picker` / `_icon_set` / `_description`, `m_21_row`, `m_22_palette` / `_picker` / `_picker_wheel` / `_look` / `_swatch_menu`; then `set text-scale=1.3` for `m13_17_list` / `_month` / `_year`, `m13_19_top` / `_exceptions`, `m13_20_top` / `_text`): the day list's month mode has "Oktober 2026" on two lines over "8 Einträge", the weekday row Mo–So whole, every two-digit number whole, the picked day's read row "Heute · 1 Eintrag ✕"; the caption wraps freely; the chips whole in both runs; "Weihnachten / 2. Dezember 2026" whole with its restore; the schedule's chips whole, two-line scope chips growing in place, the months' Select all dimmed in place; "Freie Tage / 1 Ausnahme" and "So., 4. Okt. 2026 ✕"; the style sheet's menu items wrapping ("Nach Feiertagen" on two lines), "Eigener Titel / Fastenzeit ✕", "Symbol / Eigenes Symbol ↻"; the palette "DEINE FARBEN 1 VON 24", the built-in strip, "Farben zurücksetzen" on two lines; the picker's chips, box, hue slider and hex row whole; the Look sheet's strip with "Symbol einfärben" dimmed; the swatch menu's three items wrapping. At 1.0 light: the read-only built-in strip sits on the pickers' grid (six per row, the same dots); the Square / Wheel chip group stands in a group above the geometry box; the preview leads on its group with no card; the duplicate warning reads `"Strength" already exists` in the error colour under the field with Save enabled, and under a 32-character duplicate at 200 % the warning (four lines) and the counter "32/40" share the line under the field; the hex row holds "#4595E6" with its copy button. The Days off row's dimmed caption at the cap (200 dates) was not reached on the device — the suite pins it. **Found and fixed** (in `AgendaPeriodNav`, the one tier file both findings sit in, with two cases in `agenda_period_nav_test.dart`; the overview takes both without a behaviour change): the nav's count had no node of its own under the day list's `day-list-body` container — in the Calendar-year scope the dump read `View "33 entries · 1 missed" id=day-list-body`, the count announced on the body before the scope chips, while month mode's sliver gave it a node — now `Semantics(container: true)`; and the count cut to "32 Einträge · 1 verpa…" at German 2.0 between the chevrons and the today slot — now shrunk to fit (D7's `FittedBox(scaleDown)`) inside a box of its one-line height at the current text scale, so a month with a longer count is no taller. Gate after the fix: `dart analyze lib test` clean, `flutter test` **6807 passed / 7 skipped / 0 failed** (6805 before); re-checked on the fixed build at German 2.0 — `View id=day-list-body` without a label, `View "32 Einträge · 1 verpasst"` its own node after the title, whole in the shot (`fix_nav_year_de`), month mode unchanged (`fix_nav_month_de`). **Found and recorded, not Tier 3's** (§8): `OverlaySnackbar`'s fixed 80 dp bottom offset puts "Holiday restored" over the one-row sheet's header for its 2 s, so a ✕ tapped in that window hits the bar (the probe's tap did; the flow waits the bar out); `YearMonthTile`'s titles ellipsize beside the count at German 1.3 and 2.0 ("Jan. 20…", "Okt…") — §4.1's tile, Tier 4; and three one-line clamps left by the language's rules (the preview's sample title, the entry captions, the sheet headers). **Not verifiable here**: anything Android-only — the system navigation bar's colour, Gboard's inset, the `E/AccessibilityBridge` noise. The app was left up on the fixed build, light, system locale, platform scale |
| 6 | 2026-10-03 | **Done, uncommitted.** Nothing visual changed: every number this slice touched kept its value, so the Look sheet's, the strip's and the palette's suites pass unedited. **Deleted**: `_LookMetrics` — its one survivor, `iconRowPadding` (8 above and below a 40 dp avatar under a 56 dp minimum), is the title row's own geometry, so the Look sheet's Icon row reads the existing `FormMetrics.titleRowVerticalPadding` rather than a new name, and that constant's `///` now names the Icon row as its second reader; the strip's last literals, into a private `_SwatchMetrics` with its why in the shape of the fasting style's `_PreviewMetrics` (`looseSpacing` 8 as the constructor's default — reached only by a bare strip, every sheet passing `swatchSpacing` and the appearance page its own 10 — `ringWidth` 1 / `selectedRingWidth` 2.5, `glyphShare` 0.5, `previewDiameter` 24 for `ColorSwatchPreview`); the stale "no debounce to flush either" in the schedule's class comment (slice 4 deleted the style sheet's debounce the "either" pointed at). **Already gone**, removed by the rebuilds of slices 2–5: everything else §5's last paragraph lists — both `SegmentedButton`s, the `Visibility` header, the hand-drawn header and its slots, the `ListTile` + `CircleAvatar` entry row, `_SectionLabel`, the icon `Card`s, the outlined fields (the colour picker's hex field excepted, kept by §8), `_labelRow` / `_label` / `_hint`, `_ExceptionSection`, the `OutlinedButton`s, the `ChoiceChip`s and `FilterChip`s, the preview `Card`, the debounce, the palette's header `+` and its `OutlinedButton`, `_CustomColorRow`, `_Label`, the picker's bar and title row, the strip's `ListTile` menu, `_PaletteRow`, every height factor other than `sheetHeightFactor`, every `AppSpacing` read and every `CustomSnackbar` call; the sweep `AppSpacing|CustomSnackbar|showDragHandle: true|heightFactor: 0.(88|85|86|6)` over the nine files is empty, and the only `CircleAvatar` left is the fasting preview's sample avatar under `_PreviewMetrics`, not the day list's row. **Keys retired** from the three ARBs and the en `@` blocks, each after a grep of `lib`, `test` and `tool` found no reader: `colorPaletteEditHint`, `fastingPlacementHint`, `categoryColor` (its only hits are two local variables of that name in the editor and the template form), `colorPaletteBuiltIn`; no flow or test found their texts either; `gen-l10n`, `untranslated.txt` `{}`. **Kept with their reader**: `colorPaletteDesc` (`calendar_appearance_page.dart:819`, the palette entry's search keywords); `colorShowAll` (`color_swatch_picker.dart`, the collapsed strip's "more" dot — §3.10 guessed the appearance page, and it is that page's strip that still collapses, through the strip's own `collapsible` default; `color_swatch_picker_test` keeps testing the collapse directly, §4.2 item 6). **The literals that remain in the nine files, and why**: the colour picker's picking body, chrome-exempt (§3.9 "verbatim", §8) — `_maxSquareHeight` 240, `_step` 0.02, `_semanticStep` 0.05, `_coarseStepFactor` 5, `_modeFade` 150 ms, the opening HSV (210, 0.7, 0.9), the hex grammar with its `maxLength: 9`, the hue and percent arithmetic, the geometry box's `width / 1.5` clamped at 140, the square's 12 dp corner, the painters' thumbs (9 / 10.5, strokes 3 / 1.5 / 2, a 0.6 alpha), the wheel's 60° stops, the slider theme (track 20, thumb 11 at elevation 2, overlay 22), the arrow's 16 px glyph and `_PreviewDot`'s 36 dp dot (slice 5's row); the day list's two durations (`_pageDuration` 260 ms, `_prewarmDelay` 250 ms — §4.1's prewarm); `maxLines: 1` three times in the fasting preview; the named private metric classes with a `///` why — `_PreviewMetrics` (fasting style) and `_SwatchMetrics` (the strip); the schedule's `_monthLabelAnchorYear` 2024 (the `intl` anchor, `///`) and the strip's `_collapsedRuns` 3 (`///`); and the non-geometry: the structural zeros of `EdgeInsets.fromLTRB` (the day list's caption, month sliver and year body, the palette's first and last slivers, the Look sheet's right inset while a trailing button is the sibling), counters' initial values and index arithmetic (day list, strip), date arithmetic (`DateTime.utc(y, m, 1)`, `month + 1, 0`, `_year ± 1`, `12, 31`), the category editor's `-1` memo sentinel, the strip's record accessors `$1` / `$2`. Gate: `dart analyze lib test` clean; `flutter test` **6805 passed / 7 skipped / 0 failed** (unchanged — no test referenced a retired key). **Existing bodies changed**: none. **Corrected against the record**: §5's `_LookMetrics` resolved by reading an existing `FormMetrics` name, not adding one; `dart format` would rewrap two lines this slice never touched (the strip's `SizedBox.square(...)` at :559, the Look sheet's `Expanded(child: FormLabelValue(...))` at :252) and was left alone, per the dart-format rule of 2026-10-01. Slice 7's device pass owes this slice nothing: no pixel moved |
| 5 | 2026-10-03 | **Done, uncommitted.** The three sheets rebuilt in the shape of slices 3–4: the route on `pageGround` under the `sheetRadius` top, `useSafeArea`, clamped at `sheetHeightFactor`; `Column(min)` of `FormSheetHandle` · `FormSheetHeader` (the ✕ by id, the title, the hairline of a `FormHeaderHairline`, `trailingInset: headerActionInset`) · `Flexible` over the scrolling body padded `groupInset, bodyTop, groupInset, bodyBottom + clearance`; every message through `OverlaySnackbar` (success and error durations from `AppConstants`). **Removed holidays** (§3.6): ✕ `removed-holidays-close` with the `close` tooltip, an empty trailing slot; the body a `SingleChildScrollView` holding, while loading, the spinner centred in a `rowMinHeight` box (so the sheet opens at its first row's height), empty the `FormCaption(removedHolidaysEmpty, groupCaptionPadding)`, else one `FormRowGroup(trailingGap: false)` of read rows — `FormPickerRow(event_busy_rounded, nameOf(holiday), yMMMMd(date), onTap: null, no chevron)` with `FormTrailingButton(restore_rounded, holidayRestore, holidayRestoreButton(nameKey, date))` as the second target. `_restore` in a `try/catch`: the success path drops the row and says `holidayRestored`; a throw re-reads the list through `_load()` (a delete that threw may or may not have landed) and says `holidayRestoreFailed`. Deleted: the centred title, `ListView.separated`, the `Divider`, the `ListTile` + `TextButton`, the 0.6 and every literal, `CustomSnackbar`. **The palette** (§3.7, D20): ✕ `palette-close`; the body a **shrink-wrapped** `CustomScrollView` under the clamp — content-tall and still the one scrollable, the saved-filters list's trick — of three `SliverPadding`s: the section label with `colorPaletteCapCount(n, 24)` as its trailing; the `SliverReorderableList` (`onReorderItem: _reorder` as today — `onReorder` is deprecated on this Flutter; `proxyDecorator` the shared proxy over `ClipRRect(reorderProxyRadius)`) of the custom rows, each a `ReorderableDelayedDragStartListener(key: ValueKey(color))` so a long press anywhere lifts it, over `FormRowShell(first: i == 0, last: false)` over `FormPickerRow(handle: FormDragHandle(index, colorReorder, paletteHandle(hex)), leading: ColorSwatchPreview, label: hex, onTap: _edit, no chevron, paletteRow(hex), trailingButton: delete_outline_rounded / deleteColor / paletteDelete(hex))`; the last sliver, carrying `bodyBottom + clearance` on its bottom (where the clearance case already read it), holding the Add color row in `FormRowShell(first: n == 0, last: true)` — `FormActionRow(add_rounded, addColor, palette-add)` disabled in place at the cap, `_add`'s own cap check and `colorPaletteFull` kept as the contract — the empty caption under it with the group gap below, BUILT-IN COLORS over a `FormRowGroup` of one `FormSwatchRow` of the eighteen bare dots in a `Wrap` at `swatchSpacing`, and Reset colors as a destructive `FormActionRow(refresh_rounded, palette-reset)` in a `FormRowGroup(trailingGap: false)` dimmed while nothing is custom; the reset's done message `colorPaletteResetDone`. Deleted: the header `+`, `colorPaletteDesc` / `colorPaletteEditHint` / `colorPaletteBuiltIn` as readers, the `OutlinedButton`, `_CustomColorRow`, `_Label`, the `TextButton.icon`, the 0.86, every `AppSpacing` (9) and literal, `CustomSnackbar`. `ColorSwatchDot`'s bare form (no tap, no long press) now lays out in the `tapTarget` footprint and carries its `semanticLabel` as a plain node: the old bare branch dropped the label (eighteen silent circles) and sat at 44 against the pickers' 48 — the explorer's "132 px against 144" finding; the interactive branch is untouched. **The colour picker** (§3.9, D22): the route flags and the clamp; ✕ `color-picker-close` with the `cancel` tooltip, `eventColorCustomTitle`, `FormHeaderTextButton(select, color-picker-select)` popping `_color.toARGB32()`; the body a `FormRowGroup` holding the `FormChipRow(indented: false)` of the two mode chips (`color-mode-square` / `-wheel`, driving `_setMode`), then today's `_GeometryBox`, slider and preview-and-hex row verbatim but for `FormMetrics.gap` where the three `AppSpacing.md` reads were, the arrow's `xs` padding dropped (the 48 dp dots give it more air than it had), `AutomationId(color-hex)` on the hex field (the search row's shape) and `AutomationId(color-copy-hex)` on the copy `IconButton`, and `_PreviewDot` at `trailingButtonSize` around its 36 dp dot. `_copyHex` through `OverlaySnackbar`. Deleted: the title row and its `SegmentedButton`, the Cancel / Select bar, the whole-sheet `Padding(bottom: clearance)`, the 20 padding, every `AppSpacing` (7), `CustomSnackbar`. **The leftover**: `FormPickerRow(captionMaxLines:)` (null = the glyph row's free wrap; the stacked shape keeps its two) and the fasting style's Description row at `valueMaxLines`, with a `form_rows_test` case (clamped with an ellipsis, free without) and a `fasting_style_sheet_test` case (two lines, cut, the node reading the whole line) through the robot's new `descriptionCaptionLines` / `descriptionCaptionClamped`. **Robots rewritten**: `RemovedHolidaysRobot` (rows from the picker rows, `restoreId(name)` / `restore(name)` by the row's restore id draining until the sheet has said something, `message` / `messageReachable` / `scaffoldSnackbarShown` on the overlay bar, `rowNode`, `rowWhole`, `nameRect` / `dateRect`, `targetOf`, `nodeOf`, `close`; `settle()` and the `runAsync` drain kept; `locale` / `textScale` / `surface` on `show`); `PaletteRobot` (rows by `palette-row-*`, `edit(hex)`, `delete(hex)`, `dragRow` on the `FormDragHandle`s, `dragRowByLongPress` on a row's label, `add()` / `addEnabled` (revealing first) by `palette-add`, `reveal(id)`, `capText` the section label's trailing source text, `builtInCount` / `builtInLabels` / `builtInNodes` / `builtInTargets` the bare dots, `reset()` / `resetEnabled`, `emptyCaptionShown`, `message` / `messageReachable`, `nodeOf`, `targetOf`, `rowRect`); `ColorPickerRobot` (`select()` / `cancel()` / `selectShown` / `selectRect` / `selectLabel` on the header's action, `pickMode` by the chip ids, `currentMode` from the chips' `selected` cross-checked against the drawn geometry, `copyHex` by id, `copiedMessageShown` / `copiedMessageReachable`, `dotTargets`, `copyButtonRect`, `nodeOf`, `targetOf`; every read works on whatever picker is open, so a page suite drives it without `show`). Gate: `dart analyze lib test` clean; `flutter test` **6805 passed / 7 skipped / 0 failed** (6781 before). **Existing bodies changed** (§4.2 items 5, 7, 9, 11): removed holidays — "today: the restored message is drawn under the sheet" → "the restored message is drawn over the sheet" (reachable, no `SnackBar`); the picker — "switching geometry moves nothing below the picker" compares the geometry box's and the hex field's rects (Select is the header's now and could never move); the clearance suite — the picker's case reads the scroll padding and the hex field's bottom and gained a tall-keyboard twin, the palette's keeps its last-`SliverPadding` read (the rebuilt sheet keeps that shape) plus the reset row's bottom, the removed-holidays pair reads the scroll padding and the row by its restore id. Named by item 5 and 7 but passing **unedited** through the robots: "an empty palette explains itself…" (the robot reads the action row), "dragging a row reorders the palette itself" (the robot drags the `FormDragHandle`), "copy puts the hex code on the clipboard" (the robot reads the overlay). `calendar_sheet_double_tap_test`, `color_swatch_picker_test`, `event_look_sheet_test`, the service suites and `backup_service_calendar_round_trip_test` pass unedited; `markdown_colors_page.dart` untouched. New (+24): removed holidays (+4) — the row's one node of name and date without a tap, the restore's id (`holiday-restore-christmasDay-2026-12-25`), tooltip and button flag, the ✕'s id, tooltip and a close that restores nothing; a failed restore keeping the row, re-reading and saying `holidayRestoreFailed` over the sheet (`restoreSuppressed` made to throw by a `BEFORE DELETE` trigger the suite installs on the sheet's own database and drops after — no service seam exists); German 2.0 on 360 × 780 with no layout error, "Tag der Arbeit" and "1. Mai 2026" whole with the date under the name, every control inside the sheet; 48 dp targets. Palette (+8) — the row's three nodes and ids; a tap recolouring through the picker and Add color adding through it (the service and the rows agreeing, the count following); the add row disabled in place at the cap with "24 of 24", no tap action, a tap opening nothing; the built-in strip's labels the eighteen hexes, no button flag, no tap, 48 dp footprints; the reset's done message over the sheet; a long press anywhere lifting a row (the service's order moved, no picker opened); German 2.0 on 360 × 780 with no layout error and every control inside the sheet; 48 dp targets (✕, handle, delete; the row at 56, the add and reset rows at 48). Colour picker (+6) — the header's two actions by id, Select reading "Select" and returning the colour, ✕ null; the mode chips' ids and announced selection, a pick remembered; both dots 48 dp; the hex node a text field carrying its id and value, the copy button its id and tooltip, the chips button nodes; "Copied" over the sheet, no `SnackBar`; German 2.0 on 360 × 780 ("Auswählen") with no layout error, the hex row inside the sheet. The clearance suite (+1), `form_rows_test` (+1), `fasting_style_sheet_test` (+1), and the new `test/pages/markdown_colors_page_test.dart` (+3): the add FAB → the name dialog → the picker → the colour on the page and in `markdown_custom_colors`; a cancelled picker adding nothing; a row tap opening the picker on the row's colour and persisting the pick. **Corrected against the record**: §3.7's bare dots had no accessible name and no 48 dp footprint in `ColorSwatchDot`'s bare branch (fixed there, the only bare use being the palette); §3.9's "standalone chip row as the body's first row" is hosted in a `FormRowGroup` — a row of the language stands in a group, and bare it would sit 16 dp in from the geometry box; the brief's `addEnabled()` is a future that reveals first and `customRows` sees only the built rows — the run is a lazy sliver list, a semantics id has no node past the viewport's reach, so the cap is pinned through the count; §3.6's "a test seam the service already offers" — none exists, the trigger is the seam; `flagsCollection.isSelected` is a `Tristate` on this Flutter. Slice 7's device pass still owes: the look of the read-only strip on the pickers' grid, the chip group above the geometry box, the hex row at 200 % |
| 4 | 2026-10-03 | **Done, uncommitted.** `FastingScheduleSheet` and `FastingStyleSheet` rebuilt as the sub-sheets of §3.4 and §3.5 in the category editor's shape: the route on `pageGround` under the `sheetRadius` top, `useSafeArea`, clamped at `sheetHeightFactor`; `Column(min)` of `FormSheetHandle` · `FormSheetHeader` (✕ `fasting-schedule-close` / `fasting-style-close` with the `close` tooltip, the title, an empty trailing slot at `headerActionInset`, the hairline of a `FormHeaderHairline`) · `Flexible(SingleChildScrollView)` padded `groupInset, bodyTop, groupInset, bodyBottom + clearance`. **The schedule**: WEEKLY FAST DAYS over a group of the seven weekday `FormChip`s (`fastingWeekday(n)`) in a standalone `FormChipRow` with `fastingWeekdayDaysDesc` as its caption, Select all / None as `FormActionRow`s (`done_all_rounded` / `remove_done_rounded`, `fasting-weekdays-all` / `-none`) disabled in place at the no-op, the weekday scope a labelled chip row (`tune_rounded`, chips `fasting-weekday-scope-weekly` / `-all`) whose caption is a `FormCaptionSlot` over both hints showing the selected scope's; MONTHS YOU KEEP the same over the twelve month chips (`fastingMonth(n)`, `fasting-months-all` / `-none`, `fasting-month-scope-weekly` / `-all`), the scope row kept with all twelve ticked; a third group (`trailingGap: false`) of the two exception rows — `FormPickerRow(glyph, label, value: "Limit reached" at the cap else "None" or fastingExceptionsCount(n), caption: the hint, enabled: below the cap)` with `fasting-days-off` / `fasting-extra-days` — each followed by one `FormPickerRow(subRow: true, onTap: null, showChevron: false)` per date ascending with a ✕ `FormTrailingButton` (`remove`, `fastingDateRemove(kind, date)`). `_apply`, the two toggles, `_addDates` (its additive `pickMulti` call and the explicit cross-removal), `_removeDate`, `_monthLabel`, the four hint helpers and the shared scope labels verbatim. **The style**: PREVIEW over a group holding `_Preview` drawn on the group — no `Card`, no tinted ground, `RowMetrics.twoLinePadding` around it, `FormMetrics.gap` between the cell and the row, the sample's own geometry as `_PreviewMetrics` with its why, `CalendarColors.fastingTintAlpha` for the wash and `EventAvatar.backgroundAlpha` for the avatar — the sample number in a `FittedBox(scaleDown)` on one line inside an `Expanded` under the cell's top inset, so the cell cannot overflow at any scale (D19; it also yields to the bar's slot); the cell `ExcludeSemantics`, the row one `MergeSemantics` node; a group of the two `FormMenuRow`s (`grid_on_rounded` · Show on the grid with `fasting-style-grid-tint` / `-bar` / `-strong` / `-none`; `low_priority_rounded` · Order in the day panel with `-first` / `-before-holidays` / `-after-holidays` / `-last`; `fastingPlacementHint` not shown); a group of the Icon row (`emoji_symbols_rounded`, `fastingIconDefault` / `iconCustom`, `_blur()` then `IconPickerSheet.show` as today, the reset a `refresh_rounded` second target `fasting-style-icon-reset` only while an icon is set) and `FormSwatchRow(swatch-row)` over `ColorSwatchPicker(spacing: swatchSpacing, collapsible: false, defaultOption: CalendarColors.fasting / fastingColorDefault)`; a last group (`trailingGap: false`) of Custom title (`title_rounded`, value the override or `eventLookDefault`, `_blur()` then `AppDialogs.textInput(title, hintText: the computed period name, initialValue, maxLength: kFastingTitleMaxLength)`, a confirmed value → `copyWith(titleOverride:)`, a cancel nothing, the ✕ `fasting-style-title-clear` writing `copyWith(titleOverride: '')` while set) and Description (`notes_rounded`, caption the hint or `MarkdownPlainText.strip(description, money: false)`, `_blur()` then `EventDescriptionSheet.show(initialText, heading: the tradition's name, limit: kFastingDescriptionMaxLength, grandfatheredLength: the text's own length)`, Done → `copyWith(description:)`, `null` and an unchanged Done nothing). New `lib/constants/fasting_style_limits.dart` (`kFastingTitleMaxLength` 120, `kFastingDescriptionMaxLength` 500). Deleted: both hand-drawn headers, both `ListView`s and their 0.86, `_label` / `_labelRow` / `_hint`, `_ExceptionSection`, the `OutlinedButton`s, the `ListTile` date rows, every `FilterChip` and `ChoiceChip`, the icon `Card` and the preview `Card`, both outlined fields, the 400 ms debounce with `_applyTextDebounced` / `_flushPendingText` and both controllers, every `AppSpacing` read (16 + 11) and every literal. Both robots rewritten: every control by id; a scope's hint as the caption its slot shows (drawn and hit-testable, where the laid-out twin is not); the dates as the sub-rows between the two exception rows; the title through its dialog and the description through its sheet, with `MarkdownBarBloc` above the app; `_tap` brings a control into view only when it is not already, so a tap never scrolls the body under a case comparing rects; `textWhole` / `sectionLabelWhole` / `controlLabelWhole`, `targetOf`, `nodeOf`. Gate: `dart analyze lib test` clean; `flutter test` **6781 passed / 7 skipped / 0 failed** (6768 before). **Existing bodies changed** (§4.2 items 3–4, 10–11): schedule — "at the cap the add button is disabled and reads Limit reached" expects the empty force row's value "None" where it expected the old button's "Add dates" (the row's value is the count, D17); the four hint cases and both Select all / None cases pass unedited through the robot. Style — "today: a typed title is written only after the 400 ms debounce" → "a confirmed title dialog writes at once and a cancelled one writes nothing"; "today: a pending text write is flushed when the sheet closes" → "a description confirmed with Done writes at once; a dismissed description sheet writes nothing" (an unchanged Done writes nothing too); "today: German at text scale 2.0 on 360 × 780 lays out but for the preview's sample day cell" → "… lays out with no layout error: the preview's sample day cell included, every row's label whole" (D19); "the title override replaces the sample period in the preview" and the four "the sample period and regime follow the tradition (…)" read the computed name through `await robot.titleHint()` — the hint moved from the inline field into the title dialog's field, so reading it opens and cancels the dialog (item 3). The clearance suite's four fasting cases read `scrollBottomPadding` where they read a `ListView`'s; the nav-bar cases gained the last row's bottom ≤ surface − navBar (`fasting-extra-days` / `fasting-style-description`); the tall-keyboard cases tap ✕ by id. New (+13): schedule — a chip's rect the same selected and unselected and the run around it never reflowing (weekdays, months, the scope pair); Select all / None disabled in place at the no-op in both sections with their rects held and a disabled row writing nothing; the caption slot's height constant across the scope on both axes with the next section's row at the same distance; the exception rows and each remove carrying ids, a remove a button named Remove and writing the schedule without its date; at the cap the Days off row disabled (its node flagged, inert, "Limit reached" in its label) and the Extra fast days row enabled; German 2.0 on 360 × 780 with no layout error — both section labels, every chip, action, scope and exception label whole, every control inside the sheet; every control a 48 dp target at 360 × 780; the ✕'s id, tooltip and a close without a write. Style — the two menus' items by id with the current one checked, a pick writing at once and read back; the Custom title row reading Default, its clear only with an override, a confirmed blank the clear; the Description row's hint while empty and the stripped text once set, the preview keeping the raw text; the ✕ and every row carrying ids, the strip a container, no `Card`; every control a 48 dp target at 360 × 780. **Corrected against the record**: §3.5's "the computed period name as a hint-coloured value" was superseded by the brief's `eventLookDefault` ("Default") as the title row's value, so the computed name lives on as the title dialog's hint — a behaviour five bodies pinned and D18 never meant to drop; §3.5's "two lines" for the description caption is not what `FormPickerRow` draws under a glyph (no clamp) and the brief named none — the strip's 200-character cap bounds it, and a clamp would be a primitive change for slice 5 or the review; §3.4 names `_pickDates` for what the sheet calls `_addDates` (kept); the two limits 120 / 500 had no named home in §3.1 (now `fasting_style_limits.dart`); the record's `enabled: false` at the cap dims the whole exception row, its caption included, where the old UI dimmed the button alone — the language's disabled row, accepted; the robots' tall default surfaces (1200 × 3000, 800 × 1600) stay, now so that every group is on one screen rather than for a lazy list. Slice 7's device pass still owes: the look of the preview on the group at 200 % and of the Days off row's dimmed caption at the cap |
| 3 | 2026-10-03 | **Done, uncommitted.** `CategoryEditorSheet` rebuilt as the sub-sheet of §3.3 in the quick alarm's shape: the route on `pageGround` under the `sheetRadius` top, `useSafeArea`, clamped at `sheetHeightFactor`; `Column(min)` of `FormSheetHandle` · `FormSheetHeader` (✕ `category-editor-close` / `cancel`, the title, `trailingInset: headerActionInset`, the hairline of a `FormHeaderHairline` as the quick alarm carries, Save as a `FormHeaderTextButton` `category-editor-save` following the name's controller through a `ListenableBuilder`, disabled on a blank name) · `Flexible(SingleChildScrollView)` padded `groupInset, bodyTop, groupInset, bodyBottom + clearance` holding one `FormRowGroup(trailingGap: false)`: the name — a custom category's `FormTitleRow` (the draft's `EventAvatar` as the leading preview, `categoryNameHint`, `kCategoryNameMaxLength` / `kCategoryNameCounterFrom` with `eventTitleCount`, autofocus on create only, sentences, `warning:` through `_duplicateOf`, id `category-editor-name`), rebuilt off the controller inside a `FormIndentedRow(dividerIndentTitle)` so the warning follows the typing without a rebuild of the form and the group keeps the title indent; a built-in's `FormPickerRow(leading: avatar, label: labelOf, caption: categoryDefault, onTap: null, showChevron: false)` read row — then Icon (`emoji_symbols_rounded` · `iconLabel` · `pickIcon`, id `category-editor-icon`, `_blur()` before `IconPickerSheet.show` as today), then `FormSwatchRow(swatch-row)` over `ColorSwatchPicker(spacing: swatchSpacing, collapsible: false)` with no default dot. `_onSave`, `_canSave`, `_duplicateOf`, the service calls, the prefill and the cap verbatim; the failure through `OverlaySnackbar` at the error duration. Deleted: the hand-drawn header and its filled Save, the preview `CircleAvatar`, both outlined fields, `_SectionLabel`, the icon `Card`, the 0.85 and every literal, `CustomSnackbar`. The two leftovers: the day list's `FormHeaderHairline` removed (field, `watch`, `dispose`, `scrolled:`) and its header given `trailingInset: headerActionInset`; the strip's menu floor `AppTheme.menuWidth` (the preset ⋮'s) under the unchanged `menuMaxWidth` cap. `CategoryEditorRobot` rewritten (✕, Save, the name field and the Icon row by id; the title row's warning and counter lines with their colours; the read row and its node; the avatar on either row; the overlay bar; the strip through `SwatchRobot`; targets, `textWhole`, `nodeOf`). Gate: `dart analyze lib test` clean; `flutter test` **6768 passed / 7 skipped / 0 failed** (6762 before). **Existing bodies changed** (§4.2 items 8–10): "the counter counts towards the 40-character cap" → "the counter appears from 30 characters, reads n/40 and takes the error colour at the 40-character cap"; "today: the failure message is a Scaffold snackbar under the sheet" → "the failure message is drawn over the sheet, where a finger can reach it" (no `SnackBar`, hit-testable); "today: the name field keeps focus when the icon picker opens" → "the focus is dropped before the icon picker opens and does not come back when it closes"; "today: German at text scale 2.0 on 360 × 780 overflows the sheet at its header" → "… lays out with no layout error: the title, the text action and every row whole" (create and a built-in); the clearance suite's "the category editor sheet clears the navigation bar" gained the quick alarm's last-row assertion (the strip's row above the bar) and its tall-keyboard case passes unedited; `color_swatch_picker_test`'s "a long press on a custom swatch opens a popup of three items by id, hung from the dot" reads the floor from `AppTheme.menuWidth`. The category picker's two editor-opening cases pass unedited through the robot. New (+6): the built-in read row (avatar, localized label, caption, no chevron, one node, no tap); the warning line in the error colour, gone with the name, Save enabled; the strip inside the editor not collapsible with ten custom colours on 360, `swatch-row` a container, `swatch-add` / `swatch-manage` tappable, no default dot; the avatar following a picked swatch and icon on a built-in; every control a 48 dp target at 360 × 780 (✕, Save, the title row, the Icon row, every dot); the ids on ✕, Save, the name field and the Icon row, Save disabled and never absent on a blank name. **Corrected against the record**: §3.3's "hairline above at the plain indent" for the Colour row — the group draws a hairline at the indent of the row *above* it, so the line over the strip sits at the Icon row's glyph indent (52), as in the Look sheet; a plain indent would govern only a hairline below the strip, which is last; the counter reads "30/40" (the shared `eventTitleCount`, no spaces around the slash); the header's `trailingInset` and hairline are the quick alarm's shape, which §3.3 did not spell out; the stacked read row's caption clamps at two lines (the primitive's rule), so in the box font at German 200 % "Integrierte Kategorie" ellipsizes while the label stays whole. Slice 7's device pass still owes: the look of the warning and the counter sharing one line under a long duplicate at 200 % |
| 2 | 2026-10-03 | **Done, uncommitted.** `AgendaDayListSheet` rebuilt as the filler of §3.2: the route on `pageGround` under the `sheetRadius` top at `sheetHeightFactor`; `Column(stretch)` of `FormSheetHandle` · `FormSheetHeader` (✕ `day-list-close`, replaced by ← `day-list-back` while drilled, an empty trailing slot, the hairline of a `FormHeaderHairline` watching the body) · the pinned `FormCaption` with the card's line, wrapping freely · the pinned mode `FormChipRow` with its three ids · the body under `day-list-body`. List mode: a `ListView.builder` of `FormSectionLabel`s and `FormRowShell`s — a day's read row `FormPickerRow(onTap: null, showChevron: false, dividerIndentPlain)`, an entry row with its `EventAvatar`, the subtitle as caption and the pencil as the trailing button, a missed one inside `Opacity` inside `FormIndentedRow(dividerIndentTitle)`, the last row of a group carrying the gap and the list's last none. Month mode: the nav (its four ids) and the grid at full width, then the same shells in a `SliverPadding(groupInset, groupGap above)`, the picked day's read row carrying ✕ `day-list-whole-month`, the empty caption as a sliver, the trailing `bodyBottom + clearance` sliver. Year mode: the scope chip row (two ids) over the grid, or the year nav (the same four ids) over the pager. Deleted: the hand-drawn header and its two slots, both `SegmentedButton`s, the section header with its `Visibility`, `_sectionHeaderHeight`, `_headerSlot`, the 0.88 and every literal. `_recompute`, the store, the resolvers, the prewarm, `_pickDate`, the drill-down pair, `_toggleSelectedDay`, the exits and `_selectMode` verbatim; `AgendaDayListRowView` untouched for the overview (D10). `DayListRobot` rewritten (chips, the ✕/← and the nav by id; rows as `FormPickerRow`s; `shows` / `countOf` matching a section label by its source text, since the label draws capitals; `openFromCard` by the card's id; `textScale` / `surface` on `show`). Gate: `dart analyze lib test` clean; `flutter test` **6762 passed / 7 skipped / 0 failed** (6754 before). **Existing bodies changed** (§4.2 items 1–2): "the month count names the missed occurrences beside it" reads the picked day's read row where it read the section header; "the year scope selector fits on one row at 320dp" became "whole labels in 48 dp runs at 320, one row at 400" — the test font's "Demnächst" + "Kalenderjahr" take two runs below 386 dp; "the fixed header never moves between modes or states" re-pinned at (0, 147.2)–(360, 195.2); the clearance suite's month and year cases tap the chip by id where they tapped the segment's icon. New (+8): the ✕ paths, ← in the leading slot and the ✕ back after it, the chips' ids with their announced selection and the body's id, the picked day's ✕ restoring the groups, the read row inert and one node without a chevron, the entry row's node plus the pencil's, German 2.0 on 360 × 780 through every mode and scope with no layout error (the caption and a day label wrapping, the month title on its two lines, the weekday row and two-digit numbers whole), the pinned chrome's rect at 2.0 across modes and the back state. **Corrected against the record**: with a day picked `buildAgendaDayListRows(groupByDay: false)` yields no day row, so the sheet builds the picked day's read row itself from the bucket's counts (as the old section header did); the month body's row sliver takes `groupGap` above it — the board's 18, which §3.2's `SliverPadding` did not name; the two fillers §3.2 copies carry no header hairline, the day list has one as asked; "fits on one row at 320" is Roboto's — in the test font the scope chips take two runs at 320 and 360 alike. Slice 7's device pass still owes: the look of the hairline under the title with the caption and chips between, and the title row's default 12 dp trailing inset where the two fillers pass `headerActionInset` |
| 1 | 2026-10-03 | **Done, uncommitted.** `FormMetrics`' five names and `category_name.dart`; `FormSwatchRow` (the Look sheet's `_PaletteRow` hoisted, the sheet on it with its height formula and ids cases unedited), `FormSectionLabel(trailing:)`, `FormPickerRow(handle:)`, `FormTitleRow(warning:)`, each with `form_rows_test` cases (+6); `AgendaPeriodNav` rewritten with four optional identifiers, a two-line measured title and the new `month:` (`agenda_period_nav_test`, 6); `AgendaMonthGrid` on `CalendarDaysOfWeek`, its row height delegating to the cell's (`agenda_month_grid_test`, 3); **D7 landed in `CalendarDayCell`** — the page's cells wrapped too — the number fitted on one line in its static chip; the strip's focus drop, overlay refusals, popup menu of `FormMenuItemRow`s with ids, confirmed delete, default-dot glyph and dot ids (`color_swatch_picker_test` +6, `SwatchRobot` extended); every id of §3.11 and the agenda card's `agendaCardDays(key)` on its button (+1 case); the two ARB keys, the two en spelling fixes and the `resetToDefault` reduction in three locales, `gen-l10n`, `untranslated.txt` `{}`. Gate: `dart analyze lib test` clean; `flutter test` **6754 passed / 7 skipped / 0 failed**. **Existing bodies changed**: the two tooltip strings of §4.2 item 13. **Corrected against the record**: the nav's `month:` parameter (§3.2), the five `resetToDefault` readers (§3.10), the palette helpers folding `#` (§3.11, §3.7), menu ids through `FormMenuItemRow(identifier:)`, the handle-plus-leading geometry (§3.7), the menu floor leftover (§3.8), `AgendaMonthGrid.rowHeightFor` was a copy of the cell's formula (now delegating), `_LookMetrics` survives with `iconRowPadding` alone (slice 6 names it or deletes it) |
| 0 | 2026-10-03 | **Done, uncommitted.** Eight robots in `test/widgets/support/` (`DayListRobot`, `CategoryEditorRobot`, `FastingScheduleRobot`, `FastingStyleRobot`, `RemovedHolidaysRobot`, `PaletteRobot`, `SwatchRobot`, `ColorPickerRobot`) and `layout_errors.dart`; the day-list suite (63), the agenda view's nine openers, the schedule (4, now opened through `show`, plus a new "what each control writes" group of 10), the palette (5), the strip (11), the picker (19), the Look sheet's five swatch cases and the category picker's two moved onto them with names, order and expected values unchanged — one vacuous assertion strengthened (`find.text('Show every day')` → the sheet closed). New suites: `category_editor_sheet_test` (20, on the real service over `NativeDatabase.memory()` with a failing interceptor), `fasting_style_sheet_test` (19), `removed_holidays_sheet_test` (7, on the real singleton, reads drained through `runAsync`); six clearance cases. The fixture's suppressed holiday and custom colour, pinned. Gate: `dart analyze lib test` clean; `flutter test` **6732 passed / 7 skipped / 0 failed** (6670 before; the Windows-only case passes on the Mac). **Pinned under "today:" names** for later slices to flip: the save-failure and restore messages drawn under their sheets; the name field keeping focus across the icon picker; the counter on from "0/40"; the typed title's 400 ms debounce and its dispose flush; the category editor overflowing at its header in German at 200 % on 360 × 780 (the filled Save leaves the title no width in the box font); the fasting preview's sample cell overflowing in the box font (D19 amended). **Corrected against the record**: the suppressed holiday's seed (§3.11), the holiday service's un-fakeable singleton (§3.6), flow 21's one-shot nature; the Dates-sheet-free reach of the 200-date cap (eleven thousand px down a lazy list — the rebuilt per-date rows have the same length, which is the user's own) |
