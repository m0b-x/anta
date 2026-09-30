# Saved Filters — reorder, Move to top, named captions (2026-09-29)

**Status: IMPLEMENTED 2026-09-29, uncommitted — the owner reviews and
commits.** Slices 1–4 are in the tree: `dart analyze lib test tool
test_driver` clean, `flutter test` 6172 passed / 7 skipped in one run (after the review's two test fixes),
`untranslated.txt` `{}`, `qa flows calendar` twelve for twelve on the
iPhone 17 Pro Max simulator, a real drag by the handle verified on the
device, the dark / German / 200 % matrix shot beside the boards, `qa
errors` clean (the device-pass paragraph of the 2026-09-29 addendum in
`calendar-events-feature.md`). The independent review's findings and their
resolution are recorded in that addendum. The owner chose option A of the canvas **"Saved Filters Mocks"**
— https://claude.ai/artifact/9XMircZAa27BqnkfuTQekh — ("Implement A",
2026-09-29); decisions 2 and 3 were not answered separately, so their
recommended options stand as delegated. Line numbers in §5 are as of
`7e0423b` (a clean tree on 2026-09-29); re-grep before editing.

## 0. How to run this

Load `anta-context`, `calendar-events`, `calendar-ui`, `ui-revamp`, `verify`,
`l10n` and, for slice 4, `qa-emulator`. Read this record whole, then §5
against the tree. Work the slices of §6 in order; never start a slice with
anything red. After **every** slice the gate:

- `dart analyze lib test` clean;
- the **whole** `flutter test` green, one run at a time;
- `flutter gen-l10n` run and `untranslated.txt` empty whenever an ARB changed;
- §4.1 (must not change) re-read against `git diff`.

Slice 4 adds the device pass through the QA harness (`./tool/qa/qa run
--fresh --seed tool/qa/fixtures/calendar.json`, then `./tool/qa/qa flows
calendar`, every flow green before anything else is looked at; the matrix
`qa set theme=dark locale=de text-scale=2.0` with the sheet shot beside its
board; `qa errors` clean), the independent review by a fresh subagent briefed
with this record and the diff, and the docs. **Do not commit.**

## 1. Why

The saved-filters sheet (`lib/widgets/filter_preset_sheet.dart`) already
speaks the grouped-row language: it was migrated on 2026-09-27 (D14 of
`calendar-filters-redesign-roadmap.md`) — "No filter" first, one two-line
radio row per preset with its ⋮ (Rename · Update to current filter · Delete),
a search row past twelve presets, "Save the current filter" last, dimmed
rather than hidden. Nothing there needs restyling.

What it cannot do is be **ordered**. Presets list in the order they were
saved (`FilterPresetDao.getAll` by `sort_order`, then `id`; `create` appends
through `nextSortOrder`). The `sort_order` column has existed since v35
precisely "so it can become reorderable without a migration"
(`lib/models/calendar_filter_preset.dart:20`), and no DAO, service or UI
path writes it. Every other list in the app reorders: categories,
vocabularies, counters, the markdown shortcuts and utilities, the colour
palette, folders and notes.

Two smaller warts came up on the same read: a preset's caption **counts**
("Priority (2)", "Categories (5)") where the Filters sheet's rows **name**
("Highest, High", "Gym, Strength +3 more") — the flow `09_filters.txt` even
carries a comment about the mismatch — and three reorder strings
(`reorderMode`, `longPressToReorder`, `dragToReorder`) are defined in all
three ARBs and read nowhere.

## 2. Decisions

