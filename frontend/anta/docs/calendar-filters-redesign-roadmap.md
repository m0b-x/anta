# Calendar Filters Redesign — Roadmap & Slice Prompts (2026-09-27)

**Status: IMPLEMENTED and REVIEWED 2026-09-27, uncommitted — the owner
reviews and commits.** Slices 1–6 are in the tree with the independent
review's fix round applied (see the
2026-09-27 addendum in `calendar-events-feature.md`); `qa flows calendar`
10/10 green on the Pixel 9 Pro emulator through the agent, `dart analyze
lib test` clean, `flutter test` 6055 passed / 7 skipped / 1 failed (the
known Windows-only `host_devices_test.dart` case), `untranslated.txt` `{}`,
`qa errors` clean. Decisions D22–D24 were appended during implementation.
The owner chose direction C of the canvas
**"Calendar Filters Mocks"** — https://claude.ai/artifact/YJwZnZns6WrFxg5HkGQuLP
— with the recommended option on every one of its seven decisions
("implement it, max effort", 2026-09-27, delegated). Line numbers in §5 are as
of `cf517cb` (a clean tree on 2026-09-27); re-grep before editing. Where a
board and this record disagree, **this record wins** — the places are listed
in §2 (D13, D14, D21) and §8.

## 0. How to run this

Load `anta-context`, `calendar-events`, `calendar-ui`, `ui-revamp`, `verify`,
`l10n` and, for slice 6, `qa-emulator`. Read this record whole, then §5
against the tree. Work the slices of §6 in order; never start a slice with
anything red. After **every** slice the gate:

- `dart analyze lib` clean (`dart analyze lib test` when tests changed);
- the **whole** `flutter test` green, one run at a time (the sqlite3.dll
  lock crash is transient — rerun);
- `flutter gen-l10n` run and `untranslated.txt` empty whenever an ARB changed;
- §4.1 (must not change) re-read against `git diff`.

Slice 6 adds the device pass on the running Pixel 9 Pro emulator through the
harness, never `adb` by hand: after any `lib` change
`./tool/qa/qa run --fresh --seed tool/qa/fixtures/calendar.json`
(`tool\qa\qa.cmd` on Windows), then `./tool/qa/qa flows calendar --via agent`
(the nine saved flows plus the new `09_filters.txt`, green before anything
else is looked at), then the matrix
`./tool/qa/qa set theme=dark locale=de text-scale=2.0` with every screen of
§3 shot beside its board, and `./tool/qa/qa errors` clean. Then the
independent review (§6, slice 6) by a fresh subagent briefed with this record
and the diff, and the docs of slice 6. **Do not commit** — the owner reviews
and commits.

## 1. Why

The Filters sheet (`lib/widgets/calendar_filter_sheet.dart`, 641 lines) is
the one calendar surface the owner still called "clouded": on the QA seed it
is **38 tappable controls in one scroll** — a bookmark and Reset in the
header, a Clear button and ten checkmarked colour-avatar chips for the
categories, an "Any" chip plus five priority chips, two `SegmentedButton`s
(Repeat, Time of day), seven "Only show" `FilterChip`s, three "Show" layer
chips, a `SwitchListTile` with a helper sentence, and a Cancel / Apply bar.
That is **four control styles** (checkmark chips, segmented buttons, filter
chips, a switch) for **three mental models** that sit in one list with no
seam between them: seven AND-ed *narrowing* toggles, three *on-by-default*
layers, and one *widening* switch that needed a sentence to explain itself.
Saving a filter is a bookmark icon in this sheet; using one is a second sheet
(`filter_preset_sheet.dart`, 658 lines) behind a second app-bar button, so the
sheet can never say which saved filter is on. Both sheets still wear the
chrome the 2026-09-25 editor redesign retired — the stock 48 dp drag band on
the plain surface, a centred-weight `titleMedium` header, a bottom action
bar — and neither uses a single primitive of `form_rows.dart`; neither is in
`test/widgets/sheet_bottom_clearance_test.dart`.

The event editor (2026-09-25) and the detail sheet (2026-09-26) set the
language every calendar surface now speaks — grouped rows on a layered
ground, a 22 dp handle strip, a 48 dp header with one leading icon, a
left-aligned title and one trailing text action, no bottom bar. The owner's
words: "It is so much clouded with many things, I believe we need that sleek
design that we used in the events." The canvas's row 0 holds the device shots
of both sheets, light and dark, next to the detail sheet they must match.

## 2. Decisions (owner, delegated 2026-09-27 — the recommended option stands)

