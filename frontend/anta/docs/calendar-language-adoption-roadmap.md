# Calendar UI Language Adoption — Roadmap for the remaining surfaces (2026-09-27)

**Status: PLAN, not started.** Written at the end of the Filters sheet
rework (`docs/calendar-filters-redesign-roadmap.md`, shipped uncommitted the
same day) after the owner asked which calendar components still need the new
UI language and said to write everything down so the long process can start
in the next session. Line numbers in §2 and §7 are from a read of the tree on
2026-09-27 (`cf517cb` plus the uncommitted Filters rework); re-grep every one
before editing.

## 0. How to run this

**The owner's instruction, verbatim in spirit (2026-09-27): absolute maximum
effort. This is the last calendar pass for a long while — the calendar will
not be revisited soon, so nothing may be left half-done, no defect may be
deferred "for later", every surface must be device-verified, and the result
must be as good as the editor, the detail sheet and the Filters sheet.**
In practice:

- **Models.** Design, implementation and the independent review all run on
  `fable-max` (Fable at maximum effort — `.claude/agents/fable-max.md`), one
  implementer writing at a time, reviewers read-only. Exploration may go to
  Opus. This overrides the budget split in memory for this pass; the owner
  chose it.
- **Process.** The `ui-revamp` skill, tier by tier: a design record per tier
  (§1 of that skill's structure — how to run, why, decisions D1…Dn, spec,
  behaviour, facts, slices, definition of done, deferred), mocks on a Design
  canvas **only** where a layout is a real design question (§3 says which),
  slices with the gate after every one, a device pass through the QA harness,
  an independent review with confirmed defects fixed, docs in the same change.
  The worked examples: `docs/event-editor-redesign-roadmap.md` (the language)
  and `docs/calendar-filters-redesign-roadmap.md` (the most recent, with its
  D22–D24 deviations, the review round and the device pass — copy its shape).
- **Skills to load** in the implementing session: `anta-context`,
  `calendar-events`, `calendar-ui`, `ui-revamp`, `verify`, `l10n`,
  `qa-emulator`; `markdown-engine` only for the description sheet.
- **The gate after every slice:** `dart analyze lib test` clean; the whole
  `flutter test` green in one run (`test/qa/host_devices_test.dart` has one
  known Windows-only failure — note it, never touch it); `flutter gen-l10n`
  and `untranslated.txt` (at `frontend/anta/untranslated.txt`) equal to `{}`
  when an ARB changed; the tier's must-not-change list re-read against
  `git diff`.
- **The device pass** (last slice of every tier): `tool\qa\qa.cmd run --fresh
  --seed tool/qa/fixtures/calendar.json` after any `lib` change, then
  `qa flows calendar` with `$env:ANTA_QA_VIA = 'agent'` (the flows cannot type
  on the adb path while the driver build owns the text channel; `flows` has
  no `--via` flag), every flow green before anything else is looked at, a new
  or updated flow for every surface the tier changes, the matrix `qa set
  theme=dark locale=de text-scale=2.0` with every screen shot beside its
  board, `qa errors` clean, `qa set theme=light locale=system text-scale=off`
  at the end. Never `adb` by hand.
- **Do not commit.** The owner reviews the tree and commits. Keep the tree
  small: one tier at a time, the owner commits between tiers.
- **The owner's standing decisions** (§4) are not re-argued. New design
  questions are asked as lettered options, recommended first; "implement it"
  without letters means the recommended option stands and the record says it
  was delegated.

## 1. Why

The 2026-09-25 event editor redesign set the calendar's UI language: grouped
rows (`FormRowGroup`) on a layered ground, uppercase section labels, `label …
value ›` picker rows, switch rows, action rows, labelled chip rows, check and
search rows, menu rows on a popup route, a 22 dp handle strip, a 48 dp header
with one leading icon, a left-aligned title and one trailing text action, no
bottom action bar, no `Card`, no elevation, content-tall sheets clamped at
`FormMetrics.sheetHeightFactor`. The rulebook is
`.claude/skills/calendar-ui/SKILL.md`; the numbers are `FormMetrics` and
`RowMetrics`.