| # | Decision | Reason · rejected alternatives | Who |
| --- | --- | --- | --- |
| D1 | **Drag handles always on, at the leading edge of every preset row.** Drag from the handle, or long-press the row (the categories page's pair). Reorder is locked while a search query is live: the handles dim to 38 %, the rows stop being draggable, Move to top is disabled. | The app's own idiom: every list you can order shows its handle all the time (categories, vocabularies, counters, the palette, the shortcut lists); only the folder browser hides it, and there a selection mode already exists for other reasons. No mode to discover, nothing to explain, no hidden affordance (the owner's 2026-09-26 objection). *Rejected:* **B**, an Edit mode behind the header's trailing slot (one tap more for a rare action; a third meaning for a sub-sheet's Done, which elsewhere returns a draft; the handles hidden behind a button); **C**, no drag — Move up / Move down / Move to top in the ⋮ (three taps per step; fine for four presets, miserable for fifteen); **D**, a management page from Calendar settings (a third entry point, management already happens in place, Tier 4 has not defined the page language yet). | owner, 2026-09-29 ("Implement A") |
| D2 | **"Move to top" joins the ⋮**: Rename · Update to current filter · Move to top · Delete; dimmed while the preset is already first or a query is live. | The categories page's reasoning: dragging row twelve to the top is miserable at any auto-scroll speed. Not "Move up / Move down": the drag covers those. | owner, delegated 2026-09-29 (recommended option stands) |
| D3 | **Captions and the suggested name name the sets** through `CalendarFilterSummary.namesReadBack`: "Highest, High", "Gym, Strength +3 more". The chip strip keeps its short labels ("Priority (2)") — a chip must stay one word wide. | The caption and the search stop counting where every other read-back names; the suggested name follows because "Priority (2) · Recurring" is not a name anyone would type. | owner, delegated 2026-09-29 (recommended option stands) |
| D4 | **The handle is a third slot on `FormCheckRow`** (`handle:`), a 48 dp target flush with the row's start (`FormMetrics.dragHandleSlot`), the text starting at 52 dp — the glyph rows' column, so the search row and the save row line up with the names — and the hairline indented 52. The slot holds a new `FormDragHandle` primitive: the shared `ReorderHandle` from `settings_reorder.dart` (so the four reorderable lists and this one read as one system) inside a semantics node carrying its accessible name and its id. A **label, never a `Tooltip`**: a tooltip brings a long-press recogniser that wins the arena and kills the drag (the palette sheet's note). | The language's rule — use the primitives, never a raw `Icon` with a size — and the trailing button's precedent (a sibling target outside the row's own node). | lead, 2026-09-29 |
| D5 | **The sheet's body becomes a `ReorderableListView.builder` that owns its scrolling** (`shrinkWrap: true` under the sub-sheet's `ConstrainedBox`, so the sheet stays content-tall and clamped at 0.92): `header:` the "No filter" group; items the search row (past the threshold), the preset rows and the save row, each in a **`FormRowShell`** — the row-at-a-time twin of `FormRowGroup` with the same tokens, corners on the first and last rows only, the hairline under every row but the last; `footer:` the no-match caption. `buildDefaultDragHandles: false`; a preset row is wrapped in `ReorderableDelayedDragStartListener` (long-press anywhere) and its handle carries the immediate listener; `proxyDecorator` is the shared `reorderDragProxy` over a `ClipRRect` (a middle row has square corners of its own); `onReorderItem` clamps a drop into the preset run and ignores calls while a query is live (the list's own semantics actions can still fire); `onReorderStart` drops focus; the scroll controller keeps feeding the header's hairline. | A reorderable list nested in the existing `SingleChildScrollView` with `shrinkWrap` "silently kills dragging past the fold" (the categories page's note): the edge auto-scroller binds to the nearest `Scrollable`, which must be the list itself. `SliverReorderableList` wraps every item in a semantics *container* (not a merge) carrying "move up / down / to start / to end" custom actions, so the row's own node, its ⋮ and its handle stay separate nodes and a screen reader gets reorder for free. | lead, 2026-09-29 |
| D6 | **Persistence is one no-read batch.** `FilterPresetDao.reorder(idsInOrder)`: one transaction of `customUpdate`s writing `sort_order = i, updated_at, hlc_timestamp, device_id, version = version + 1 WHERE id = ? AND is_deleted = 0 AND sort_order != ?` — dense `0..N-1` over the ids given, unchanged rows untouched (no version bump), tombstones and unknown ids no-ops. `FilterPresetService.reorder(ids)` serializes on a chain (`_serialize`, the tail starting `null` — `CategoryService`'s reasoning) and reloads the cache; every preset mutation, the backup import included, rides the same chain. The sheet applies the order optimistically and reconciles with the service afterwards whether the write succeeded or not (the categories page's `_guarded` shape), so a failed write visibly springs back. | The notes' `setNotePositions` shape (`query_count_test` "reordering never reads a row to write it"); the vocabulary DAO's read-per-row is the older idiom. Two quick drags issue two reorders; the chain makes the last one the truth. | lead, 2026-09-29 |
| D7 | **Tombstones keep their `sort_order`**; `nextSortOrder` still counts them. A resurrected tombstone may land beside a live row's position; the `id` tie-break settles it. | Not worth a rewrite of the resurrection path; nothing in app code resurrects. | lead, 2026-09-29 |
| D8 | **Copy.** New `filterPresetReorder` "Drag to reorder" (the handle's accessible name). Reused: `moveToTop`, `filterPresetRename`, `filterPresetUpdate`, `delete`, `filterPresetActions`. Retired after grep: `reorderMode`, `longPressToReorder`, `dragToReorder`. | §3.6. | lead, 2026-09-29 |
| D9 | **Ids.** `SemanticsIds.filterPresetHandle(id)` = `filter-preset-handle-<id>` on the handle's node; `filterPresetMoveToTop` = `filter-preset-move-top` on the menu item. | A flow taps the menu item by id; the `look` dump shows the handles. | lead, 2026-09-29 |
| D10 | **The fixture gains a second preset** `qa-cal-preset-tracked` "Tracked" (`{"trackedOnly":true}`, `sortOrder` 1); the flow opens its ⋮, taps Move to top, and shoots the reordered list; the caption expectation reads "Highest, High". | A reorder needs two rows; a drag cannot be scripted by label, so the device pass drags by hand and the widget suite pins the drag. | lead, 2026-09-29 |

## 3. The spec

### 3.1 Geometry and tokens

- **`FormMetrics.dragHandleSlot` = 48** — the handle's target, the trailing
  button's size mirrored at the row's start. The text column after it is
  `dividerIndentGlyph` (52): slot + 4.
- **The handle**: `Icons.drag_handle` 24 in `onSurface` at α 0.4 (`ReorderHandle`,
  unchanged), α 0.15 while locked (`enabled: false`) — 38 % of the enabled
  alpha, the language's disabled opacity in effect.
- **`FormRowShell`**: background `rowGroup`, radius `RowMetrics.groupRadius`
  on the first row's top and the last row's bottom, a 1 px `rowDivider`
  under every row but the last at the child's `FormRowGroup.indentOf`,
  `RowMetrics.groupGap` below the last row when `trailingGap`. Only the end
  rows are a clipped `Material`; a middle row is a `ColoredBox` hosting a
  transparent `Material` for its ink (the browser shell's reasoning).
- **The drag proxy**: `reorderDragProxy` (2 % scale, elevation 6 × t, radius
  12) over `ClipRRect(12)`.
- Everything else is what the sheet already uses: `sheetHeightFactor`,
  `bodyTop`, `bodyBottom`, `groupInset`, `twoLineRowMinHeight`,
  `menuRowHeight`, `disabledOpacity`.

### 3.2 The sheet (`FilterPresetSheet`), top to bottom

Header: ✕ (`filter-preset-close`) · "Saved filters" · empty slot. Unchanged.

Body: `ReorderableListView.builder(scrollController: _bodyScroll, shrinkWrap:
true, buildDefaultDragHandles: false, padding: EdgeInsets.fromLTRB(groupInset,
bodyTop, groupInset, bodyBottom + clearance), header:, footer:, itemCount:,
itemBuilder:, onReorderStart:, onReorderItem:, proxyDecorator:)`.

- **Header**: `FormRowGroup([FormCheckRow(exclusive, "No filter", checked:
  current.isEmpty, id filter-preset-none)])` — unchanged, its own
  `groupGap` below.
- **Items**, in order: the search row while `_presets.length >
  listSearchThreshold || _query.isNotEmpty` (unchanged rule); one
  `_PresetRow` per visible preset; the save row. Each item is
  `FormRowShell(first: i == 0, last: i == last, trailingGap: false, child:)`;
  a preset item is additionally wrapped in
  `ReorderableDelayedDragStartListener(index: i, enabled: canReorder)`.
  Keys: `ValueKey('search')`, `ValueKey(preset.id)`, `ValueKey('save')`.
- **A preset row** (`_PresetRow` → `FormCheckRow`): `handle:
  FormDragHandle(index: i, enabled: canReorder, label:
  filterPresetReorder, identifier: filterPresetHandle(id))`, `exclusive:
  true`, `label: name`, `caption: describe(filters)`, `checked: filters ==
  current`, `identifier: filterPresetRow(id)`, `trailingButton:` the ⋮
  (`filterPresetOptions(id)`). The hairline under it is indented 52.
- **`canReorder`** = `_query.isEmpty`.
- **Footer**: `FormCaption(filterPresetNoMatches, padding:
  groupCaptionPadding)` while a query has no hits, else null.
- **`_onReorder(oldIndex, newIndex)`**: return while `!canReorder`; map the
  item indices to the preset run (`firstPreset` = 1 while the search row is
  shown, else 0); clamp `newIndex` into `[firstPreset, firstPreset +
  presets.length - 1]`; build the new list; `_persistOrder(ordered)`.
- **`_persistOrder(ordered)`**: `setState(_presets = ordered)`, then
  `service.reorder(ids)`, then reload from the service whether it succeeded
  or not (a failed order visibly springs back — the categories page's
  feedback).
- **`_moveToTop(preset)`**: the same funnel with the preset moved to index 0.
- **The ⋮** (`_openActions`): Rename · Update to current filter (disabled
  while in use or `current.isEmpty`, unchanged) · Move to top (disabled
  while `_presets.first.id == preset.id || !canReorder`) · Delete;
  `formMenuHeight(4)`.
- The name dialog, save, rename, update, delete: unchanged.

### 3.3 The primitives (`lib/widgets/form_rows.dart`)

```dart
class FormDragHandle extends StatelessWidget {
  const FormDragHandle({super.key, this.index, this.enabled = true,
      required this.label, this.identifier});
}
```

A `SizedBox.square(FormMetrics.dragHandleSlot)` centring
`ReorderHandle(index: enabled ? index : null, enabled: enabled)` inside
`Semantics(label: label)`; `AutomationId(identifier)` when given, so the
handle is one node with its name and its id. `index: null` draws a handle
that drags nothing (a list that is not reorderable yet, a test host).

`FormCheckRow` gains `final Widget? handle;` — when present the outer row is
`[handle, Expanded(well), trailingButton?]`, the well's left padding is
`dividerIndentGlyph - dragHandleSlot`, and `dividerIndent` is
`dividerIndentGlyph`. Everything else about the row (the node, the caption,
the check glyph, the disabled opacity) is untouched.

```dart
class FormRowShell extends StatelessWidget {
  const FormRowShell({super.key, required this.first, required this.last,
      required this.child, this.trailingGap = true});
}
```

### 3.4 The DAO and the service

```dart
// FilterPresetDao
Future<void> reorder(List<String> idsInOrder);   // D6
// FilterPresetService
Future<void> reorder(List<String> idsInOrder);   // serialized, then _load()
```

### 3.5 The summary

`CalendarFilterSummary.facetsOf(filters, l10n, {bool named = false})`: with
`named`, the priority facet reads `namesReadBack` of the selected
priorities' labels (ascending, highest first) and the category facet
`namesReadBack` of the shown categories' labels ("No categories" when none
is shown, unchanged); every other facet is unchanged. `describe` and
`suggestName` pass `named: true`; the chip strip calls `facetsOf` as
before.

### 3.6 Copy and l10n

| Key | en | de | ro |
| --- | --- | --- | --- |
| `filterPresetReorder` (new) | Drag to reorder | Zum Neuordnen ziehen | Trage pentru a reordona |

Reused: `moveToTop` "Move to top" / "Nach oben" / "Mută sus", the ⋮'s
existing keys. Retired: `reorderMode`, `longPressToReorder`,
`dragToReorder` (each `grep -rn` clean outside the ARBs on 2026-09-29).

### 3.7 Semantics ids (`lib/constants/semantics_ids.dart`, after `filterPresetDelete`)

```
static String filterPresetHandle(String id) => 'filter-preset-handle-$id';
static const String filterPresetMoveToTop = 'filter-preset-move-top';
```

## 4. Behaviour

### 4.1 Must not change

- **`FilterPresetSheet.show(context, current:) → CalendarGridFilters?`**; a
  preset row pops its filters, "No filter" pops `current.cleared()`, ✕ / the
  barrier / back pop `null`; rename, update, delete (and now reorder) in
  place, never popping; in-use by value equality; the save row's three
  dimming rules; the search over name **and** description through
  `normalizeForSearch`; the name dialog's rules; the 50-cap snackbar; the
  double-tap guard on the page (`calendar_sheet_double_tap_test.dart`).
- **`FilterPresetService`**: `maxPresets`, `presets`, `isFull`, `matching`,
  `create` (appending through `nextSortOrder`), `update` (keeping the
  position), `delete` (soft), `exportData` / `importData` (the blob
  verbatim, `sortOrder` already round-tripped); `reset()` and the
  `DatabaseLifecycle` contract.
- **`FilterPresetDao`**: `getAll` ordering (`sort_order`, then `id`),
  `upsertPreset`'s stamping, `softDeleteById`, `nextSortOrder` counting
  tombstones, `importAll`, `deleteAll`; the table and its frozen DDL
  (`schema_parity_test.dart:319`); no schema change, no migration.
- **`CalendarFilterPreset`** and its `props`.
- **`CalendarFilterSummary.facetsOf`** as the chip strip reads it (no
  `named`): the same icons, the same short labels; `namesReadBack`;
  `CalendarFilterChips`.
- **The Filters sheet**'s Saved filter row and its `_openPresets` /
  `_saveAsPreset` (`calendar_filter_sheet.dart`), and the page's
  `_openPresetSheet` / `_presetSheetBody` / `_applyFilters`
  (`calendar_page.dart`).
- **`FormCheckRow`** without a `handle`: node, geometry, indent, disabled
  opacity, the trailing button as a sibling node — every existing case of
  `form_rows_test.dart` unchanged.
- **`settings_reorder.dart`** (`ReorderHandle`, `ReorderLockedHint`,
  `reorderDragProxy`) and its three callers — the proxy's radius may be
  given a name (`reorderProxyRadius`), never a new value.
- Backup format (version 7), soft deletes, CRDT fields.

### 4.2 Deliberately changes

| Today | After |
| --- | --- |
| Rows in save order, no way to move one | Drag handles on every preset row; long-press anywhere; Move to top in the ⋮ (D1, D2) |
| The body is a `SingleChildScrollView` over two `FormRowGroup`s | A `ReorderableListView` owning the scroll: the "No filter" group as header, shelled items, the caption as footer (D5) |
| The caption counts several priorities and categories | It names them (D3); the suggested name likewise |
| Preset rows' hairline indented 16 | 52, past the handle (D4) |
| `sort_order` written only by `create` and import | Also by `reorder`, dense, no reads (D6) |
| Three unused ARB keys | Retired (D8) |

## 5. Facts from the tree (as of `7e0423b`; re-grep before editing)

- `lib/widgets/filter_preset_sheet.dart` (614 lines): `show` :47–71,
  `_presets` :81, `_query` :87, `_bodyScroll` / `_headerScrolled` :92–93,
  `_load` :116, `_onQueryChanged` :132, `_visible` :140, `_otherNames` :155,
  `_saveCurrent` :166, `_rename` :192, `_updateToCurrent` :214, `_delete`
  :220, `_openActions` :239–313 (`formMenuHeight(_PresetAction.values.length)`
  :258, the three `PopupMenuItem`s :272–301), `build` :315 (`showSearch`
  :323, `canSave` :330, the `SingleChildScrollView` :360, group 1 :381, group
  2 :393–427 with the search row :397, the `_PresetRow` loop :404, the save
  row :420, the caption :428), `_PresetAction` :442, `_PresetRow` :449–486
  (`dividerIndent` :467, the `FormCheckRow` :471), `FilterPresetNameDialog`
  :494.
- `lib/services/filter_preset_service.dart` (232 lines): `maxPresets` :32,
  `_dao` :34, `reset` :69, `_cache` :73, `_load` :81, `matching` :96,
  `create` :108 (`nextSortOrder` :118), `update` :127, `delete` :132,
  `_byId` :137, `exportData` :153, `importData` :176. No `dart:async`
  import yet (the chain needs `Completer`).
- `lib/database/daos/filter_preset_dao.dart` (147 lines): `getAll` :20,
  `upsertPreset` :37, `softDeleteById` :78, `nextSortOrder` :101, `importAll`
  :116, `deleteAll` :138, `_byId` :142. The no-read idiom to copy:
  `lib/database/daos/note_dao.dart:635–656` (`setNotePositions`,
  `customUpdate` with `Variable<DateTime>(now)`, `updates: {notes}`).
- `lib/services/category_service.dart:175–192` (`_serialize`, `_writes`),
  `:287` (`reorder`).
- `lib/models/calendar_filter_preset.dart:20–21` (the "not user-reorderable
  yet" doc line).
- `lib/widgets/form_rows.dart` (1527 lines): `FormDividedRow` :14,
  `FormRowGroup` :20 (`indentOf` :30, the `Material` :54), `FormTrailingButton`
  :382–420, `FormCheckRow` :857–1030 (fields :860–873, ctor :875, `dividerIndent`
  :889, the `Row` :985, `well` :1001, the trailing `Row` :1022), `FormCaption`
  :1282, `FormSearchRow` :1326. Insert `FormDragHandle` after
  `FormTrailingButton`, `FormRowShell` after `FormRowGroup`.
- `lib/constants/form_metrics.dart`: `trailingButtonSize` :73,
  `dividerIndentGlyph` :124, `disabledOpacity` :156.
- `lib/widgets/settings_reorder.dart`: `ReorderHandle` :20–39,
  `reorderDragProxy` :82–99.
- `lib/utils/calendar_filter_summary.dart`: `facetsOf` :98, the priority
  facet :114–129, `describe` :264, `namesReadBack` :285, `suggestName` :296,
  `_categoryLabel` :313–328.
- `lib/constants/semantics_ids.dart:119–129` (the presets block).
- ARBs: `filterPresetActions` en :220 / de :55 / ro :52 (insert the new key
  after `filterPresetLimitReached`); `moveToTop` en :638 / de :152 / ro :149;
  `longPressToReorder` en :2337 / de :936 / ro :560; `reorderMode` en :2734 /
  de :1450 / ro :647; `dragToReorder` en :2738 / de :1454 / ro :648.
- Flutter 3.47.4 (`.metadata`, the SDK on PATH): `ReorderableListView`
  (`header`, `footer`, `shrinkWrap`, `scrollController`, `onReorderItem`,
  `buildDefaultDragHandles`, `proxyDecorator`) splits `padding` between
  header, list and footer; `SliverReorderableListState._wrapWithSemantics`
  wraps each item in `Semantics(container: true, customSemanticsActions:)`;
  `ReorderableDragStartListener` / `ReorderableDelayedDragStartListener`
  take `enabled`.
- Tests: `test/widgets/filter_preset_sheet_test.dart` (491 lines: `pumpSheet`
  :51 on an 800 × 1600 surface, `rowNamed` :92, `saveRow` :95,
  `seedPastThreshold` :107, `menuItem` :120, the ⋮ group :383);
  `test/widgets/form_rows_test.dart` (group 'check, search and menu rows'
  :507, the check-row cases :520–700, `host`, `dataOf` :508);
  `test/database/filter_preset_test.dart` (`insert` :44, group 'ordering'
  :151); `test/services/filter_preset_service_test.dart` (`tracked` :20);
  `test/database/query_count_test.dart` (:344 the notes' no-read case, :969
  the categories' batch case, `StatementCounter` in
  `support/db_test_support.dart:96`); `test/widgets/sheet_bottom_clearance_test.dart`
  (`scrollBottomPadding` :152, the preset case :633);
  `test/qa/calendar_fixture_test.dart:160` ("templates, presets and the
  custom holiday land").
- QA: `tool/qa/fixtures/calendar.json:382–391` (one preset);
  `tool/qa/flows/calendar/09_filters.txt:31–47` (the preset steps; the
  caption expectation :35).
- Docs: `docs/calendar-events-feature.md` (6105 lines; the last addendum
  :5941); `COPILOT_CONTEXT.md:81` (the presets paragraph);
  `.claude/skills/calendar-events/SKILL.md:94` (the presets bullet);
  `.claude/skills/calendar-ui/SKILL.md:47` (the `FormCheckRow` row of the
  primitives table).

## 6. Slices

### Slice 1 — Primitives

`FormMetrics.dragHandleSlot`; `FormDragHandle`; `FormCheckRow.handle`;
`FormRowShell`. Tests in `form_rows_test.dart`: a check row with a handle is
three nodes (the handle with its label and id, the row, the ⋮), 62 dp tall,
its text at 52, its hairline indent 52; a locked handle is faded and drags
nothing; a shell draws corners on the ends only and a hairline under every
row but the last; every existing case unchanged.

### Slice 2 — Persistence

`FilterPresetDao.reorder`, `FilterPresetService.reorder` (+ `_serialize`),
the model's doc line. Tests: DAO — dense positions, moved rows bump
`version` and take a fresh HLC, unchanged rows keep theirs, tombstones and
unknown ids are no-ops; `query_count_test` — no `SELECT`, at most one
statement per row; service — reorder persists and survives a reload, racing
reorders land in issue order, a failed write does not poison later ones,
reordering nothing changes nothing.

### Slice 3 — The sheet, the summary, the copy

The body per §3.2; Move to top; `facetsOf(named:)`; the ARB trio +
`gen-l10n`; the retired keys; the ids. Tests: `filter_preset_sheet_test.dart`
— every existing case green; new: handles carry their ids, a drag on the
handle reorders and persists, a long-press on the row does too, a drag past
the fold scrolls the list, a drop outside the run clamps, handles and Move
to top are locked while searching, Move to top moves in place and is
disabled while first, the caption names the priorities;
`sheet_bottom_clearance_test.dart` — the preset case reads the list's
padding; a `calendar_filter_summary` case for `named`.

### Slice 4 — Fixture, flow, device pass, review, docs

The second fixture preset (+ `calendar_fixture_test.dart`), the flow steps,
`qa run --fresh --seed …` then `qa flows calendar`, the matrix, `qa errors`;
the independent review; the docs: the feature doc's addendum,
`COPILOT_CONTEXT.md:81`, the two skills' lines, this record's status.

## 7. Definition of done

1. **Round-trip.** Create, rename, update, delete write exactly what they
   wrote before (the service and DAO suites unchanged); a reorder writes
   dense `0..N-1`, bumps `version` only on moved rows, and comes back in
   that order after `reload()`; a backup round-trips the order.
2. **One-handed on 360.** The handle, the row and the ⋮ are each a 48 dp
   target; a drag from the handle and a long-press on the row both lift it.
3. **Nothing moves under the finger.** Handles dim, never vanish, while
   searching; the save row keeps its place; the sheet stays content-tall
   and clamped at 0.92.
4. **Light and dark; en, de, ro; text scale 2.0** on 360 × 780: the three
   targets and the two text lines fit, the caption clamps at two lines.
5. **Keyboard.** The bottom clearance holds with the list as the scrollable.
6. **Strings.** `untranslated.txt` is `{}`; the retired keys are absent
   from `lib`, `test`, `tool`, `.claude`, `docs`.
7. **Semantics.** The handle is one node with its label and id; the row and
   the ⋮ stay separate nodes; the list's items carry the reorder custom
   actions; the menu item carries `filter-preset-move-top`.
8. **Suites.** The whole suite green; `qa flows calendar` all green; `qa
   errors` clean after the matrix.

## 8. Deferred

- **Sort alphabetically** (the categories page has it in its ⋮): the sheet
  has no page menu; with drag and Move to top over at most 50 rows it is
  not needed.
- **The bar's bookmark reading selected while a preset is in use**: the
  filter button already says "filtered"; the sheet says which. Cheap, but
  a second filled icon beside the first is noise until asked for.
- **Hiding the lifted row's hairline in the drag proxy**: the browser's
  lifted rows carry theirs too.
- **A trailing handle** (the browser's place for it in selection mode):
  the ⋮ owns the trailing end here.
- **The list's own accessibility actions on the fixed rows.** Flutter's
  reorderable list puts move up / down / to start / to end on every item's
  container — the search row's and the save row's too, and on every row
  while a search locks reorder — and those do nothing, silently
  (`_onReorder`'s guards). Inherent to items-of-one-list; a custom
  `SliverReorderableList` wrapper would be the fix if a screen-reader user
  ever reports it.
- **A clamped drop's jump.** A drop the list offered above the search row
  or below the save row animates the proxy into that slot, then the row
  moves into the clamped slot on the next frame. Cosmetic, inherent to D5.
- **Two radii on a lifted end row**: its own 14 on the outer corners, the
  proxy's 12 on the clip and the shadow — 2 px, accepted in §3.1.
- **`pubspec.lock`** was rewritten by the SDK during the pass (`intl`
  0.20.2 → 0.20.3 and four transitive bumps) with `pubspec.yaml` untouched;
  reverted, nothing in the rework needs it.