| # | Decision | Reason · rejected alternatives | Who |
| --- | --- | --- | --- |
| D1 | **Direction C — two-level summary.** One rule: a *set* (Categories, Priority, Only show) is a picker row that reads its value back and opens a check-list sub-sheet; a *three-way choice* (Repeat, Time of day) is a menu row; a *boolean* (the three layers, the day panel) is a switch row. Twelve rows, 731 dp on a 390-wide phone: the top level never scrolls. | The complaint was readability, not tap count; every row reads its value back, the header lands mid-screen within thumb reach, the month row stays visible above the sheet. *Rejected:* A (every boolean a switch row — 1,045 dp, a third below the fold on every open, the same eighteen things in a nicer coat); B (labelled chip rows — sixteen chips are a wall again, a filled chip says "on" less clearly than a switch); a fourth "lenses first" direction (the preset list as the top level, the axes one level down — declutters most, but a user with no presets gets a nearly empty sheet and every ad-hoc filter costs a tap more; a different product, not a different sheet). | owner, delegated 2026-09-27 (recommended option stands) |
| D2 | **Apply as the header's text action; the draft is kept.** `FormHeaderTextButton(apply)` is the one trailing action; ✕, back, the system back gesture, the barrier and drag-to-dismiss pop `null`; `CalendarFilterSheet.show` keeps returning `CalendarGridFilters?` and the page's `_applyFilters` stays the one funnel. One repaint per visit. | *Rejected:* live apply with ✕ only — every tap would repaint 42 cells and the panel behind a sheet that hides them, with no cancel; live apply plus an Undo snackbar — a third surface to save two taps. | owner, delegated 2026-09-27 (recommended option stands) |
| D3 | **Reset is an action row at the bottom** — `FormActionRow(restart_alt_rounded, "Reset filters")`, the last group, 38 % while the draft is empty. It calls `cleared()` (keeps `panelShowsAll`) and does not close the sheet. | The header has one trailing slot and Apply owns it; in C the row is above the fold. *Rejected:* Reset in the header (only possible with live apply); dropping it in favour of the sub-sheet's "No filter" and the chip strip's ✕ (loses the in-sheet reset). | owner, delegated 2026-09-27 (recommended option stands) |
| D4 | **Presets get a row on top of the sheet and keep their app-bar button.** An unlabelled first group holds one two-target row `Saved filter … None ›` whose trailing 48 dp button is the bookmark that saves the draft (38 % while the draft is empty or already saved); tapping the row opens the Saved filters sub-sheet with the draft; the app-bar bookmark keeps opening the same sub-sheet with the applied filters, one tap. `FilterPresetSheet` is restyled in the language (D14). | The sheet finally says which lens is on; the one-tap lens switch survives. *Rejected:* folding presets completely and dropping the bar button (switching a lens goes from 2 taps to 4); two separate sheets as today, only restyled (the header has no slot for the old save icon anyway). | owner, delegated 2026-09-27 (recommended option stands) |
| D5 | **Priority is a check-list sub-sheet** of five rows with the priority glyphs (`EventPriorities.iconFor`), highest first; the row reads `Any` while the set is empty, else the names (D16). Multi-select is kept. | Same shape as Categories and Only show — one sub-sheet class serves both (D15). *Rejected:* a six-chip labelled row (one tap, two lines); a menu with check items (`MenuAnchor` has no semantics on iOS and closes per pick); a "minimum priority" menu (Any / High and up / …) — simpler, encodes to the same set, but drops arbitrary combinations; deferred (§8) for the owner. | owner, delegated 2026-09-27 (recommended option stands) |
| D6 | **Two groups replace three vocabularies: EVENTS and ALSO SHOW.** EVENTS holds what narrows (Categories, Priority, Repeat, Time of day, Only show). ALSO SHOW holds what is drawn in addition — the three layers and **"All events in the day panel"**, which is `panelShowsAll` with its key and polarity unchanged (off by default) and its helper sentence gone. | "Also show all events in the day panel" reads without a sentence; the seven traits move behind one row so their "Only show" label stops competing with "Show". *Rejected:* three groups EVENTS / LAYERS / DAY PANEL with an inverted "Also filter the day panel" (clearer scope, one more label and 38 dp, a polarity flip in a persisted field's UI); today's words in rows. | owner, delegated 2026-09-27 (recommended option stands) |
| D7 | **Categories are always one picker row** (`Categories … All ›`); chips never appear. The sub-sheet is the shared `CategoryPickerSheet` (D13), which gains a search row past `AppConstants.listSearchThreshold` (12). | *Rejected:* chips up to 12 as today (a five-line wall on the QA seed). | owner, delegated 2026-09-27 (recommended option stands) |
| D8 | **Fasting, when no tradition is configured, is shown at 38 % with its stored value** (`FormSwitchRow(onChanged: null)`), never omitted. | The language's "disabled, never hidden"; a row that appears between two openings moves everything under it. *Rejected:* omitting the chip as today. | owner, delegated 2026-09-27 (recommended option stands) |
| D9 | **Sheet shape: the sub-sheet shape, content-tall, clamped at `FormMetrics.sheetHeightFactor`** (`ConstrainedBox(maxHeight: height × 0.92)` → `Column(min)` → `FormSheetHandle` · `FormSheetHeader` · `Flexible(SingleChildScrollView)`), `showDragHandle: false`, `backgroundColor: pageGround`, top radius `FormMetrics.sheetRadius`, `useSafeArea: true`, the route's own drag. **No discard guard**: the sheet holds no typed text, and today's Cancel drops the draft silently too. | Every sub-sheet of the language is this shape (detail sheet E2); the fixed-0.92 form shape exists for the editor's docked markdown bar and its guard, neither of which this sheet has. | lead, 2026-09-27 |
| D10 | **Every sub-sheet confirms with a `FormHeaderTextButton` Done and returns its draft; ✕, drag, back and the barrier return `null` and change nothing.** The one exception is a pick-on-tap list (`CategoryPickerSheet.pickSingle`, the Saved filters list), which pops on the tap and has an empty trailing slot. | Editor D18, detail E3. | lead, 2026-09-27 |
| D11 | **Value lists carry their values' own icons.** The Priority rows use `EventPriorities.iconFor`, the Only show rows the facet icons of `CalendarFilterSummary` (the same glyphs the chip strip shows), the Categories rows the `EventAvatar` of each category. On the top level a row's glyph names the field (editor D12): `bookmark_border_rounded`, `label_outlined`, `flag_outlined`, `repeat_rounded`, `schedule_outlined`, `tune_rounded`, `celebration_rounded`, `no_food_rounded`, `payments_outlined`, `view_day_outlined`, `restart_alt_rounded`. | A value list is the priority menu's grammar, not a field's. | lead, 2026-09-27 |
| D12 | **`FormMenuRow` moves from `MenuAnchor` to a popup route** (`showMenu` with the header menus' `_ChoiceItem` anatomy: `menuSurface`, `FormMetrics.menuRadius`, `menuPadding`, rows `menuRowHeight` 44 with a `menuIconSize` 20 glyph in `onSurfaceVariant`, the label at `labelSize`, a `check_rounded` 20 in `primary` on the current item, each item a `menuItemRadio` node with its checked state; width `menuWidth`, right edge aligned with the group's, below the row when there is room, else above; focus dropped before opening). The editor's Priority and Day rail menus ride on the same fix; Repeat and Time of day are the third and fourth. | The `calendar-ui` skill records that `MenuAnchor` items expose no semantics nodes on iOS and says to fix it before a third menu; the header record's D7 already chose `PopupMenuButton` for that reason. *Rejected:* a private `showMenu` helper inside the filter sheet (a second copy of the menu anatomy). | lead, 2026-09-27 |
| D13 | **`CategoryPickerSheet` migrates to the language in place, both modes**, contracts untouched (`pickSingle(selectedId:) → String?`, `pickMulti(selected:) → Set<String>?`, an empty set never collapsed to `null`, `visiblePlus(initialSelection)` rows, `rankCategories` search, never autofocused). Multi mode: header ✕ · `calendarCategories` · Done; the bulk actions are **two action rows** — `Select all` (`done_all_rounded`) and `Select none` (`remove_done_rounded`), each 38 % where it would be a no-op, acting on the rows currently listed; the footer Apply goes. Single mode: ✕ · `eventType` · an empty trailing slot, pops on tap. Both: a `FormSearchRow` as the first row past the threshold or while a query is live, `Create category` (`add_rounded`) as the last action row of the group, and the no-match state as the single action row `createCategoryNamed(typed)`. Height content-tall, clamped at 0.92 (was a fixed 0.85). | The adoption rule: a sheet moves to the primitives when a change opens it and touches its chrome; this change opens it from the Categories row. A filter-only copy would duplicate the search, bulk, archived-row and create logic. **Deviation from the board**, which drew one flipping Select all / Select none row: a label that flips under the finger is exactly what the language forbids, and the two buttons disabled-where-no-op are what today's tests assert. | lead, 2026-09-27 |
| D14 | **`FilterPresetSheet` migrates in place**; `show(context, current:) → CalendarGridFilters?` unchanged. Header ✕ · `filterPresetsTitle` · empty. Group 1: an exclusive check row **"No filter"** (checked while `current.isEmpty`; tap pops `current.cleared()`) — it replaces the header's "Show everything". Group 2: one two-line exclusive check row per preset (name over `describe()`, checked while `preset.filters == current`, tap pops `preset.filters`) with a trailing ⋮ (Rename · Update to current filter · Delete, the app's menu anatomy), then the action row **Save the current filter** (38 % while `current.isEmpty` or already saved). A `FormSearchRow` leads group 2 past `AppConstants.listSearchThreshold` presets or while a query is live; no hits show `filterPresetNoMatches` as a `FormCaption` under the group. **The empty-state paragraph goes** (`filterPresetEmpty` retired): "No filter ✓" plus a dimmed save row already say what to do. | **Deviation from the board and the canvas note**, which retitled `filterPresetEmpty`: a paragraph under an empty list is the hint text the language forbids. | lead, 2026-09-27 |
| D15 | **One `FilterCheckListSheet`** (`lib/widgets/filter_check_list_sheet.dart`) serves Priority and Only show: `show(context, {title, items: List<FilterCheckItem(id, icon, label, identifier)>, selected}) → Set<String>?`, content-tall, ✕ · title · Done, one group of `FormCheckRow`s, no section label. | Two files for one shape would drift. | lead, 2026-09-27 |
| D16 | **The read-back rule for every set** (Categories, Priority, Only show): nothing selected reads the row's own word (`All` / `Any` / `Everything`); one or two selections read their names joined by ", "; more read the first two plus `categoriesMore(rest)` ("+N more") — the `CategoryFilterTile.namedLimit` rule, hoisted into `CalendarFilterSummary.namesReadBack(List<String> names, AppLocalizations)` so the tile and the rows cannot disagree. Categories with every category hidden read `calendarFilterNoCategories`. The value still wraps under the label and clamps at two lines (editor D10) — at 200 % German that is the only time it wraps. | A value that ellipsizes hides the count; "+N more" never does. The chip strip's `_categoryLabel` ("Categories (N)") is a different surface and stays. | lead, 2026-09-27 |
| D17 | **`_decodePriorities` becomes tolerant**: it accepts a JSON array of integers (or numeric strings) as well as today's comma-separated string; every other shape still decodes to "every priority". The encoder is untouched. | The QA fixture's "Top priority" preset stores `{"priorities":[1,2]}` and today decodes to "Shows everything"; a decoder that accepts more never breaks a stored blob. | lead, 2026-09-27 |
| D18 | **Ids for every target** (§3.9): `filter-…` on the sheet, `filter-list-…` on the check-list sub-sheet, `category-pick-…` on the shared picker, `filter-preset-…` on the presets, and the two app-bar buttons gain `calendar-filter-open` / `calendar-saved-filters-open` (tooltips, icons, position and badge unchanged). | The flow of slice 6 targets rows by id; "All" is not a unique label. | lead, 2026-09-27 |
| D19 | **Copy**: the seven trait labels stay except `calendarFilterHideEnded` retitled "Not ended" so every row reads as "Only show … X"; `calendarFilterPanelShowsAll` retitled "All events in the day panel" (same key, same polarity); new keys of §3.8. | §3.8. | lead, 2026-09-27 |
| D20 | **Bottom clearance** in the scroll view's padding (`max(viewInsets.bottom, viewPadding.bottom)`), the header the first `Column` child; every new or migrated sheet (the Filters sheet, the check-list sheet, the picker in both modes, the presets sheet) joins `test/widgets/sheet_bottom_clearance_test.dart`. | The rule that has shipped four defects. | lead, 2026-09-27 |
| D21 | **The saved-filter row's trailing glyph** is `bookmark_add_outlined` while the draft can be saved and `bookmark_added_rounded` once it matches a preset (today's icons); the row's own glyph is `bookmark_border_rounded`. | **Deviation from the board**, which drew a filled bookmark for the matched state; the app already owns the two icons. | lead, 2026-09-27 |
| D22 | **An answer that ticks every listed row empties the denylist outright, archived denials included** (`_pickCategories`); any other answer is inverted over the offered set as §3.2.2 says. Supersedes the plain inverse for that one answer and carries §4.1's "`_selectAll` empties the denylist outright" into the picker era. | The picker never lists a *denied* archived category — a hidden one reaches it only inside a selection, and a denied one is not selected — so the plain inverse could never clear such a denial: the Categories row would keep reading a count with nothing left in the picker to un-tick, and slice 2's "Select all in the picker empties archived denials" could not hold. The old sheet's header `_selectAll` did exactly this; the rule now lives where the sub-sheet's Select all arrives. Un-ticking one row keeps an archived denial denied (a test pins both). | implementer, 2026-09-27 |
| D24 | **A `FormMenuRow` menu is at least `menuWidth` wide and grows to `FormMetrics.menuMaxWidth` (the header menus' 280 cap) when a label needs it**, its right edge staying on the group's. Amends D12's "width `menuWidth`". | The device pass at 200 % German showed "Wiederkehrend" broken mid-word ("Wiederkehr / end") in a 220 menu; the header menus already take a floor and a cap for the same reason ("Ereignisse exportieren (.ics)"). At scale 1 nothing changes: the content is narrower than the floor. | implementer, 2026-09-27 (device pass) |
| D23 | **Four small additions the §3.7 sketches and §5's "nothing to add" left out**: `FormSearchRow` takes a required `clearTooltip` (`form_rows.dart` carries no localizations — every label there is passed in); `FormCheckRow` takes an optional `trailingButton` (the preset rows of §3.6 need the ⋮ as a second target, the check then shrinking to its 20 dp glyph before the 48 dp button, as the board draws); `FormMetrics.groupCaptionPadding` names the inset of a caption under a whole group — the no-match lines of §3.5 and §3.6, the picker's *under* the group so the group holds only the create row and "No categories match" keeps its place; `FormMenuItemRow.color` for the destructive Delete item. The popup anchor math is one shared `formMenuPosition` / `formMenuHeight` in `form_menu_item.dart`, read by `FormMenuRow` and the preset ⋮. | Each is the language's own rule (labels passed in, a number named first, one copy of an anatomy) meeting a case the sketch did not draw. | implementer, 2026-09-27 |

## 3. The spec

### 3.1 Geometry and tokens

Every number is an existing `FormMetrics` / `RowMetrics` constant; nothing
new is needed except the two primitives' own names (§3.7).

- **Sheet (all five surfaces).** `showModalBottomSheet(isScrollControlled:
  true, useSafeArea: true, showDragHandle: false, backgroundColor:
  colorScheme.pageGround, shape: RoundedRectangleBorder(top radius
  FormMetrics.sheetRadius))` → `ConstrainedBox(maxHeight:
  MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor)` →
  `Column(mainAxisSize: min)` of `FormSheetHandle`, `FormSheetHeader`,
  `Flexible(SingleChildScrollView(controller:, padding: EdgeInsets.fromLTRB(
  RowMetrics.groupInset, FormMetrics.bodyTop, RowMetrics.groupInset,
  FormMetrics.bodyBottom + clearance)))`. The header's hairline is a
  `ValueNotifier<bool>` fed by the scroll controller, never `setState`.
- **Header.** `FormSheetHeader(leadingIcon: Icons.close_rounded,
  leadingTooltip: l10n.cancel, title:, trailing:, trailingInset:
  FormMetrics.headerActionInset)`; the trailing is a
  `FormHeaderTextButton` or `const SizedBox.shrink()`.
- **Groups.** `FormRowGroup` (`rowGroup`, radius `RowMetrics.groupRadius`,
  hairlines `rowDivider` from each row's `dividerIndent`, `groupGap` below;
  `trailingGap: false` on the last group). `FormSectionLabel` for EVENTS and
  ALSO SHOW; none above the first group, the actions group, or inside a
  sub-sheet.
- **Rows.** `FormPickerRow`, `FormSwitchRow`, `FormActionRow`, `FormMenuRow`
  (D12), and the new `FormCheckRow` / `FormSearchRow` (§3.7). Text roles,
  glyphs, chevrons, the disabled opacity: the `calendar-ui` table.
- **Avatars** in the Categories rows: `EventAvatar(icon:
  CalendarIcons.forKey(c.iconKey) ?? Icons.event_rounded, color: c.color)`.
- **Heights on a 390 × 844 phone at text scale 1** (measured on the boards,
  hairlines included): the Filters sheet 731 dp against the 776 dp clamp;
  the Priority sub-sheet 342; Only show 438; Saved filters with three
  presets 402; Categories with eleven rows ≈ 830, clamped and scrolling.

### 3.2 The Filters sheet (`CalendarFilterSheet`), top to bottom

Header: ✕ (`filter-close`) · `calendarFiltersTitle` "Filters" ·
`FormHeaderTextButton(label: l10n.apply, identifier: filter-apply)` —
always enabled; a no-op Apply pops the unchanged draft. Body scroll view
`identifier: filter-sheet`.

**Group 1** (no label):

1. **Saved filter** — a two-target `FormPickerRow(glyph:
   Icons.bookmark_border_rounded, label: calendarFilterSavedFilter, value:
   _savedName ?? calendarFilterSavedNone, identifier: filter-saved-filter,
   onTap: _openPresets, trailingButton: FormTrailingButton(icon: _savedName
   == null ? Icons.bookmark_add_outlined : Icons.bookmark_added_rounded,
   tooltip: _savedName == null ? filterPresetSave :
   filterPresetSaved(_savedName), onPressed: _draft.isEmpty || _savedName !=
   null ? null : _saveAsPreset, identifier: filter-save))`. `_savedName` is
   `FilterPresetService.matching(_draft)?.name`, re-resolved on every edit
   as today. `_openPresets` = `FilterPresetSheet.show(context, current:
   _draft)`; a non-null result replaces the draft through `_update` (so
   "No filter" resets the draft and a preset loads into it); `null` changes
   nothing. Saving keeps today's `_saveAsPreset` (name dialog pre-filled with
   `CalendarFilterSummary.suggestName`, duplicate warning, the 50-cap
   snackbar, `filterPresetSaved` snackbar).