**Eight sheets speak it today:** `event_editor_sheet.dart`,
`event_repeat_sheet.dart`, `event_look_sheet.dart`, `event_detail_sheet.dart`,
`calendar_filter_sheet.dart`, `filter_check_list_sheet.dart`,
`category_picker_sheet.dart`, `filter_preset_sheet.dart`. Twenty calendar
sheets, three pages and two panels do not (§2). Every one of the migrated
sheets opens at least one of the old ones (the editor opens the alert editor,
the time pad, the Dates sheet, the description sheet, the icon picker, the
template editor; the Filters sheet's picker opens the category editor), so the
seam is visible in the app's most-used flows.

The adoption rule of 2026-09-26 ("an older sheet moves to the primitives when
a change opens it and touches its chrome, never as a drive-by") is **overridden
for this pass by the owner's decision of 2026-09-27**: the remaining surfaces
are migrated in planned tiers. The rule returns once this roadmap is done.

## 2. Inventory (read 2026-09-27)

Chrome was read from the widget names and l10n keys each file uses. "drag" =
`showDragHandle: true` (the stock 48 dp band); "hF" = the fixed
`FractionallySizedBox` height factor; "Cancel/Save" = a bottom or inline
action bar. Frequency is how often a user meets the surface. Size: S = chrome
only, M = chrome plus rows, L = a rework with sub-parts or shared callers.

### 2.1 Sheets

| File (`lib/widgets/`) | Lines | What | Reached from · frequency | Chrome · controls today | Size · constraints |
| --- | --- | --- | --- | --- | --- |
| `agenda_filters_sheet.dart` | 652 | Upcoming agenda search/filter options | Upcoming agenda filter button (`upcoming_agenda_view.dart:1052`) · weekly | drag, no hF, Apply button; FilterChip ×5, ChoiceChip ×3, SegmentedButton ×3, SwitchListTile, `CategoryFilterTile` | M–L — the Filters sheet's twin; chips become rows |
| `alert_editor_sheet.dart` | 751 | Edit one event alert | Editor alert rows (`event_editor_sheet.dart:1250–1294`); default alerts in settings (`calendar_settings_page.dart:1053`) · weekly | drag, hF 0.7, Cancel+Save, Card ×4; ChoiceChip ×4, SegmentedButton ×2, SwitchListTile, ListTile ×2; opens TimePad, AlertSound | L — two callers, two sub-sheets |
| `event_template_editor_sheet.dart` | 776 | Create/edit an event template | `pages/event_templates_page.dart:53`; editor "Save as template" (`event_editor_sheet.dart:1484`) · setup | drag, hF 0.92, Cancel+Save+Reset, Card ×3; SwitchListTile ×5, ChoiceChip ×4, FilterChip, SegmentedButton, ListTile ×4, TextField ×2 | L — duplicates the editor's fields in the old language |
| `quick_alarm_sheet.dart` | 347 | One-tap alarm event | Template picker's quick-alarm row (`calendar_page.dart:1520`) · weekly | drag, hF 0.7, Cancel+Save, Card; ChoiceChip ×3, SegmentedButton, SwitchListTile, TextField; opens TimePad | M |
| `agenda_day_list_sheet.dart` | 854 | Agenda day list, period-navigable (list / month / year drill-down) | Upcoming agenda day tap (`upcoming_agenda_view.dart:1015`) · weekly | drag, hF 0.88, centred text; SegmentedButton ×2, IconButton, TextButton; opens MonthYearPicker (:375) | M — see `docs/` day-list notes in memory (PopScope + Visibility test traps) |
| `calendar_date_picker_sheet.dart` | 1019 | Explicit dates / one-date picker (the Dates sheet) | Editor Dates rows (`event_editor_sheet.dart:1030–1140, 1748`), detail sheet (:598), Repeat (:194), `calendar_page.dart:1597`, fasting schedule (:90) · weekly | drag, hF 0.86, hand-rolled centred header, Cancel+Save `FilledButton`; GridView, SegmentedButton ×2, IconButton ×6 | S–M — **partial**: already uses `FormRowGroup`, `FormPickerRow`, `FormActionRow`, `FormSectionLabel`, `FormTrailingButton`; five callers; ids `date-picker-save` / `date-picker-cancel` are in flow `03_dates.txt` |
| `time_pad_sheet.dart` | 634 | Numeric time entry pad | Editor (:1177, :1205), alert editor (:351), template editor (:221), quick alarm (:114) · daily | drag, no hF, Cancel + `FilledButton` ×3 | S — four callers; keep the pad's keys and `ValueChangeHighlight` contract |
| `month_year_picker_sheet.dart` | 620 | Month/year wheel jump | Month title (`calendar_page.dart:2120`), overview (:497), day list (:375), date picker (:298) · daily | drag, no hF, Cancel+Apply; ListWheelScrollView, TextField | S–M — four callers |
| `event_description_sheet.dart` | 526 | Per-occurrence description editor (markdown) | Editor (`event_editor_sheet.dart:2352`), `calendar_page.dart:951` · weekly | drag, hF 0.92, centred title, `FilledButton`; IconButton | S — load `markdown-engine`; the docked markdown bar and the dirty guard are the *form-sheet* shape's reason to exist |
| `event_template_picker_sheet.dart` | 142 | Template list for quick add | Day long-press (`calendar_page.dart:1476`) · weekly | drag, hF 0.7, centred text; ListTile ×3 | S |
| `icon_picker_sheet.dart` | 406 | Searchable icon grid | Look sheet (:112), category editor, template editor, fasting style · occasional | drag, hF 0.85, centred title; Wrap grid, TextButton | S–M — `FormSearchRow` fits; the migrated Look sheet opens it |
| `alert_sound_sheet.dart` | 277 | Alert sound radio list | Alert editor (:270, :559); settings (`calendar_settings_page.dart:189, 840`) · setup | drag, no hF; `ListTile`s with a drawn radio glyph (not `RadioListTile`s — corrected 2026-09-27 on the Tier 1 read) ×3 | S–M — `FormRadioRow` fits; the system ringtone picker row stays |
| `category_editor_sheet.dart` | 339 | Create/edit a category | Categories page (`calendar_categories_page.dart:144`), category picker (`category_picker_sheet.dart:201`) · setup | drag, hF 0.85, Cancel+Save, Card; TextFormField, ListTile; embeds `ColorSwatchPicker` (:308), opens IconPicker (:133) | M |
| `fasting_schedule_sheet.dart` | 440 | Fasting period schedule editor | Settings Fasting section (`calendar_settings_page.dart:270`) · setup | drag, hF 0.86; ChoiceChip ×2, FilterChip ×2, ListTile, OutlinedButton, TextButton ×2 | M |
| `fasting_style_sheet.dart` | 464 | Fasting marker icon / colour / label | Settings (`calendar_settings_page.dart:253`) · setup | drag, hF 0.86, Card ×2; ChoiceChip ×2, TextField ×2, ListTile; `ColorSwatchPicker`, IconPicker | M |
| `removed_holidays_sheet.dart` | 124 | Restore removed holidays | Settings (`calendar_settings_page.dart:445`) · setup | drag, hF 0.6, centred empty state; ListTile, Divider | S |
| `color_palette_sheet.dart` | 373 | Edit the saved colour palette | Appearance page (`calendar_appearance_page.dart:829`), `ColorSwatchPicker` (:144, :211) · setup | drag, hF 0.86; ListTile, Wrap, OutlinedButton, TextButton, IconButton ×3; confirm dialogs | M — the palette is shared (`CalendarPaletteService`, colour labels) |
| `color_picker_sheet.dart` | 1104 | Custom colour (HSV / hex) | `ColorSwatchPicker` (:117, :151), palette sheet (:63, :73), **`pages/markdown_colors_page.dart:76`** · occasional | drag, no hF, Cancel + `FilledButton`; Slider ×3, SegmentedButton, TextField | L — **shared with the markdown colours page (notes)**; migrate the chrome only, never the picker's behaviour |
| `color_swatch_picker.dart` | 447 | Swatch row plus the colour sheet | Appearance page (:795), category editor, `event_look_sheet.dart:189`, template editor, fasting style · occasional | drag, no hF; ListTile ×3, Wrap | L — used by the migrated Look sheet and the appearance page |

Not calendar (out of scope here): `bar_switcher_sheet.dart` (the markdown
bar profile picker, `optimized_note_editor_page.dart:2595`) and
`money_detail_sheet.dart` (the ledger's `$$` breakdown,
`optimized_note_editor_page.dart:1595`).

### 2.2 Pages and panels

None uses `ContentRowShell` or any form-row primitive.

| File | Lines | Reached · frequency | Row / tile kinds | Shell |
| --- | --- | --- | --- | --- |
| `pages/calendar_settings_page.dart` | 1238 | Calendar settings · setup | `SettingsSectionList` / `SettingsSectionData` / `SettingsEntry`, 7 sections; ListTile ×12, SwitchListTile ×3, DropdownButton, `slider_setting_row` | the app-wide settings kit (`widgets/settings_section_list.dart`) |
| `pages/calendar_appearance_page.dart` | 939 | From settings · setup | the settings kit, 6 sections; SegmentedButton ×8, SwitchListTile ×4, ListTile ×2, `ColorSwatchPicker`, the pinned preview | settings kit |
| `pages/calendar_categories_page.dart` | 554 | From settings · setup | ReorderableListView ×2, `_CategoryRow` (:416) = Card + ListTile + PopupMenuButton ×2 | `settings_reorder.dart` |
| `pages/calendar_overview_page.dart` | 1004 | Overview (the title's view menu) · weekly | CustomScrollView slivers, `AgendaPeriodNav`, month/year grids, agenda list rows; one SegmentedButton | agenda widgets |
| `pages/alerts_page.dart` | 792 | Alerts hub (⋮ menu, drawer, the alarm's show intent) · occasional | Card ×3, custom `_AlertHubRow` (:382) and `_AlertHistoryRow` (:541) on InkWell, `_PermissionBanner` | nothing |
| `widgets/day_summary_panel.dart` | 345 | Calendar bottom panel, day mode · daily | Card in `rowGroup` colour (:229–236) + ListTile; mirrors `_AgendaCard` | nothing |
| `_AgendaCard` in `widgets/agenda_list_view.dart:1148` | (1382) | Upcoming agenda and the alerts page · daily | Card in `rowGroup` + 4 px colour stripe + ListTile with CircleAvatar | nothing |
| `widgets/calendar_filter_chips.dart` | 70 | Active-filter strip (opt-in setting) · daily | InputChip | nothing |
| `widgets/calendar_bottom_panel.dart` | 484 | The calendar's bottom half · daily | mode SegmentedButton on `pageGround`; hosts the day summary, timeline and agenda panels | nothing |

### 2.3 Calendar dialogs

All confirmations go through `widgets/app_dialogs.dart:33` (`AppDialogs.confirm`),
shared app-wide; the language's rule (an `AlertDialog` with a `TextButton`
cancel and a `FilledButton.tonal` confirm) is what it already draws — check,
do not rebuild. Inline dialogs: delete event and the unsaved-changes guard in
`event_editor_sheet.dart:1669, 1844`; the preset name dialog
`filter_preset_sheet.dart:562`. Confirmations: remove holiday
(`calendar_page.dart:1877`), delete category (`calendar_categories_page.dart:174`),
reset settings / delete all events (`calendar_settings_page.dart:1132, 1147`),
reset appearance (`calendar_appearance_page.dart:873`), cancel an alarm
(`alerts_page.dart:163`), delete template (`event_templates_page.dart:69`),
palette delete / reset (`color_palette_sheet.dart:88, 106`).

## 3. The plan — tiers, in order

Each tier is one design record, one implementing session, one owner commit.
Mocks (a Design canvas like `https://claude.ai/artifact/YJwZnZns6WrFxg5HkGQuLP`,
390 × 844 boards in both themes, the real "today" shots beside them) are made
where the tier says so and shown to the owner as lettered choices before the
record is written; chrome-only surfaces need no mocks.

### Tier 1 — the Upcoming agenda's filter sheet + the chrome-only pass

The cheapest tier that removes the most visible seams. **Mocks: the agenda
filters sheet only** (it has real layout questions: which of the Filters
sheet's rows it shares, how search and the agenda-only axes fit).

1. **`agenda_filters_sheet.dart`** — rebuild in the Filters sheet's shape.
   Reuse `FilterCheckListSheet`, `CategoryPickerSheet`, `FormMenuRow`,
   `CalendarFilterSummary.namesReadBack`; the agenda's own axes (its search
   field, its period / sort / grouping choices, `upcomingSectionShow`,
   `upcomingFiltersReset`) become rows in the same grammar (a set → a picker
   row and a check-list sub-sheet; a three-way choice → a menu row; a boolean
   → a switch row). Decide with the owner whether the two filter models
   (`CalendarGridFilters` and the agenda's) should share more than the
   vocabulary — the record must list every agenda filter field and its
   default as must-not-change. Delete `CategoryFilterTile` and
   `_CategoryAvatarCluster` once the overview page (its last reader) is
   handled or given a row of its own; grep before deleting.
   Test: `test/widgets/agenda_filters_sheet_test.dart` (14 cases) keeps its
   assertions with finders moved. Flow: a new `10_agenda_filters.txt`.
2. **Chrome-only pass** — each sheet takes the sub-sheet shape of the
   `calendar-ui` skill (`showDragHandle: false`, `pageGround`, radius
   `sheetRadius`, `ConstrainedBox(maxHeight: … × sheetHeightFactor)`,
   `FormSheetHandle`, `FormSheetHeader(✕ · title · Done)`, `Flexible(scroll)`,
   clearance on the scroll padding, the header hairline on a `ValueNotifier`),
   its own content untouched unless a row primitive is an exact fit:
   - `calendar_date_picker_sheet.dart` — the hand-rolled header becomes
     `FormSheetHeader`, Save moves into the trailing slot as
     `FormHeaderTextButton`, the Cancel/Save bar goes; keep the ids
     `date-picker-save` / `date-picker-cancel` on the new controls (flow
     `03_dates.txt` and `07_detail.txt` use them) and the five callers'
     contracts. The grid, the segmented views (list / month / year) and the
     `YearMonthTile` matrix stay.
   - `time_pad_sheet.dart` — header + Done; the pad and its `FilledButton`
     confirm keys are the pad's own content (decide with the owner whether the
     pad's big confirm stays as the one exception to "no bottom bar" — it is
     a keypad, and one-handed entry ends on the thumb; recommend keeping it
     and recording it as D-something).
   - `month_year_picker_sheet.dart` — header + Done (Apply), no bar; the wheels
     stay.
   - `event_description_sheet.dart` — the **form-sheet** shape
     (`EventEditorSheet.show`'s: fixed 0.92, own drag, the dirty guard through
     one `_leave()`), because it has typed text and a docked markdown bar;
     load `markdown-engine`; the description's per-occurrence semantics
     (`docs/description-scope-roadmap.md`) are must-not-change.
   - `event_template_picker_sheet.dart` — a `FormRowGroup` of picker rows
     with `EventAvatar`, the quick-alarm row as an action row; header ✕ ·
     title · empty (pick-on-tap).
   - `icon_picker_sheet.dart` — header + Done, `FormSearchRow` as the first
     row, the grid stays; called by four sheets, contract unchanged.
   - `alert_sound_sheet.dart` — `FormRadioRow`s in a group, the system
     ringtone picker as an action row; the `system:default` / content-URI
     values and the phone-volume rule (`docs/event-alerts-*`) are
     must-not-change.
   Every migrated sheet joins `test/widgets/sheet_bottom_clearance_test.dart`
   and gets `SemanticsIds` for its Done / close; the flows that walk them
   (`02_editor_sheets`, `03_dates`, `04_alerts`, `07_detail`) are updated in
   the same slice.

### Tier 2 — the editor's satellites

**Mocks: yes, for all three** — they are forms with real grouping questions.

1. **`alert_editor_sheet.dart`** — a form in groups (WHEN: offset / at time
   with the time pad; HOW: tier Reminder / Alarm as a menu or chip row, sound
   as a picker row opening the migrated sound sheet, repeat / snooze switches;
   an actions group). Must-not-change: the `EventAlert` model, the planner /
   scheduler contracts (`docs/event-alerts-roadmap.md` sessions 1–4, the
   whole-module review of 2026-09-21), the cap of five, the Removed·Undo
   behaviour, the `alarm` fork's arm signature, the settings caller's default
   alerts. Two callers, both keep their signatures. Flow `04_alerts.txt`.
2. **`quick_alarm_sheet.dart`** — the same groups reduced; opened from the
   template picker's row and the Quick Settings tile / launcher shortcut
   (`qa-emulator` skill, 2026-09-23) — those entry points are must-not-change.
3. **`event_template_editor_sheet.dart`** — decide with the owner whether the
   template editor becomes the event editor in a "template" mode (one form,
   one set of groups, the template-only rows added) or a twin built from the
   same groups. Recommend the former if `EventEditorSheet`'s draft can carry
   a template without a persisted event; the record must prove the save path
   (`event_templates_page.dart`, "Save as template" from the editor) writes
   the same template as today. Flow: extend `01_new_event.txt` or add
   `11_templates.txt`.

### Tier 3 — the agenda day list and the setup sheets

1. **`agenda_day_list_sheet.dart`** — header with `AgendaPeriodNav` semantics
   kept (its list / month / year modes are the owner's 2026-09-02 design; the
   PopScope and `Visibility` test traps are in memory), the two segmented
   buttons become the view menu's grammar or a chip row; **mocks: yes** (one
   board per mode).
2. Setup sheets, chrome + rows, no mocks: `category_editor_sheet.dart` (title
   row with `EventAvatar`, Icon › and Colour › picker rows like the Look
   sheet, delete as a destructive action row), `fasting_schedule_sheet.dart`
   and `fasting_style_sheet.dart` (`docs/fasting-schedule-roadmap.md` is
   must-not-change), `removed_holidays_sheet.dart` (a group of action rows),
   `color_palette_sheet.dart` (rows + the swatch strip; shared with colour
   labels — `docs/colour-labels-roadmap.md`), `color_swatch_picker.dart`
   (chrome only; used by the migrated Look sheet), `color_picker_sheet.dart`
   (**chrome only**, header + Done; the HSV / hex picker is shared with the
   markdown colours page and its behaviour is must-not-change).

### Tier 4 — pages

1. **`calendar_categories_page.dart`** — `_CategoryRow` on the browser's
   `ContentRowShell` (a list page is the browser's language, not a form's)
   with the label dot / avatar, the ⋮ as a two-target row; reorder stays
   (`settings_reorder.dart`). Must-not-change: the category scaling rules
   (`docs/category-scaling-roadmap.md`, waves 1–4), archive = `is_hidden`.
2. **`alerts_page.dart`** — `_AlertHubRow` / `_AlertHistoryRow` on
   `ContentRowShell` or `FormRowGroup` (decide by whether the hub is a list
   or a form — it is a list), the three Cards gone, the permission banner
   kept; the OS-integration roadmap's snooze / log rows are must-not-change.
3. **`calendar_overview_page.dart`** — its agenda rows and the last
   `CategoryFilterTile` reader; the year / month tiles are the language
   already (`YearMonthTile`).
4. **Out of scope, deliberately:** `calendar_settings_page.dart` and
   `calendar_appearance_page.dart` use the app-wide settings kit — every
   settings page in the app speaks it, so changing it is an app-wide decision,
   not a calendar one. `day_summary_panel.dart` and `_AgendaCard` were decided
   on 2026-09-14 (rowGroup cards on the pageGround panel) and stay.
   `calendar_filter_chips.dart` stays (InputChips are the strip's grammar).
   `calendar_bottom_panel.dart`'s mode switch stays a `SegmentedButton`.

## 4. Standing decisions that apply to every tier

From the editor, detail and Filters records and the `calendar-ui` skill; not
re-argued:

- Ground `pageGround`, groups `rowGroup`, hairlines `rowDivider`, menus
  `menuSurface`; no `Card`, no elevation, no shadow in a sheet or form.
- Two sheet shapes only: the **form sheet** (fixed 0.92, own drag, the dirty
  guard through one `_leave()`) for a sheet with typed text or a docked bar;
  the **sub-sheet** (content-tall, clamped at 0.92, unguarded) for everything
  else. Never a third shape, never a fixed factor other than
  `FormMetrics.sheetHeightFactor`.
- Header: one leading icon (`close_rounded`, or `arrow_back_rounded` when
  re-entered from another sheet), a left-aligned title, one trailing text
  action (`Done` / `Apply` / `Save` as `FormHeaderTextButton`; the filled
  Save belongs to the editor alone). **Never a bottom action bar** (the time
  pad's confirm key is the one candidate exception — decide in tier 1).
- A sub-sheet's Done returns its draft, ✕ / drag / back / barrier return
  `null` and change nothing; a pick-on-tap list pops on the tap with an empty
  trailing slot.
- A row's glyph names the field, never the value; value lists carry their
  values' icons. Sets read back through `CalendarFilterSummary.namesReadBack`
  (two names, then "+N more"), never an ellipsis.
- Disabled = 38 % and inert, never hidden; nothing moves under the finger;
  captions change text, never geometry; no helper paragraphs under fields.
- Chips only in a labelled `FormChipRow`; menus through `FormMenuRow` (popup
  route, radio items with ids); multi-select lists through `FormCheckRow`;
  search through `FormSearchRow` past `AppConstants.listSearchThreshold`.
- Every number a `FormMetrics` / `RowMetrics` constant; a new number gets a
  name there first. `FormSectionLabel` uppercases and folds ß.
- Bottom clearance `max(viewInsets.bottom, viewPadding.bottom)` on the scroll
  view's padding; every sheet in `sheet_bottom_clearance_test.dart`.
- Ids (`SemanticsIds`, kebab-case, never renamed) on every control a flow
  targets; one semantics node per row, two for a two-target row; tooltips on
  every icon-only button; menus and pickers drop focus first.
- Every string through `AppLocalizations`, three ARBs together, `gen-l10n`.
- **Saved filters keep both entry points** (the row in the Filters sheet and
  the app-bar bookmark) — owner, 2026-09-27, "fine with it as it is".
- The drive-by rule is suspended for this roadmap and returns after it.

## 5. Gate and definition of done (every tier)

The `ui-revamp` skill's §4 checklist, adapted per record, always including:

1. Create / edit / delete round-trip equal to what the old UI wrote (compare
   through the old writer's tests; the persisted blob byte-identical).
2. Every control a 48 dp target on 360 × 780, one-handed; the header
   reachable without scrolling.
3. Dirty forms ask first on every exit; clean ones leave silently; sub-sheets
   never ask.
4. Light and dark; en, de, ro; text scale 1.3 and 2.0; no clipped label, no
   overflow — the German 200 % / 360 block in every suite.
5. Keyboard up and down: clearance holds, nothing shifts, nothing under the
   navigation bar.
6. Disabled, never hidden; constant-height sub-sheets.
7. `untranslated.txt` empty; retired keys absent from `lib`, `test`, `tool`.
8. Semantics: tooltips, one node per row, ids on every flow target; the
   `look` dump shows them.
9. The touched suites pass with assertions kept; new behaviour has new tests;
   `qa flows calendar` all green through the agent; `qa errors` clean after
   the matrix.
10. Docs in the same change: the area feature doc's addendum,
    `COPILOT_CONTEXT.md`'s section, the skills' rule lines (the adoption
    count in `calendar-ui`'s header paragraph, the file table, the
    primitives table); this roadmap's status line per tier.

## 6. Risks to brief every implementer with

- **Shared callers.** The colour picker is used by the markdown colours page;
  the palette by colour labels; the icon picker, the swatch picker, the time
  pad and the Dates sheet by four or five sheets each; the category editor by
  the picker and the categories page. Contracts never change; only the sheet's
  own chrome does. Grep every caller before and after.
- **The alert subsystem** has the deepest must-not-change list in the app
  (`docs/event-alerts-roadmap.md`, `event-alerts-os-integration-roadmap.md`,
  the 2026-09-21 whole-module review with 74 findings, the `alarm` fork). The
  alert editor's rework is chrome and grouping — never the planner, the
  scheduler, the arm signature or the sound values.
- **Test traps on record:** a bloc built in `setUp` lives outside the
  fake-async zone (`tester.runAsync`); an open popup route holds focus; the
  day-list sheet's `PopScope` and `Visibility` finders; the date picker's
  `YearMonthTile` semantics (one node per tile, the matrix excluded); drift
  under `FakeAsync`; `TextPainter` in `FakeAsync`; the `didChangeDependencies`
  unfocus trap (fake the keyboard through `tester.view` insets).
- **Emulator traps:** `ANTA_QA_VIA=agent`; `relaunch` starts the installed
  build (`run` after a lib change); day cells are label-only
  (`"{{longdate+N}}"`); titles are never targets on the calendar page; the QA
  build left installed makes the launcher open the QA database until the next
  normal run.
- **EOL:** the working copies the agents write are LF while the repo
  normalises to CRLF; `git diff` is clean, `git status` warns — harmless, do
  not "fix" line endings.

## 7. Facts to re-grep first (entry points per tier)

Tier 1: `upcoming_agenda_view.dart:1052` (filters), `agenda_filters_sheet.dart`,
`event_editor_sheet.dart:1030–1140, 1177, 1205, 1748, 2352` (Dates, times,
description), `event_detail_sheet.dart:598`, `event_repeat_sheet.dart:194`,
`calendar_page.dart:951, 1476, 1520, 1597, 2120`, `fasting_schedule_sheet.dart:90`,
`event_look_sheet.dart:112`, `alert_editor_sheet.dart:270, 351, 559`,
`calendar_settings_page.dart:189, 840`; flows `02_editor_sheets`, `03_dates`,
`04_alerts`, `07_detail`; ids in `lib/constants/semantics_ids.dart`.
Tier 2: `event_editor_sheet.dart:1250–1294, 1484`, `calendar_settings_page.dart:1053`,
`event_templates_page.dart:53`, `calendar_page.dart:1520`, the Quick Settings
tile and launcher shortcut entry points (grep `QuickAlarm`).
Tier 3: `upcoming_agenda_view.dart:1015`, `agenda_day_list_sheet.dart:375`,
`calendar_categories_page.dart:144`, `category_picker_sheet.dart:201`,
`calendar_settings_page.dart:253, 270, 445`, `calendar_appearance_page.dart:795, 829`,
`color_swatch_picker.dart:117, 144, 151, 211`, `color_palette_sheet.dart:63, 73`,
`markdown_colors_page.dart:76`.
Tier 4: `calendar_categories_page.dart:416`, `alerts_page.dart:382, 541`,
`calendar_overview_page.dart:497, 595`.

## 8. Size and order at a glance

| Tier | Surfaces | Records | Mocks | Rough size |
| --- | --- | --- | --- | --- |
| 1 | agenda filters + 7 chrome-only sheets | 1 | agenda filters only | 1 session |
| 2 | alert editor, quick alarm, template editor | 1 | all three | 1–2 sessions |
| 3 | agenda day list + 7 setup sheets | 1 | day list only | 1–2 sessions |
| 4 | categories page, alerts hub, overview rows | 1 | alerts hub | 1 session |

Sizes are judgments, not measurements. The owner commits after each tier;
the next tier starts on a clean tree.

## 9. Status per tier

| Tier | Status |
| --- | --- |
| 1 | **done 2026-09-27, uncommitted — the owner reviews and commits.** Record `docs/calendar-language-tier-1-roadmap.md` (D1–D25), canvas "Agenda Filters Mocks" https://claude.ai/artifact/FGLdxuNj5a3ATaDCpiaKYo. The agenda sheet rebuilt as the Filters sheet's twin (Events one menu over the whole axis), the seven chrome-only sheets migrated in three shapes (sub-sheet · the form box without its guard for the two fillers · the form sheet), `FormSheetFrame` hoisted from the editor, the description sheet guarded; gate: `dart analyze lib test` clean, `flutter test` 6137 / 7 skipped / the one known Windows case, `untranslated.txt` `{}`, `qa flows calendar` 12 / 12, `qa errors` clean after the matrix; the review confirmed no defect, its nits and the device pass's nine 200 % findings fixed the same day (D23–D25). Deferred to later tiers: `CategoryFilterTile` (Tier 4), the day-list's mini grid weekday style (Tier 3); to the owner: a two-line header at 200 %, a range mode for the Dates sheet |
| 2 | not started |
| 3 | not started |
| 4 | not started |