**EVENTS** (`calendarFilterSectionEvents`):

2. **Categories** — `FormPickerRow(glyph: Icons.label_outlined, label:
   calendarCategories, value:, identifier: filter-categories)`. Value:
   `_hidden.isEmpty` → `calendarFilterCategoriesAll` "All"; else the shown
   categories (`visiblePlus(_hidden)` minus `_hidden`, display order) through
   `namesReadBack`; none shown → `calendarFilterNoCategories`. Tap →
   today's `_pickCategories` (`CategoryPickerSheet.pickMulti` over
   `visiblePlus(_hidden)`, the denylist rebuilt as the inverse of the answer,
   `null` ignored) behind `_subRouteOpen`.
3. **Priority** — `FormPickerRow(glyph: Icons.flag_outlined, label:
   upcomingPriority, value:, identifier: filter-priority)`. Value: empty →
   `upcomingPriorityAny` "Any"; else `EventPriorities.labelOf` of the set,
   ascending (highest first), through `namesReadBack`. Tap →
   `FilterCheckListSheet.show(title: upcomingPriority, items: 1…5 with
   EventPriorities.iconFor / labelOf, selected: the set as strings)`; a
   non-null answer becomes `priorities`.
4. **Repeat** — `FormMenuRow<AgendaEventType>(glyph: Icons.repeat_rounded,
   label: calendarFilterRepeat, value: CalendarFilterSummary.eventTypeLabel,
   selected: eventType, items: [all, recurring, oneTime] each with
   CalendarFilterSummary.eventTypeIcon and eventTypeLabel, menuWidth: 220,
   identifier: filter-repeat)`; items `filter-repeat-all` /
   `filter-repeat-recurring` / `filter-repeat-one-time`.
5. **Time of day** — `FormMenuRow<CalendarEventTiming>(glyph:
   Icons.schedule_outlined, label: calendarFilterTiming, value: timingLabel,
   items: CalendarEventTiming.values with timingIcon / timingLabel,
   menuWidth: 220, identifier: filter-time)`; items `filter-time-all` /
   `filter-time-timed` / `filter-time-all-day`.
6. **Only show** — `FormPickerRow(glyph: Icons.tune_rounded, label:
   calendarFilterOnlyShow, value:, identifier: filter-only-show)`. Value: no
   trait set → `calendarFilterOnlyShowAny` "Everything"; else the set
   traits' labels in the sheet's order through `namesReadBack`. Tap →
   `FilterCheckListSheet.show(title: calendarFilterOnlyShow, items: the
   seven traits of §3.4, selected: the true flags)`; a non-null answer
   writes the seven booleans.

**ALSO SHOW** (`calendarFilterSectionAlsoShow`):

7. **Holidays** — `FormSwitchRow(glyph: CalendarFilterSummary.holidayIcon,
   label: upcomingShowHolidays, value: showHolidays, identifier:
   filter-holidays)`.
8. **Fasting** — `FormSwitchRow(glyph: fastingIcon, label:
   upcomingShowFasting, value: showFasting, onChanged:
   FastingCalendar.isEnabled ? … : null, identifier: filter-fasting)` — the
   disabled row draws at 38 % with the stored value (D8).
9. **Money** — `FormSwitchRow(glyph: moneyIcon, label:
   calendarFilterMoneyLayer, value: showMoney, identifier: filter-money)`.
10. **All events in the day panel** — `FormSwitchRow(glyph:
    Icons.view_day_outlined, label: calendarFilterPanelShowsAll, value:
    panelShowsAll, identifier: filter-panel-all)`.

**Actions group** (no label, `trailingGap: false`):

11. **Reset filters** — `FormActionRow(glyph: Icons.restart_alt_rounded,
    label: calendarFilterReset, onTap: _draft.isEmpty ? null : _reset,
    identifier: filter-reset)`; `_reset` = `_update(_draft.cleared())`, the
    sheet stays open.

**States drawn on the canvas:** default (nothing set: Save and Reset at
38 %, every value at its word, the badge absent); active (Categories "Gym,
Strength", Priority "Highest, High", Repeat "Recurring", Only show
"Tracked, Missed", Holidays off, Fasting at 38 %, Money on, the panel switch
on, Reset enabled, the app-bar filter button selected with the badge); the
Saved filters board opened while the draft equals "Top priority" (the row
reads the name, its bookmark is `bookmark_added_rounded` at 38 %).

### 3.3 The Priority sub-sheet

`FilterCheckListSheet.show(context, title: upcomingPriority, items: [for p
in 1…5: FilterCheckItem(id: '$p', icon: EventPriorities.iconFor(p), label:
EventPriorities.labelOf(p), identifier: filter-list-priority-$p)],
selected:)`. Header ✕ (`filter-list-close`) · "Priority" · Done
(`filter-list-done`). One group, five `FormCheckRow(glyph:, label:,
checked:)`, no Select all. Done returns the checked ids (an empty set is a
real answer: "Any"); ✕, drag, back, barrier return `null`.

### 3.4 The Only show sub-sheet

The same sheet with title `calendarFilterOnlyShow` and, in this order:

| id | icon (`CalendarFilterSummary`) | label key | field |
| --- | --- | --- | --- |
| `tracked` | `trackedIcon` | `calendarFilterTracked` "Tracked" | `trackedOnly` |
| `missed` | `missedIcon` | `eventPresenceMissed` "Missed" | `missedOnly` |
| `linked-note` | `linkedNoteIcon` | `eventLinkedNote` "Linked note" | `linkedNotesOnly` |
| `money` | `moneyIcon` | `calendarFilterWithMoney` "With money" | `moneyOnly` |
| `description` | `descriptionIcon` | `calendarFilterWithDescription` "With description" | `withDescriptionOnly` |
| `counted` | `countedIcon` | `calendarFilterCounted` "Counted" | `countedOnly` |
| `not-ended` | `hideEndedIcon` | `calendarFilterHideEnded` "Not ended" (D19) | `hideEnded` |

Row ids `filter-list-<id>`. The order is today's `_buildTraits` order; the
chip strip (`facetsOf`) keeps its own order and words — one facet per flag,
unchanged.

### 3.5 The Categories sub-sheet (`CategoryPickerSheet`, migrated — D13)

Header ✕ (`category-pick-close`) · `calendarCategories` "Categories" (multi)
or `eventType` "Type" (single) · Done (`category-pick-done`, multi only; it
pops `{..._selected}`, empty included). One group, top to bottom:

1. `FormSearchRow(hint: searchCategories, identifier: category-pick-search)`
   — only while `_isFiltering || categories.length >
   AppConstants.listSearchThreshold` (today's `showSearch`); the field is
   never autofocused; a live query keeps the row (the list must never be
   filtered with no field left to clear it).
2. Multi only: `FormActionRow(done_all_rounded, categoriesSelectAll,
   onTap: rows.every(selected) ? null : _setAll(rows, true), identifier:
   category-pick-select-all)` and `FormActionRow(remove_done_rounded,
   categoriesSelectNone, onTap: rows.every(!selected) ? null : _setAll(rows,
   false), identifier: category-pick-select-none)` — over the rows
   **currently listed** (the filtered set while a query is live), as today.
3. One `FormCheckRow(leading: EventAvatar, label: labelOf(c), caption:
   c.isHidden ? categoryHidden : null, checked:, exclusive: single mode,
   identifier: category-pick-<id>)` per row of `rankCategories(_query,
   visiblePlus(initialSelection))` (or the unranked list without a query).
   Archived categories are listed only while the **opening** selection
   carries them and stay listed when un-ticked (today's invariant). Single
   mode pops the id on tap.
4. `FormActionRow(add_rounded, createCategory, onTap: _createCategory,
   identifier: category-pick-create)` — replaces the tonal ＋ in the old
   header; opens `CategoryEditorSheet` exactly as today and selects the new
   category.
5. No match: the group holds only `FormActionRow(add_rounded,
   createCategoryNamed(typed))` (today's empty state, as a row).

The old count line ("N categories") goes: the check marks show it, and the
Filters row reads it back after Done. `CategoryFilterTile` and
`_CategoryAvatarCluster` stay (the agenda sheet and the overview page render
them, §5); the Filters sheet no longer does.

### 3.6 The Saved filters sub-sheet (`FilterPresetSheet`, migrated — D14)

Header ✕ (`filter-preset-close`) · `filterPresetsTitle` "Saved filters" ·
empty trailing slot. Loading state: the groups render with no preset rows
until the service answers (no spinner in the language; the list fills in).

**Group 1:** `FormCheckRow(exclusive: true, label: filterPresetNone "No
filter", checked: current.isEmpty, identifier: filter-preset-none)` — tap
pops `current.cleared()` (never `CalendarGridFilters.none`: `panelShowsAll`
is a preference, exactly today's "Show everything" reasoning).

**Group 2:**

1. `FormSearchRow(hint: filterPresetSearchHint, identifier:
   filter-preset-search)` while `_presets.length >
   AppConstants.listSearchThreshold || _query.isNotEmpty`; matching is
   today's `_visible` (folded name **or** `describe()` through
   `normalizeForSearch`).
2. One two-line `FormCheckRow(exclusive: true, label: preset.name, caption:
   CalendarFilterSummary.describe(preset.filters), checked: preset.filters
   == current, identifier: filter-preset-<id>)` per visible preset, tap pops
   `preset.filters`; its trailing `FormTrailingButton(Icons.more_vert_rounded,
   filterPresetActions, identifier: filter-preset-options-<id>)` opens a
   popup menu (the header menus' anatomy) with `filterPresetRename`
   (`drive_file_rename_outline_rounded`, `filter-preset-rename`),
   `filterPresetUpdate` (`sync_rounded`, `filter-preset-update`, disabled
   while in use or `current.isEmpty`) and `delete` (`delete_outline_rounded`
   in `error`, `filter-preset-delete`, then today's `AppDialogs.confirm`).
   Rename, update and delete happen in place and never pop.
3. `FormActionRow(bookmark_add_outlined, filterPresetSaveCurrent, onTap:
   current.isEmpty || matching(current) != null ? null : _saveCurrent,
   identifier: filter-preset-save)` — hidden while a query is live as today
   is **not** kept: it is disabled instead (nothing moves under the finger).
   `_saveCurrent` is today's (name dialog, cap snackbar, the list refreshes,
   the sheet stays open).
4. No hits: `FormCaption(filterPresetNoMatches)` under the group.

`FilterPresetNameDialog` is unchanged (`AlertDialog`, `filterPresetName`,
`maxLength` 60, the soft `categoryNameExists` warning, Save disabled on an
empty name).

### 3.7 The two new primitives (`lib/widgets/form_rows.dart`)

**`FormCheckRow`** — the multi-select twin of `FormRadioRow`.

```dart
class FormCheckRow extends FormDividedRow {
  const FormCheckRow({
    super.key,
    this.leading,            // a 40 dp widget (EventAvatar); wins over glyph
    this.glyph,              // 22 dp primary, like every row glyph
    required this.label,
    this.caption,            // 13/400 onSurfaceVariant second line
    required this.checked,
    required this.onChanged, // null = 38 %, inert
    this.exclusive = false,  // true: radio semantics + the check glyph
    this.identifier,
  });
}
```

- Geometry: min height `FormMetrics.rowMinHeight`; with a caption
  `twoLineRowMinHeight` and `RowMetrics.twoLinePadding`; with a leading
  `titleRowMinHeight` (56). Left padding `RowMetrics.groupInset`, gap
  `FormMetrics.gap`; the trailing control sits in a 48 × 48 slot flush with
  the row's end (right padding 0), so the box centres 24 dp from the edge
  as a two-target row's button does. `dividerIndent`: 70
  (`dividerIndentTitle`) with a leading, 52 with a glyph, 16 otherwise.
- Control: `exclusive: false` → an M3 `Checkbox` (`materialTapTargetSize:
  padded`, `visualDensity: standard`, the theme's colours); `exclusive:
  true` → `check_rounded` at `trailingIconSize` in `primary` when checked,
  an empty box of that size otherwise, the label 15/500 when checked —
  `FormRadioRow`'s look, so a list can mix a leading avatar with the radio
  shape.
- Semantics: one `MergeSemantics` node over an `InkWell` that toggles the
  whole row; `checked` / `selected` state from the control; `exclusive` adds
  `inMutuallyExclusiveGroup`; `identifier` through `AutomationId`. Disabled
  rows have no tap and no ink.

**`FormSearchRow`** — a search field as the first row of a group.

```dart
class FormSearchRow extends FormDividedRow {
  const FormSearchRow({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.identifier,
  });
}
```

- Geometry: min height `rowMinHeight`; `search_rounded` at `glyphSize` in
  `primary` at `groupInset`; a collapsed `TextField` (`InputDecoration.
  collapsed`, 15/400 `onSurface`, hint 15/400 `onSurfaceVariant` — never
  `outline`, D15; `textInputAction: search`; `autofocus: false`, always);
  while the text is non-empty a trailing `FormTrailingButton(close_rounded,
  upcomingClearSearch)` as a sibling target that clears the controller and
  calls `onChanged('')`; `dividerIndent` 52.
- Semantics: the field is its own text-field node (the QA driver types into
  it by id); the clear button its own button node.
- It replaces `SettingsSearchField` only inside form groups; the settings
  pages and `CalendarCategoriesPage` keep theirs.

**`FormMenuRow`** (D12): same constructor, the body rebuilt on `showMenu`;
`FormMenuItem` gains `identifier` so each item is a `menuItemRadio` node with
an id. `form_rows_test.dart:118` ("a menu row passes its id to the row it
draws") stays; a new case asserts an item's id and checked state. The two
editor suites that find `MenuItemButton` —
`test/widgets/event_editor_redesign_test.dart:719–726` and
`test/widgets/event_editor_day_rail_test.dart:146` — switch their finders to
the popup item; their assertions stay.

**`FormTrailingButton`** gains an optional `identifier` (through
`AutomationId`, like every other primitive) — it has none today (`form_rows.
dart:377–405`: `icon`, `tooltip`, `onPressed`, `color`). The Saved filter
row's bookmark (`filter-save`) and each preset's ⋮ (`filter-preset-options-
<id>`) need it.

**`CalendarFilterSummary.namesReadBack(List<String> names, AppLocalizations
l10n)`** (D16): `names.length <= 2 ? names.join(', ') : '${names.take(2).
join(', ')} ${l10n.categoriesMore(names.length - 2)}'`; `CategoryFilterTile.
_subtitle` calls it.

### 3.8 Copy and l10n

Load the `l10n` skill; every key in `app_en.arb`, `app_de.arb`, `app_ro.arb`
together, then `flutter gen-l10n`, then `untranslated.txt` empty.

**New**

| Key | en | de | ro |
| --- | --- | --- | --- |
| `calendarFilterSavedFilter` | Saved filter | Gespeicherter Filter | Filtru salvat |
| `calendarFilterSavedNone` | None | Keiner | Niciunul |
| `calendarFilterSectionEvents` | Events | Ereignisse | Evenimente |
| `calendarFilterCategoriesAll` | All | Alle | Toate |
| `calendarFilterOnlyShowAny` | Everything | Alles | Tot |
| `calendarFilterSectionAlsoShow` | Also show | Außerdem anzeigen | Afișează și |
| `calendarFilterReset` | Reset filters | Filter zurücksetzen | Resetează filtrele |
| `filterPresetNone` | No filter | Kein Filter | Fără filtru |

**Retitled** (same key, same meaning; the chip strip inherits the new
"Not ended" through `facetsOf`)

| Key | was | en | de | ro |
| --- | --- | --- | --- | --- |
| `calendarFilterHideEnded` | Hide ended | Not ended | Nicht beendet | Neîncheiate |
| `calendarFilterPanelShowsAll` | Keep the day panel unfiltered | All events in the day panel | Alle Ereignisse im Tagesbereich | Toate evenimentele în panoul zilei |

**Reused as is**: `calendarFiltersTitle`, `apply`, `cancel`, `close`,
`calendarCategories` (row label and sub-sheet title), `eventType` (the single
picker's title), `upcomingPriority`, `upcomingPriorityAny`,
`eventPriorityHighest` … `eventPriorityLowest` (through `EventPriorities.
labelOf`), `calendarFilterRepeat`, `calendarFilterTiming`, `upcomingEventType
All/Recurring/OneTime`, `calendarFilterTimed`, `eventAllDay`,
`calendarFilterOnlyShow`, `calendarFilterTracked`, `eventPresenceMissed`,
`eventLinkedNote`, `calendarFilterWithMoney`, `calendarFilterWithDescription`,
`calendarFilterCounted`, `upcomingShowHolidays`, `upcomingShowFasting`,
`calendarFilterMoneyLayer`, `calendarFilterNoCategories`, `categoriesMore`,
`categoriesSelectAll`, `categoriesSelectNone`, `searchCategories`,
`categoryHidden`, `createCategory`, `createCategoryNamed`,
`upcomingClearSearch`, `filterPresetsTitle`, `filterPresetSave`,
`filterPresetSaved`, `filterPresetSaveCurrent`, `filterPresetSearchHint`,
`filterPresetNoMatches`, `filterPresetName`, `filterPresetRename`,
`filterPresetUpdate`, `filterPresetDelete`, `filterPresetDeleteConfirm`,
`filterPresetActions`, `filterPresetLimitReached`, `categoryNameExists`,
`delete`, `save`, `eventDescriptionDone` ("Done"), `filterCalendar`,
`calendarFilterShowsEverything` (`describe()`), `calendarFilterLayerHidden`
(the chip strip).

**Retired, each after `grep -rn <key> lib test tool`**:
`calendarFilterPanelShowsAllDesc` (the helper sentence),
`calendarFilterShowAll` (the presets header button — "No filter" replaces
it), `calendarSelectAll` and `calendarClearAll` (the old categories header —
the sub-sheet uses `categoriesSelectAll` / `categoriesSelectNone`),
`calendarEventCategories` (the old section label), `filterPresetEmpty`
(D14). `upcomingSectionShow` and `upcomingFiltersReset` **stay**: the agenda
sheet still reads them.

### 3.9 Semantics ids (`lib/constants/semantics_ids.dart`, after `calendarSettingsOpen`)

```
calendarFilterOpen = 'calendar-filter-open'          calendarSavedFiltersOpen = 'calendar-saved-filters-open'
filterSheet = 'filter-sheet'   filterClose = 'filter-close'   filterApply = 'filter-apply'
filterSavedFilter = 'filter-saved-filter'   filterSave = 'filter-save'
filterCategories = 'filter-categories'   filterPriority = 'filter-priority'
filterRepeat = 'filter-repeat'   filterRepeatAll / filterRepeatRecurring / filterRepeatOneTime
filterTime = 'filter-time'   filterTimeAll / filterTimeTimed / filterTimeAllDay
filterOnlyShow = 'filter-only-show'
filterHolidays / filterFasting / filterMoney / filterPanelAll = 'filter-panel-all'
filterReset = 'filter-reset'
filterListClose = 'filter-list-close'   filterListDone = 'filter-list-done'
static String filterListRow(String id) => 'filter-list-$id'   (priority-1…5, tracked, missed, linked-note, money, description, counted, not-ended)
categoryPickClose / categoryPickDone / categoryPickSearch / categoryPickSelectAll / categoryPickSelectNone / categoryPickCreate
static String categoryPickRow(String id) => 'category-pick-$id'
filterPresetClose / filterPresetNone / filterPresetSearch / filterPresetSave
static String filterPresetRow(String id) => 'filter-preset-$id'
static String filterPresetOptions(String id) => 'filter-preset-options-$id'
filterPresetRename / filterPresetUpdate / filterPresetDelete
```

Kebab-case, never renamed; the two app-bar ids go on the existing
`IconButton`s at `calendar_page.dart:1079` and `:1105` through `AutomationId`.

## 4. Behaviour

### 4.1 Must not change

Every item is current code; each one has a test or a past bug behind it.

- **The model.** `CalendarGridFilters` keeps every field with its default:
  `hiddenCategoryIds` `{}`, `priorities` `{}` (= every priority),
  `eventType` `all`, `timing` `all`, `trackedOnly`, `linkedNotesOnly`,
  `moneyOnly`, `withDescriptionOnly`, `countedOnly`, `missedOnly`,
  `hideEnded` all `false`, `showHolidays` / `showFasting` / `showMoney`
  `true`, `panelShowsAll` `false`; `isEmpty`, `activeCount` (categories
  count once, a layer only while off, `panelShowsAll` never), `allows`,
  `allowsOccurrence`, `cleared()` (keeps `panelShowsAll`), `encode` (only
  non-defaults, priorities as the comma string), `decode` tolerant; the
  settings key `SettingsKeys.calendarGridFilters`, `SettingsService.
  setCalendarGridFilters` deleting the key when empty, the restore on page
  load. `test/models/calendar_grid_filters_test.dart` passes unchanged and
  gains D17's case.
- **The funnel.** `CalendarFilterSheet.show(context, filters:) →
  Future<CalendarGridFilters?>`: the draft on Apply (with unmodifiable sets,
  as `_apply` builds it today), `null` on every other exit; `calendar_page.
  dart`'s `_openFilterSheet` / `_filterSheetBody` / `_applyFilters` /
  `_persistFilters` untouched; `ChangeCalendarFilters` the one dispatch.
- **The badge and the buttons.** `Badge.count(activeCount)`, `isSelected`,
  `filter_alt_rounded` / `filter_alt_outlined`, both tooltips, both
  `buildWhen`s and the press-time state reads, the order in the bar
  (saved filters, then filter), `SheetGuard` around both sheets.
- **The chip strip.** `CalendarFilterChips` and `CalendarFilterSummary.
  facetsOf` / `describe` / `suggestName` / `_categoryLabel`: one facet per
  axis, the same icons, the same words (only the retitled keys read
  differently), a chip's ✕ still goes through `_applyFilters`.
- **Presets.** `FilterPresetService` (`maxPresets` 50, `presets`, `isFull`,
  `matching` by value equality, `create`, `update`, `delete` soft, backup
  export/import), the Drift table, `CalendarFilterPreset`; `FilterPresetSheet.
  show(context, current:) → CalendarGridFilters?` and `_presetSheetBody`;
  in-use = value equality; rename / update / delete in place, never popping;
  the name dialog's rules; the sheet's bookmark and the presets' save row
  both refusing an empty filter and one already saved; the duplicate-name
  warning that never blocks.
- **The picker.** `CategoryPickerSheet.pickSingle` / `pickMulti` signatures
  and answers (an empty set is real, `null` is a dismissal), rows from
  `visiblePlus(initialSelection)`, archived rows kept while un-ticked, bulk
  actions over the listed rows, search through `rankCategories` never
  autofocused, `_createCategory` selecting what it creates; its four other
  callers (`event_editor_sheet.dart:1364`, `event_template_editor_sheet.
  dart:197`, `agenda_filters_sheet.dart:136`, `calendar_overview_page.dart:
  595`) and `test/widgets/category_picker_sheet_test.dart`'s assertions
  (finders may change, behaviour may not).
- **The denylist.** `_pickCategories` inverts the picker's answer;
  `_selectAll` empties the denylist outright (archived denials included);
  the old `_clearAll` union is retired with the chip header (§4.2) — the
  sub-sheet's Select none acts on listed rows, the picker's rule.
- **The double-tap guard** `_subRouteOpen` (one flag for the sub-sheets and
  the name dialog) and `test/widgets/calendar_sheet_double_tap_test.dart`.
- **Other surfaces.** `AgendaFiltersSheet` (its chips, its `SegmentedButton`s,
  its `CategoryFilterTile`, `upcomingSectionShow`, `upcomingFiltersReset`),
  `CalendarOverviewPage`'s allowlist tile, `CategoryFilterTile` and
  `_CategoryAvatarCluster`, `CalendarCategoriesPage`, `SettingsSearchField`.
- **Data.** Backup format (`FilterPresetService` export/import), soft
  deletes, CRDT fields, `is_hidden` (hiding a category archives it and never
  filters it — §2.3 of the feature doc).

### 4.2 Deliberately changes

| Today | After |
| --- | --- |
| Stock 48 dp drag band, default sheet surface, content-sized with a pinned Cancel / Apply bar | 22 dp handle strip, `pageGround`, radius 28, content-tall clamped at 0.92, Apply in the header, no bar (D2, D9) |
| Header: `titleMedium` "Filters" · bookmark `IconButton` · Reset `TextButton` | `FormSheetHeader`: ✕ · "Filters" · Apply; saving on the Saved filter row's bookmark; Reset an action row at the bottom (D3, D4) |
| Categories: label + Clear/Select all button, ten `FilterChip`s, a `CategoryFilterTile` past 12 | One picker row reading "All" / the names / "+N more"; the sub-sheet (D7, D13, D16) |
| Priority: "Any" `ChoiceChip` + five `FilterChip`s | A picker row and a check-list sub-sheet (D5, D15) |
| Repeat, Time of day: `SegmentedButton`s | `FormMenuRow`s on a popup route (D12) |
| Only show: seven `FilterChip`s | One picker row reading "Everything" / the traits and a check-list sub-sheet (D6, D15) |
| Show: three `FilterChip`s, Fasting absent while inert | ALSO SHOW: three switch rows, Fasting at 38 % while inert (D6, D8) |
| `SwitchListTile` "Keep the day panel unfiltered" + sentence | The fourth ALSO SHOW switch, "All events in the day panel", no sentence (D6, D19) |
| "Hide ended" | "Not ended" everywhere the key is read (D19) |
| `FilterPresetSheet`: 0.75 fixed, stock handle, "Show everything" header button, a search field whenever a preset exists, `ListTile`s with ⋮, an empty-state paragraph | The language, "No filter" row, search past 12, two-line check rows with ⋮, the save row disabled instead of hidden, no paragraph (D14) |
| `CategoryPickerSheet`: 0.85 fixed, stock handle, centred `titleLarge` + tonal ＋, `SettingsSearchField`, a count + two `TextButton`s, `ListTile` + `Checkbox`, a `FilledButton` Apply footer | The language: ✕ · title · Done, a search row, two bulk action rows, check rows with avatars, a Create category row (D13) |
| `_decodePriorities` accepts only the comma string | …and a JSON array (D17) — tolerant, never stricter |
| No ids on the filter surfaces or the two app-bar buttons | §3.9 (D18) |

## 5. Facts from the tree (as of `cf517cb`; re-grep before editing)

- `lib/widgets/calendar_filter_sheet.dart` (641 lines): class :32,
  `categoryChipsKey` :39 (**delete**, tests only), `show` :41–50
  (`showDragHandle: true`), `_subRouteOpen` :72, `_saveAsPreset` :114,
  `_reset` :158, `_selectAll` :192, `_clearAll` :197 (**delete** with the
  chip header), `_pickCategories` :215, `_apply` :240, `build` :250 (the
  header `Row` :268–304 with the `IconButton` :282 and Reset; the body
  :305–357; `SwitchListTile` :348 with `calendarFilterPanelShowsAllDesc`
  :351; `Divider` :362 and the Cancel / Apply `Row` :363–382 — **delete**),
  `_segmented` :388, `_buildPriorities` :416, `_traitChip` :446,
  `_buildTraits` :464, `_buildLayers` :526 (`FastingCalendar.isEnabled` :540),
  `_buildCategories` :559 (`listSearchThreshold` :589, the chip `Wrap`
  :596–620), `_SectionLabel` :623 — **all delete**; keep `_saveAsPreset`,
  `_reset`, `_selectAll`'s reasoning (as the picker's Select all), `_pickCategories`, `_apply`, `_update`, `_loadPresets`, `_report`.
- `lib/widgets/filter_preset_sheet.dart` (658 lines): class :22, `show`
  :29–43 (`heightFactor: 0.75`, `showDragHandle: true`), `_onQueryChanged`
  :89, `_visible` :97, `_otherNames` :112, `_saveCurrent` :123, `_rename`
  :149, `_updateToCurrent` :171, `_delete` :177, `build` :193 (the header
  `Row` with `calendarFilterShowAll` :248, the `TextField` with
  `filterPresetSearchHint` :270, the `ListView.builder`), `_SaveCurrentTile`
  :357 and `_PresetTile` :387 (**replace** with rows), `_PresetAction` :496
  (keep), `_EmptyState` :498 (**delete**), `FilterPresetNameDialog` :538 and
  `_NameDialog` :556–658 (keep; `maxLength: 60` :626, `categoryNameExists`
  :630).
- `lib/widgets/category_picker_sheet.dart` (549 lines): class :30,
  `pickSingle` :44, `pickMulti` :67, `_show` :78–97 (`showDragHandle: true`
  :87, `heightFactor: 0.85` :90), `_setAll` :137, `_createCategory` :162,
  `build` :180–330 (the title row with the tonal ＋ :222–243,
  `SettingsSearchField` :247, the count + bulk `TextButton`s :253–290, the
  `ListView.builder` :292–310, the `Divider` + `FilledButton` footer
  :312–323 — **replace**), `_buildEmptyState` :328, `CategoryFilterTile`
  :384 (keep; `namedLimit` :402 and `_subtitle` :439 call `namesReadBack`),
  `_CategoryAvatarCluster` :458 (keep), `_CategoryPickerRow` :510–549
  (`categoryHidden` :539, `Checkbox` :541 — **replace** with `FormCheckRow`).
- `lib/pages/calendar_page.dart` (2511 lines): `SheetGuard` :128,
  `_sheetGuard` :179, the restore `ChangeCalendarFilters` :729,
  `_applyFilters` :743, `_persistFilters` :748, the saved-filters
  `IconButton` :1079–1094 (`filterPresetsTitle` :1080, `bookmarks_outlined`
  :1081, `_openPresetSheet` :1090), the filter `Badge.count` :1102–1127
  (`filterCalendar` :1106, the icons :1110–1111, `_openFilterSheet` :1122),
  `CalendarFilterChips` :1210 (chip body → `_openFilterSheet` :1218),
  `_openFilterSheet` :1901, `_filterSheetBody` :1906–1916,
  `_openPresetSheet` :1922, `_presetSheetBody` :1927–1937. Only the two ids
  change here.
- `lib/models/calendar_grid_filters.dart` (420 lines): class :54, fields
  :58–115, constructor :117, `isEmpty` :140, `activeCount` :152, `allows`
  :177, `allowsOccurrence` :226, `cleared` :304, `decode` :341
  (`_decodePriorities(map['priorities'])` :359), `_decodePriorities`
  :388–400 (D17).
- `lib/utils/calendar_filter_summary.dart` (308 lines): `CalendarFilterFacet`
  :12, the icons :39–52, `eventTypeIcon` :54, `eventTypeLabel` :65,
  `timingIcon` :74, `timingLabel` :82, `facetsOf` :95, `describe` :261,
  `suggestName` :275, `_categoryLabel` :292–308; `namesReadBack` goes
  beside `describe`.
- `lib/widgets/form_rows.dart` (1148 lines): `FormRowGroup` :18,
  `FormSectionLabel` :67, `FormSheetHandle` :96, `FormSheetHeader` :124
  (`trailing` required, `trailingInset`, `scrolled`, `leadingIdentifier`),
  `FormHeaderTextButton` :223, `FormLabelValue` :258, `FormTrailingButton`
  :377–405 (nullable `onPressed`, no `identifier` yet — §3.7),
  `FormPickerRow` :406 (`trailingButton`, `caption`, `identifier`),
  `FormSwitchRow` :536, `FormActionRow` :634, `FormRadioRow` :692–763 (the
  model for `FormCheckRow`'s exclusive look), `FormChip` :764, `FormChipRow`
  :893, `FormCaption` :1014, `FormMenuItem` :1043, `FormMenuRow` :1051–1148
  (`return MenuAnchor(` :1080 — D12). Insert `FormCheckRow` after
  `FormRadioRow`, `FormSearchRow` after `FormCaption`.
- `lib/constants/form_metrics.dart` (97 lines): every constant §3.1 names
  exists (`sheetHeightFactor` :12, `headerActionInset` :26, `rowMinHeight`
  :36, `twoLineRowMinHeight` :37, `titleRowMinHeight` :38,
  `trailingIconSize` :50, `trailingButtonSize` :51, `dividerIndentTitle`
  :76, the menu constants :91–94, `disabledOpacity` :96). Nothing to add.
  `lib/constants/row_metrics.dart`: `groupInset` :13, `twoLinePadding` :50,
  `gap` :57. `lib/constants/app_theme.dart`: `menuWidth` :118,
  `menuItemHeight` :119, `menuIconSize` :120, `menuLabelSize` :121,
  `menuDividerHeight` :123, `menuMaxWidth` :130.
- `lib/widgets/calendar_header_menus.dart`: `CalendarViewMenu` :32,
  `_dropFocus` :304, `_ChoiceItem` :325 (the radio `PopupMenuItem` D12
  copies or shares — share it: move it to `form_rows.dart` or a small
  `form_menu_item.dart` and point the header menus at it).
- `lib/constants/semantics_ids.dart` (163 lines): the calendar ids :55–73
  (`calendarSettingsOpen` :73), the editor block from :80. Insert §3.9
  after :73.
- `lib/constants/app_constants.dart:101` `listSearchThreshold = 12`;
  `lib/constants/fasting_calendar.dart:170` `isEnabled`;
  `lib/constants/calendar_categories.dart` `visible` :121, `visiblePlus`
  :132, `iconFor` :156, `labelOf` :165; `lib/constants/settings_keys.dart:284`
  `calendarGridFilters`; `lib/services/settings_service.dart` :1863 / :1878;
  `lib/services/filter_preset_service.dart` `maxPresets` :32, `getInstance`
  :38, `presets` :75, `isFull` :77, `matching` :96, `create` :108, `update`
  :127, `delete` :132.
- `lib/widgets/agenda_filters_sheet.dart`: `pickMulti` :136,
  `CategoryFilterTile` :489, `listSearchThreshold` :488 — untouched.
  `lib/pages/calendar_overview_page.dart`: `pickMulti` :595,
  `CategoryFilterTile` :733 — untouched. `lib/widgets/calendar_filter_chips.
  dart`: class :18, `facetsOf` :43 — untouched.
- ARBs: the filter block starts at `app_en.arb:66` / `app_de.arb:21` /
  `app_ro.arb:18` (`calendarFiltersTitle`); `calendarCategories` en :489 /
  de :123 / ro :120; `categoriesSelectAll` / `categoriesSelectNone` en
  :618 / :622; `searchCategories` en :561; `categoryHidden` en :578;
  `categoriesMore` en :611; `createCategory` en :497; `upcomingPriorityAny`
  en :5233; `upcomingEventTypeAll` en :5273; `upcomingClearSearch` en :5067.
- Tests: `test/widgets/category_filter_sheets_test.dart` group 'calendar
  filter sheet' :80–220 (five cases on chips, the tile, the denylist
  inverse, Select all, clearing) — **rewrite** for the row and the
  sub-sheet; its 'agenda filters sheet' group :222–500 exercises the picker
  through the agenda sheet (Select all / Select none by text, `Checkbox`
  finders) — finders adapt, assertions stay. `test/widgets/
  category_picker_sheet_test.dart` (:65–300, nine cases plus the
  `CategoryFilterTile` group :253) — finders adapt. `test/widgets/
  filter_preset_sheet_test.dart` (:75–300) — the search cases need thirteen
  seeded presets or a query; "Show everything" cases become "No filter"
  cases; the empty-state case asserts no paragraph and a dimmed save row.
  `test/widgets/calendar_header_test.dart:251–262` opens the sheet by the
  outlined icon and asserts `find.byType(CalendarFilterSheet)` — stays.
  `test/widgets/calendar_sheet_double_tap_test.dart:279–331` finds both
  sheets by type — stays. `test/widgets/form_rows_test.dart` groups
  'identifiers' :21, 'geometry' :153, 'shared chrome and read rows' :202 —
  extend. `test/widgets/sheet_bottom_clearance_test.dart` (`openFrom`,
  `sizeSurfaceWithNavBar`, `scrollBottomPadding`; the detail-sheet case
  :180–207 is the shape) — gains the four sheets. `test/models/
  calendar_grid_filters_test.dart` 'persistence' :277–330 — gains D17.
  `test/widgets/agenda_filters_sheet_test.dart` — untouched, must stay green.
- QA: `tool/qa/fixtures/calendar.json:382–391` the "Top priority" preset
  (`{"priorities":[1,2]}`); `tool/qa/flows/calendar/` holds `00_open` …
  `08_header` (`08_header.txt` is the shape: `tap id:`, `wait id: [--gone]`,
  `expect id:… "text"`, `shot`, `key back`, `errors`).
- Docs: `docs/calendar-events-feature.md` — the grid-filters addendum :3759
  (its "Sheet" bullet :3916) and the saved-filters addendum :3973 (the save
  `IconButton` :4079, the "Show everything" reasoning :4104–4117);
  `COPILOT_CONTEXT.md:80` (the grid-filters paragraph: "UI is
  `CalendarFilterSheet` (draft-and-Apply; categories stay the second
  section)"); `.claude/skills/calendar-events/SKILL.md:85–86` (the picker
  and the two filter sheets' `CategoryFilterTile` rule); `.claude/skills/
  calendar-ui/SKILL.md:10` (the adoption count: "four sheets") and :87 (the
  `MenuAnchor` gap).

## 6. Slices

### Slice 1 — Primitives

`FormCheckRow`, `FormSearchRow`, `FormTrailingButton.identifier`,
`FormMenuRow` on a popup route with `FormMenuItem.identifier` (D12;
`_ChoiceItem` shared with the header menus), `CalendarFilterSummary.
namesReadBack` with `CategoryFilterTile` pointed at it, the `SemanticsIds`
of §3.9. Tests: `form_rows_test.dart`
gains — a check row is one node with its checked state and id, toggles from
the id, is 48 / 62 / 56 tall by shape, is faded and inert when disabled; an
exclusive check row is a radio node; a search row's field carries its id and
its clear button is a second node that empties it; a menu row's items are
radio nodes with ids and the current one checked, the menu right-aligned to
the group. The editor's Priority and Day rail cases
(`event_editor_redesign_test.dart:719–726`,
`event_editor_day_rail_test.dart:146`, both on `find.byType(MenuItemButton)`)
stay green with their finders on the popup item;
`category_picker_sheet_test.dart`'s `CategoryFilterTile` group :253 passes
unchanged.

### Slice 2 — The Filters sheet

`CalendarFilterSheet` rebuilt per §3.2 in the shape of §3.1;
`FilterCheckListSheet` (§3.3–3.4); the two menus; Reset; the Saved filter
row wired to today's `FilterPresetSheet.show` (restyled in slice 4) and
`_saveAsPreset`; the two app-bar ids; D17 in the model; the ARBs ×3 (§3.8,
the retitles included; the retirements wait for slice 5). Tests:
`category_filter_sheets_test.dart` 'calendar filter sheet' rewritten — the
Categories row reads "All", opens the picker, and the denylist is the inverse
of its answer; Select all in the picker empties archived denials; Select
none hides everything and the row reads "No categories"; Priority Done
returns the set and the row reads "Highest, High"; Only show Done writes the
seven flags and the row reads the names then "+N more"; the menus change
`eventType` / `timing`; Fasting is present and inert while
`FastingCalendar.isEnabled` is false; Reset is inert on an empty draft,
clears everything but `panelShowsAll` and keeps the sheet open; Apply pops
the draft, ✕ / barrier / back pop `null`; the saved-filter row reads the
matching preset's name and its bookmark is inert when empty or saved. A new
`test/widgets/filter_check_list_sheet_test.dart` (Done / cancel, ids,
disabled rows). `calendar_grid_filters_test.dart` gains "an array of
priorities decodes like the comma string". `sheet_bottom_clearance_test.dart`
gains the Filters sheet and the check-list sheet. The German 200 % / 360 × 780
block in the shape of the editor suite: no overflow, every label whole.

### Slice 3 — The Categories sub-sheet

`CategoryPickerSheet` migrated in place per §3.5 (D13), both modes, the
`FormSearchRow`, the two bulk rows, the create row, height clamped at 0.92.
Tests: `category_picker_sheet_test.dart` — every existing case green with
finders on the new rows (by id where a label is not unique), plus: Done
returns the set, ✕ returns `null`, single mode pops on tap with no Done,
the search row appears past twelve rows and while a query is live, the bulk
rows are disabled where they would be no-ops, the create row opens the
editor. The agenda group of `category_filter_sheets_test.dart` and
`agenda_filters_sheet_test.dart` green. The clearance test gains the picker
in both modes.

### Slice 4 — The Saved filters sub-sheet

`FilterPresetSheet` migrated in place per §3.6 (D14); the ⋮ menu on the
shared radio-item anatomy; the Filters sheet's row now reads back and loads
a preset. Tests: `filter_preset_sheet_test.dart` — every case green with its
finders on rows ("No filter" for "Show everything", thirteen presets for the
search cases, a dimmed save row for the hidden one, no paragraph for the
empty state), plus: "No filter" pops `cleared()` and keeps `panelShowsAll`;
a preset row pops its filters; the ⋮ menu's rows carry their ids and Update
is disabled while in use or empty; from the Filters sheet a pick replaces the
draft and "No filter" resets it. The clearance test gains the sheet.

### Slice 5 — Delete the old UI and the dead keys

The chip / segment / trait / layer builders, `_SectionLabel`,
`categoryChipsKey`, `_clearAll`, the bottom bar and the header row of the
old Filters sheet; `_SaveCurrentTile`, `_PresetTile`, `_EmptyState` of the
presets sheet; the old picker chrome and `_CategoryPickerRow`; the retired
keys of §3.8 after `grep -rn <key> lib test tool` each; dead imports
(`FilterChip`, `SegmentedButton`, `SettingsSearchField` where no longer
read). `dart analyze lib test` clean; the whole suite green.

### Slice 6 — Device pass, review, docs

- A new flow `tool/qa/flows/calendar/09_filters.txt` after
  `qa run --fresh --seed tool/qa/fixtures/calendar.json`:

  ```
  # The filter sheet (docs/calendar-filters-redesign-roadmap.md): every row by
  # id, each sub-sheet, a preset loaded from the sheet, Apply, then Reset.
  tap id:calendar-filter-open
  wait id:filter-apply
  expect id:filter-saved-filter id:filter-categories id:filter-priority id:filter-repeat id:filter-time id:filter-only-show id:filter-holidays id:filter-fasting id:filter-money id:filter-panel-all id:filter-reset
  shot 09_filters
  tap id:filter-priority
  wait id:filter-list-done
  tap id:filter-list-priority-1
  tap id:filter-list-priority-2
  shot 09_priority
  tap id:filter-list-done
  wait id:filter-apply
  expect "Highest, High"
  tap id:filter-only-show
  wait id:filter-list-done
  tap id:filter-list-tracked
  tap id:filter-list-done
  wait id:filter-apply
  tap id:filter-repeat
  wait id:filter-repeat-recurring
  shot 09_repeat_menu
  tap id:filter-repeat-recurring
  wait id:filter-apply
  tap id:filter-categories
  wait id:category-pick-done
  shot 09_categories
  tap id:category-pick-done
  wait id:filter-apply
  tap id:filter-holidays
  tap id:filter-saved-filter
  wait id:filter-preset-none
  expect id:filter-preset-qa-cal-preset-top "Highest, High"
  shot 09_saved_filters
  tap id:filter-preset-qa-cal-preset-top
  wait id:filter-apply
  expect "Top priority"
  shot 09_filters_active
  tap id:filter-apply
  wait id:calendar-add-event
  tap id:calendar-saved-filters-open
  wait id:filter-preset-none
  shot 09_saved_from_bar
  key back
  wait id:calendar-add-event
  tap id:calendar-filter-open
  wait id:filter-reset
  tap id:filter-reset
  tap id:filter-apply
  wait id:calendar-add-event
  errors
  ```

  The badge is checked on the `09_filters_active` shot and by reopening the
  sheet (a bare `expect "1"` is ambiguous on a month grid). `qa flows
  calendar --via agent` all green.
- The matrix: `qa set theme=dark locale=de text-scale=2.0`, then the Filters
  sheet, each sub-sheet and the presets sheet shot beside the canvas boards
  (`CStressDe` is the German 200 % reference); `qa set` back; the 360 × 780
  and 412 × 915 sizes through the widget suites when only the 427 dp
  emulator is available (the header record's precedent). `qa errors` clean.
- Independent review by a fresh `fable-max` subagent briefed with this record
  and the diff: confirmed defects only; fix; rerun the gate.
- Docs in the same slice: an addendum "## Addendum (2026-09-27): the filter
  sheet in the editor's language" in `docs/calendar-events-feature.md` (the
  history, the decisions' why, the deviations); `COPILOT_CONTEXT.md:80`'s
  "UI is …" sentence rewritten (the sheet, the sub-sheets, the presets row,
  the tolerant decoder); `.claude/skills/calendar-events/SKILL.md:85–86`
  (the picker's new chrome, "only the agenda sheet and the overview render
  `CategoryFilterTile`"); `.claude/skills/calendar-ui/SKILL.md:10` (the
  adoption count: eight sheets — the Filters sheet, the check-list sheet, the
  picker, the presets sheet) and :87 (the `MenuAnchor` gap closed by D12,
  `FormCheckRow` / `FormSearchRow` in the primitives table). Narrative stays
  in the docs.

## 7. Definition of done

1. **Round-trip.** For every filter the old sheet could express, the new
   sheet's Apply pops a `CalendarGridFilters` equal to the old one's
   (`test/models/calendar_grid_filters_test.dart` unchanged; the rewritten
   sheet suite compares the popped draft against constructor calls); the
   persisted blob is byte-identical for the same draft; the fixture's "Top
   priority" preset decodes to `{1, 2}`.
2. **One-handed on 360.** Every control on every surface is a 48 dp target:
   the rows, the row's trailing bookmark and ⋮, the check boxes, the search
   row's clear button, Done and ✕; the Filters sheet's header is reachable
   without scrolling on 360 × 780.
3. **Leaving.** ✕, back, the system back gesture, the barrier and drag pop
   `null` on the Filters sheet and every sub-sheet; Apply / Done pop the
   draft; no dialog anywhere (D9).
4. **Light and dark; en, de, ro; text scale 1.3 and 2.0.** A filter with all
   seven traits set reads "Tracked, Missed +5 more" on the Only show row; in
   German at 2.0 on 360 the value drops under its label and neither clips
   nor overflows; "Alle Ereignisse im Tagesbereich" wraps beside its switch;
   "Toate evenimentele în panoul zilei" likewise; the header's Apply /
   Übernehmen / Aplică never pushes the title off.
5. **Keyboard.** The Categories and presets search rows raise the keyboard
   without the sheet losing its header; every sheet's bottom padding is at
   least the navigation bar (the clearance test, four new cases).
6. **Nothing moves under the finger.** Fasting is present at 38 % while
   inert; Reset and the two bookmarks dim, never vanish; the bulk rows dim
   where no-op; the presets' save row dims while searching; a check row's
   caption changes text, never height; a menu opens above the row when
   there is no room below.
7. **Strings.** Every string of §3.8 in the three ARBs; `untranslated.txt`
   is `{}`; the retired keys are absent from `lib`, `test` and `tool`; the
   chip strip reads "Not ended" and "Without Holidays" as before.
8. **Semantics.** Every icon-only button has a tooltip; every row is one
   node; every id of §3.9 is on its control (the `look` dump shows them);
   the menu items are radio nodes on Android **and** iOS (the D12 fix);
   TalkBack reads the Saved filter row as one announcement plus its button.
9. **Suites.** `agenda_filters_sheet_test.dart`, `calendar_header_test.
   dart`, `calendar_sheet_double_tap_test.dart` and the model suite pass
   unchanged; the picker, presets and filter-sheet suites pass with finders
   updated and assertions kept; the new cases of §6 exist; `qa flows
   calendar --via agent` is ten for ten; `qa errors` is clean after the
   matrix.

## 8. Deferred

- **Lenses first** — the preset list as the top level with the axes one
  level down: a different product, revisit only if presets become the
  primary way the owner filters.
- **A "minimum priority" menu** (Any / High and up / Normal and up / …) in
  place of the multi-select sub-sheet: simpler, encodes to the same set,
  drops arbitrary combinations; the owner's call once the sub-sheet has been
  used for a while.
- **The chip strip** (`CalendarFilterChips`): unchanged here; whether a
  chip should open the sub-sheet of its own axis instead of the whole sheet
  is a separate question.
- **The agenda filter sheet** (`agenda_filters_sheet.dart`) still speaks the
  old language (chips, segmented buttons, `CategoryFilterTile`); it moves
  when a change opens it, per the adoption rule — the migrated picker it
  opens already speaks the new one.
- **A quick "hide this category" from a day-panel row** or the categories
  page — outside this sheet.
- **The Categories sub-sheet's count line** ("N categories") was dropped
  (§3.5); if the device pass shows people counting check marks, a
  `FormCaption` under the bulk rows is the place.
