# Colour Labels — Roadmap & Slice Prompts (2026-09-12)

**Status: Phase 1 DONE and committed as `4b525b9` (2026-09-12). The
selectable rendering style — dot (Study A) or edge stripe (Study D), decision
L9 — is DONE and committed as `d6025a2`. Phase 2: Slice C DONE, reviewed and
committed as `0984341` (2026-09-13); Slices B and A DONE the same day, with
both §2 follow-ups (in-place folder refresh, darker light-mode yellow and
orange), strict-reviewed and fixed, UNCOMMITTED on `0984341` — see the
"Shipped" blocks under each slice. Slice D (names) was DROPPED by the owner
on 2026-09-13; the feature is complete without it.** The short checklist, with the slices numbered 1–5,
is `colour-labels-next-slices.md`; the two lettering schemes are: roadmap
Slice C = checklist 2, B = 3, A = 4, D = 5. The design page's *studies* A–D
are placements, not slices.
Design source: the studies artifact, Study A chosen by the owner on
2026-09-12: https://claude.ai/code/artifact/4debb1a3-e456-4e28-b401-470662658e7a
Line numbers below are as of the Phase 1 tree and will drift — re-grep
before editing.

Companion docs: `COPILOT_CONTEXT.md` (the "One colour label per note and
per folder" bullet is the shipped behaviour), `tag-system-roadmap.md` (the
`#tag` taxonomy this feature deliberately does **not** merge with).

---

## 0. What a label is, and is not

A label is **one colour per note or folder**, drawn on the browser row as a
10 dp dot at the trailing edge or — since L9 — as a 3 dp stripe on the
leading edge, whichever the user picked in settings, assigned in two taps
from the row's long-press sheet or in bulk from selection mode. It is
pre-attentive differentiation — "the red one" — nothing more.

Labelling is **not an edit**: a label write moves the row's HLC and version
(so it syncs) but leaves `updated_at` alone, so an old note that gets a
colour stays where it was in the "last updated" sort and its row keeps its
date. Every other write in the two DAOs bumps `updated_at`, including
reorder; labels are the deliberate exception (review decision, 2026-09-12).
For the same reason a label write raises `NoteChangeType.labelled` /
`FolderChangeType.labelled`, which the search index and the folder-name
index ignore.

- **Not Finder's tags.** Finder items carry many *named* tags; that is a
  taxonomy, and ANTA already has one in the inline `#tag` syntax
  (`docs/tag-system-roadmap.md`). Two tag systems would compete. One colour
  per item, always.
- **Not a pin.** A pin changes *order*; a label changes *appearance*. The
  column shape (`INTEGER NOT NULL DEFAULT 0`) would suit a pin too, but that
  is a separate decision the owner has not taken (§6).
- **Not a tint.** The dot or the stripe is the only coloured pixel. The
  approved nav mock carries exactly one accent (`primary`), and a second hue
  on the folder glyph is documented as the thing that broke it
  (`AppColors.folderIcon`). A label never tints the glyph, the row, or any
  chrome.

## 1. Decisions (taken 2026-09-12, do not revisit)

| Id | Question | Decision |
| --- | --- | --- |
| L1 | Placement | Study A: trailing dot. Note rows after the title column, before the reorder handle; folder rows before `RowCountChevron` / the handle. Nothing left of the title ever moves. |
| L2 | Palette | Seven fixed hues — red, orange, yellow, green, teal, blue, pink — each with a light and a dark value in `AppColors.labelColor`. No purple (the accent, reads as "selected"), no grey (vanishes on `rowGroup`). 1 px ring at 10 % of the opposite tone so yellow reads. |
| L3 | Cardinality | One label per item. |
| L4 | Folders | Yes, same column, same picker. |
| L5 | Storage | `label INTEGER NOT NULL DEFAULT 0` on `notes` and `folders`, enum index = storage value, **append-only enum**. Exported as the enum *name* in backups and archives, additive key, no format bump. |
| L6 | Names | Phase 2 (Slice D): optional per-colour name in settings, no schema. |
| L7 | Pin | Deferred; separate decision (§6). |
| L8 | Swatch strip width | Eight cells divide the strip's width equally, 48 dp tall — eight fixed 48 dp targets overflowed a 360 dp phone (found in the Phase 1 review). |
| L9 | Rendering style (2026-09-12, owner) | Two styles behind Settings → Browsing → "Label style": **dot** (Study A, default) and **edge stripe** (Study D: 3 dp bar on the row's leading edge, inset 8 dp top and bottom, right corners rounded 3 dp, left edge clipped by the group corner). `LabelStyle { dot, stripe }` persisted by name in `SettingsKeys.labelStyle`, published through `LabelAppearance.style` (a `ValueNotifier`) by `LabelAppearanceService` on the `DatabaseLifecycle` reset contract; primed in `main.dart` before the first frame, re-primed by the browser's `_loadSettings` and after a backup restore; in the backup allow-list. `ContentRowShell.edgeStripe` draws the bar; `LabelRowDecoration.resolve` is the one place the three rows decide dot-or-stripe; only labelled rows subscribe. Storage, assignment, export and sync are untouched by the style. |

## 2. Phase 1 — shipped (do not redo)

- `ItemLabel` (`lib/models/item_label.dart`): `none, red, orange, yellow,
  green, teal, blue, pink`; `storageValue` (= index), `storageName` (= name),
  `fromStorage(int?)`, `fromName(String?)` — both tolerant, unknown → `none`;
  `assignable` = all but `none`.
- Schema **v39** `DatabaseSchema.v39ItemLabels`, `_migrateV38ToV39`: two
  guarded `ALTER TABLE … ADD COLUMN label INTEGER NOT NULL DEFAULT 0`, no
  index, no backfill (0 is what every pre-v39 row meant).
- `NoteMetadata.label` / `Folder.label` with `copyWith`, `props`, JSON
  (`JsonKeys.label` — the constant already existed for shortcut labels).
- DAO: `createNote`/`importNote`/`createFolder`/`importFolder` take
  `label:`; `updateNoteLabel` / `updateFolderLabel` (read row, fresh HLC,
  `version + 1`, **tombstones refused**); `updateLabelForNotes` /
  `updateLabelForFolders` (**one** `UPDATE … WHERE id IN (…) AND
  is_deleted = 0`, `version = version + 1` in SQL); `FolderDao.getFoldersByIds`;
  `mergeNote` / `mergeFolder` carry `label` in **both** branches;
  `fullTextSearch`'s hand-built `Note(...)` reads the column.
- Repository → service → bloc: `setLabel` / `setLabelForMany`,
  `setNoteLabel` / `setLabelForNotes`, `setFolderLabel` / `setLabelForFolders`,
  events `SetOptimizedNoteLabel` / `SetOptimizedNotesLabel` /
  `SetOptimizedFolderLabel` / `SetOptimizedFoldersLabel` (each ends in a
  `RefreshNotes` / `RefreshFolders`). Separate from the `Update…` events on
  purpose: a colour cannot affect the duplicate-name check or the search
  re-index.
- UI: `LabelDot` (`lib/widgets/label_dot.dart`, `RowMetrics.labelDotSize`
  = 10, `Semantics` label "<Colour> label", `ItemLabelL10n.displayName`);
  `LabelSwatchStrip` (`lib/widgets/label_swatch_strip.dart`, clear swatch
  with a diagonal slash then the seven, current value ringed in `primary`);
  `showRowActionSheet(headerBuilder:)` (takes the **sheet's** context so a
  pick can pop it); `NoteRow`, `FolderRow`, `SearchResultRow` draw the dot;
  `SelectionActionBar.onLabel` is the bar's first action (`_Action` padding
  24 → 16 so four fit at 360 dp) → `_labelSelected` in the browser page
  opens its own modal sheet padded `max(viewInsets, viewPadding)`.
- Backup (`BackupService`, version **still 7**) and archives
  (`ImportExportService.archiveVersion` **still 1**): additive `label` key
  on note and folder maps, `_folder.json` and the per-note JSON export;
  markdown/text exports carry no metadata and therefore no label.
- l10n: `labelAction`, `labelSelected`, `labelNone`, `labelRed` … `labelPink`,
  `labelSemantics({color})` in en/de/ro.
- Tests: `test/database/item_label_migration_test.dart`,
  `item_label_dao_test.dart`, `test/models/item_label_test.dart`,
  `test/services/backup_service_item_label_round_trip_test.dart`, and the
  "colour label dot" / "label swatch strip" / "row action sheet" groups in
  `test/widgets/content_rows_test.dart` (incl. the 360 dp strip test).
  Suite at hand-off: **4,435 passed / 7 skipped / 0 failed**.
- The style setting (L9) added `test/services/label_appearance_service_test.dart`,
  `test/widgets/settings_page_test.dart` (new harness) and the stripe groups in
  `content_rows_test.dart`; the in-depth review of 2026-09-12 (§7) added the
  bloc, archive, page-sheet, action-bar matrix and DAO-semantics tests.

## 7. In-depth review (2026-09-12)

Four read-only passes (data layer; widgets/a11y/theming; services, blocs
and lifecycle; tests, l10n and docs) over `4b525b9` plus the style setting.
Fixed in the tree:

- **Labelling no longer bumps `updated_at`** and writing the label a row
  already has is a no-op (single and bulk; bulk returns the count of rows
  that actually changed via `AND label <> ?`). Before, bulk-labelling forty
  notes of which thirty were already red re-dated and re-versioned all forty
  and shuffled them to the top of the default sort.
- **`NoteChangeType.labelled` / `FolderChangeType.labelled`**: the search
  index no longer re-reads note bodies after a label change, and the
  folder-name index no longer rebuilds.
- **Stripe accessibility**: `MergeSemantics` around the stripe `Stack` so a
  stripe row is one screen-reader node like a dot row; the stripe carries the
  dot's 1 px ring.
- **Rows always subscribe** to `LabelAppearance.style`, so the root widget
  type does not change when a label appears and the row is rebuilt in place
  rather than remounted (a remount would drop a drag in flight over a folder).
- **Swatch strip**: the `InkWell` fills the 48 dp cell (it used to hit-test
  only the 32 dp circle, leaving dead gaps between swatches); the tooltip no
  longer duplicates the semantics label.
- **`SelectionActionBar`**: each action is `Flexible` with a one-line
  ellipsised label, so German at 320 dp under large text scale cannot
  overflow.
- **`LabelAppearanceService`**: a `_create()` that a `reset()` overtakes
  discards itself (generation counter); a failed read publishes nothing;
  `setStyle` always writes (so "Reset to defaults" leaves an explicit row);
  `AllNotesPage` re-primes it like the browser does; the settings-page reset
  calls it last.
- **Archives**: `label` is read with an `is String` guard so a non-string
  value in a hand-edited note JSON or `_folder.json` cannot abort an import.
- **Bulk sheet** rings the selection's common label instead of always
  "no label".

Known and left, with the reason:

- **Light-mode yellow and orange — DONE 2026-09-13.** Darkened to `#A8890E`
  (3.19:1) and `#D27318` (3.22:1) against the light row surface, level with
  green and teal; `test/constants/label_contrast_test.dart` computes WCAG
  luminance for all seven hues in both themes against `rowGroup` and pins
  the 3:1 floor, so a future palette tune-up stays free as long as it
  clears it. The dark values were untouched.
- **Bulk actions flash the list — DONE 2026-09-13.** `OptimizedFolderBloc`
  now has the note bloc's `_loadLoadedPages` and `_onRefreshFolders` reloads
  `pageSize × loadedPages` in place — no `Loading` state, no snap to page 1
  — unless the refresh targets a parent other than the one on screen (then
  the full load, as before). `_onLoadMoreFolders` reads at the list's own
  page size and advances the counter only after a successful read; both
  blocs' load-more bail if a refresh moved the state under them. On the page,
  bulk move, drop-on-folder, pull-to-refresh, the post-import reload and the
  return from a created note go through `_refreshData()` (the two refresh
  events) instead of `_loadData()`. Pinned by `optimized_folder_bloc_test.dart`
  "refreshing in place" and the browser page's "bulk actions leave the list
  where it was" (which also records the bloc stream, because the spinner
  frame is a race the frame sweep alone cannot force).
- **N+1 refresh fan-out — DONE 2026-09-13.** Both blocs coalesce: every
  `add(Refresh…)` — the handlers' own and `_onExternalChange`'s — goes
  through `_scheduleRefresh(id)`, which collects ids and flushes one event
  per distinct parent/folder on a `Timer(Duration.zero)` (a microtask does
  not work: broadcast-stream events arrive one microtask apart, so it
  coalesced nothing), guarded by `isClosed` and cancelled in `close()`. Ten
  changes on one parent are one reload. `bloc_concurrency` is not a
  dependency and was not added.
- **Drop-target border** paints over the stripe while a drag hovers a
  labelled folder; the primary border is the stronger signal at that moment.
- The group's 14 dp corner shaves at most 1.35 dp off the stripe's tip on
  end rows; middle rows are square. Accepted.
- Title width differs by ~24 dp between the two styles (the dot takes
  trailing space, the stripe does not), so flipping the setting re-ellipsises
  long titles. Within L1.
- `labelAction` and `labelSelected` are the same word in all three locales;
  kept separate in case the bar label gains a count.

**Owed from Phase 1: the Android device pass** (§5.2). Widget tests cannot
see the keyboard or the gesture bar.

## 3. Facts from the tree (re-grep before editing)

Search:
- `SearchScopeChips` — `lib/widgets/search_surface.dart:194-276`. Exactly two
  `ChoiceChip`s in a `Wrap`; `preferredHeight = 48 + AppSpacing.md` (:199) is
  what the in-place host reserves as the bar's `bottom`
  (`lib/widgets/search_field_app_bar.dart:77-79`). **The chips row must stay
  one fixed height** — a `Wrap` that folds to a second line would change a
  `PreferredSize` the sliver bar has already committed to. The standalone
  route builds the same widget at `search_surface.dart:47`. At the root
  browser the chips are hidden (no second scope to offer) — grep
  `SearchFieldAppBar(` in `optimized_folder_content_page.dart` for the
  `null`/conditional that does it.
- `SearchBloc` — `lib/bloc/search/search_bloc.dart`: `_runQuick` :185,
  `_runFull` :209, `_emitRecents` :239 (idle = `loadNotesPaginated(pageSize:
  recentsPageSize, sortOrder: updatedDesc)`), `_onScopeChanged` :152 (idle
  only records the scope; quick/full re-run), `_generation` guards every
  emit. Events in `search_event.dart` (`SearchOpened`, `SearchQueryChanged`,
  `SearchSubmitted`, `SearchScopeChanged`, `SearchCleared`); state in
  `search_state.dart` (`scope, query, phase, recents, titleHits,
  contentHits, folderPaths, isSearching`).
- `FolderSearchService` — `lib/services/folder_search_service.dart`:
  `SearchFilter` :200-245 (`folderIds`, dates, lengths; `matches(NoteMetadata)`
  :221), `quickSearch` :672 (**returns `[]` for an empty query** at :681;
  reads one unscoped page of `_quickSearchPageSize` = 300 and filters in
  memory), `search` :593 (indexed, takes `filter:`), `_loadAllNoteMetadata`
  :525. Every result is built from fresh `NoteMetadata`, so the label is
  never stale here.
- `SearchResultRow` (`search_surface.dart:280+`) already draws `LabelDot`.

Sort:
- `NotesSortOrder` — `lib/services/note_storage_service.dart:10-19`
  (`updatedDesc … positionDesc`), mapped by `_mapSortOrder` :404-420 to
  `(NoteSortField, bool ascending)`; `NoteSortField { title, createdAt,
  updatedAt, position }` at `lib/database/daos/note_dao.dart:~870`;
  `getNotesPaginated` :84-130 builds `orderBy` per field, **always ending on
  `id`** (page-boundary tiebreak — keep it). `FoldersSortOrder` and
  `FolderSortField` are the folder twins (`folder_storage_service.dart:8-15`,
  `folder_dao.dart`).
- Persistence: per folder, `folders.noteSortOrder` / `subfolderSortOrder`
  hold the **enum name**; `_parseNotesSortOrder` / `_parseFoldersSortOrder`
  (`optimized_folder_content_page.dart:538-552`) fall back to the default on
  an unknown name, so an older build reading a newer name degrades safely.
  `SettingsKeys.defaultNotesSortOrder` (an int) has a getter/setter in
  `SettingsService` :395-404 but **no reader in the pages** — the per-folder
  value is what the browser uses.
- UI: `_showNoteSortOptions` :1538-1618 (six `_buildSortOption`s),
  `_showFolderSortOptions` just above it, `_sortLabel` :1681-1701 (exhaustive
  `switch` — a new enum member fails to compile until it is named here),
  `FolderOverflowMenu.sortLabel` shows the result.
- Indexes: `lib/database/migrations/database_indexes.dart` — `idx_notes_folder
  (folder_id) WHERE is_deleted = 0` :52, `idx_notes_updated (updated_at DESC)
  WHERE is_deleted = 0` :58, `idx_notes_position` :32-37. Every index is
  defined once on `DatabaseIndexes` and called from **both**
  `createAllIndexes()` and the migration that introduced it;
  `test/database/schema_parity_test.dart` scrapes `CREATE INDEX` names and
  fails if a fresh database lacks one. `test/database/query_plan_test.dart`
  :68 asserts `USE TEMP B-TREE FOR ORDER BY` is absent for the paginated
  sorts it covers (:82-125).

Editor:
- `NoteOverflowMenu` — `lib/widgets/note_overflow_menu.dart`: `_NoteMenuAction
  { openFolder, editTitle, move, share, delete, settings }`, rows built by
  `_row(...)` with `AppTheme.menuItemHeight` / `menuIconSize`. Built by the
  editor at `lib/pages/optimized_note_editor_page.dart:1839-1848`.
- The editor holds `widget.metadata` (nullable — a brand-new note has none
  until `NoteSaveCoordinator`'s early create) and reads fresh metadata through
  `GetIt.I<NoteStorageService>().getNoteMetadata(noteId)` (:2208). It
  dispatches to the app-wide `OptimizedNoteBloc` (:361, :831).

Settings:
- JSON-map setting precedent: `SettingsKeys.markdownCustomColors`
  (`settings_keys.dart:67`) read/written in `settings_service.dart:286-295`,
  decoded at :1578, listed in the bulk-read key list at :1468.
- Live palette precedent for something rows read on every build without a
  settings round-trip: `CalendarPalette.listenable` (`ValueNotifier<int>`,
  `lib/constants/calendar_palette.dart:32`) fed by `CalendarPaletteService`
  (`getInstance()` + `reset()` on the `DatabaseLifecycle` contract).
- `BackupService._exportSettings` (`backup_service.dart:188-230`) is an
  explicit **allow-list**; a new key must be added or it does not round-trip.
  Restore writes every carried key back verbatim (:335-337).
- Settings page sections: `_sectionStartup / Browsing / Editor / AutoSave /
  Feedback / Deprecated` (`settings_page.dart:34-39`); rows are
  `SettingsEntry(keywords: …)` so they are searchable.

Rows and sheets:
- `_labelSelected` (`optimized_folder_content_page.dart:~790-870`) builds its
  own handle + title + `LabelSwatchStrip` sheet. Slice C extracts it.
- `NoteRow._showActionSheet` / `FolderRow._showActionSheet` pass
  `headerBuilder:`; the pick pops the sheet, then dispatches only if the value
  changed.

## 4. Slices

Order: **C → B → A → D**. C is the smallest and extracts the picker sheet
that A's empty state and D's naming will reuse; B is pure data + sheet; A is
the only one that touches the search bloc; D is optional polish and is last
so its names can flow into A's chips and B's sort rows without a second pass.

Execution model for every slice: one Opus implementation agent with the
prompt below (pasted verbatim, plus the standing preamble from §5.1), then
a Fable review of the full diff before anything is committed. The brief
always says: do not touch, stash or commit anything you did not write; tests
are required; no new markdown docs; `dart analyze lib` + `dart analyze test`
+ `flutter test` counts in the report.

### Slice C — Label from the editor (and one shared picker sheet)

**Why:** the editor is where the user is when a note turns out to matter; a
trip back to the browser to colour it is three taps too many. It also
removes a duplication Phase 1 left: the bulk sheet in the page and the
row-sheet header are two ways to show the same strip.

**Scope:**
1. Extract `_labelSelected`'s sheet into `Future<ItemLabel?>
   showLabelPickerSheet(BuildContext context, {required ItemLabel value})` in
   `lib/widgets/label_swatch_strip.dart`: handle, title `l10n.labelAction`,
   `Divider`, the strip, bottom padding `max(viewInsets.bottom,
   viewPadding.bottom)`. Returns the pick, `null` on dismiss. `_labelSelected`
   calls it with `ItemLabel.none` and keeps its bloc dispatch + `_selection.clear()`.
2. `NoteOverflowMenu` gains `onLabel` (`_NoteMenuAction.label`, icon
   `Icons.label_outline`, label `l10n.labelAction`) placed **after Move and
   before Share** — appearance actions together, sharing/deleting after. It
   is `null`-able: when null the row is not built, and the editor passes
   null while `widget.noteId == null` and the early create has not happened
   (a note with no id has no row to label).
3. Editor handler `_labelNote`: read the current label through
   `NoteStorageService.getNoteMetadata(noteId)` (never trust
   `widget.metadata`, which is the value at push time), open the sheet, and
   on a changed pick dispatch `SetOptimizedNoteLabel` to the app-wide
   `OptimizedNoteBloc` — the browser beneath refreshes through the same
   event Phase 1 wired. No new service call.
4. l10n: nothing new unless the menu needs a distinct string (it does not —
   `labelAction` is the row).

**Tests:** `test/widgets/optimized_note_editor_page_test.dart` — the overflow
menu shows a Label row for a saved note and not for a brand-new one; picking
a swatch dispatches `SetOptimizedNoteLabel(noteId, label)` exactly once and
picking the current value dispatches nothing. `content_rows_test.dart` or a
new `label_picker_sheet_test.dart` — the sheet returns the pick, returns null
on barrier dismiss, and pads by `viewPadding` when `viewInsets` is zero (fake
both through `tester.view`). Update the page test's selection-bar group only
if its finder relied on the inline sheet.

**Shipped 2026-09-13 (Opus implementation, Fable + Opus review).** As
scoped, with four deviations worth knowing:
- `_labelSelected` passes `_commonLabelOf(items)`, not `ItemLabel.none` —
  point 1 above was stale; the bulk sheet has ringed the selection's common
  colour since the Phase 1 review and that stayed.
- The `OptimizedNoteCreated` branch of the editor's bloc listener now ends in
  a `setState`: nothing else rebuilds the app bar when the early create
  lands (`hasChanges` flipped before the id arrived), so without it the Label
  row stayed missing until an unrelated rebuild. Verified by removing the
  line: the "appears once the early create lands" test fails.
- `NoteStorageService.getNoteMetadata` reads a **tombstone as null**. The
  DAO's `getNoteById` does not filter `is_deleted`, so an editor still
  mounted over a note deleted elsewhere (a second editor for the same note
  through a `[[wiki link]]` chain, or a sync merge) opened the sheet and had
  its pick refused silently by `updateNoteLabel`; `_labelNote`, `_moveNote`
  and `_showExportFormatDialog` now hit their `noteNotFound` branch instead,
  and `FolderSearchService._refreshStaleNotes` drops such a note from the
  index rather than re-adding it. `loadNoteWithContent` is unchanged.
- `_labelNote` does **not** flush saves before reading: a label is not an
  edit and `updateNote`'s partial companion never carries `label`, so an
  auto-save in flight cannot stomp the write.
Tests: six editor-page cases in "the app bar's leading pair and its menu",
`test/widgets/label_picker_sheet_test.dart` (six), one service case for the
tombstone read. Left alone on purpose: the sheet's drag handle is now the
fifth verbatim copy of the 40×4 handle (`bar_switcher_sheet`,
`content_rows`, `move_history_sheet`, `pairing_sheet`) — a `SheetHandle`
widget is a separate tidy-up; and `?? widget.noteId` after
`_saves.effectiveNoteId` is dead (the coordinator seeds the id) but matches
the page's idiom.

**Paste-ready prompt:**

> Implement Slice C of `docs/colour-labels-roadmap.md` in
> D:\Alex\Programare\repos\anta\frontend\anta. Read that document's §0–§3
> and the Slice C block first, then `CLAUDE.md`, the `anta-context` and `l10n`
> skills, and the "One colour label per note and per folder" bullet of
> `COPILOT_CONTEXT.md`. Deliverables: (1) `showLabelPickerSheet` in
> `lib/widgets/label_swatch_strip.dart` and `_labelSelected` rewritten on top
> of it with no behaviour change; (2) `NoteOverflowMenu.onLabel` (nullable,
> row omitted when null, after Move, before Share); (3) the editor's
> `_labelNote` reading fresh metadata via `NoteStorageService.getNoteMetadata`
> and dispatching `SetOptimizedNoteLabel` only on a changed pick, passing
> `onLabel: null` while the note has no id. The row sheet header in `NoteRow`
> / `FolderRow` stays as it is. Tests as listed in the slice. Do not touch
> sort, search, or settings. Report: files, the editor test names, `flutter
> test` counts, anything you decided that the slice did not cover.

### Slice B — Sort by label

**Why:** once a folder has a handful of labelled notes, "the red ones
together" is the first thing a user reaches for, and the sort sheet is where
the browser already answers that kind of question.

**Scope:**
1. `NotesSortOrder.labelAsc` **appended** (palette order: none last? — no:
   **labelled first, in palette order, unlabelled last**, because the user
   sorted by label to see the labelled ones), and `FoldersSortOrder.labelAsc`
   likewise. No `labelDesc` — reversing a palette is not a thing anyone asks
   for. Names are what `folders.noteSortOrder` persists; an older build parses
   them as the default, which is the safe degradation `_parseNotesSortOrder`
   already gives.
2. `NoteSortField.label` / `FolderSortField.label`. In `getNotesPaginated`
   the ordering is `CASE WHEN label = 0 THEN 1 ELSE 0 END, label,
   updated_at DESC, id` (a `CustomExpression` for the first term is fine;
   the ordering **must still end on `id`**). Folders: same shape with
   `LOWER(name)` in place of `updated_at DESC` — check what
   `FolderSortField.name` already orders on and reuse that expression.
3. Query plan: run `EXPLAIN QUERY PLAN` for the new note sort inside a folder
   through `queryPlan()` in `test/database/support/db_test_support.dart`. If
   it reports `USE TEMP B-TREE FOR ORDER BY` **and** the existing per-folder
   sorts in `query_plan_test.dart` do not, add a partial composite index
   `idx_notes_folder_label ON notes(folder_id, label, updated_at DESC) WHERE
   is_deleted = 0` as a `DatabaseIndexes` method called from
   `createAllIndexes()` **and** from a new `_migrateV39ToV40` (schema v40
   `v40LabelSortIndex`), and pin it with a plan test. If the existing sorts
   already sort in memory for a folder, do **not** add an index — match the
   neighbours and say so in the report.
4. Sort sheets: a seventh `_buildSortOption` in `_showNoteSortOptions` and a
   fourth in `_showFolderSortOptions`, leading icon `Icons.label_outline`,
   title `l10n.sortByLabel` ("Label" / "Etikett" / "Etichetă"); `_sortLabel`
   gains the case (the exhaustive `switch` forces it). `_sortNotesBy` /
   `_sortFoldersBy` need nothing — they persist `order.name`.
5. `SearchBloc._emitRecents` and `AllNotesPage` keep `updatedDesc`; a global
   label sort is Slice A's chip, not a sort.

**Tests:** `test/database/note_pagination_test.dart` — labelled notes come
first in palette order, unlabelled last, ties broken by `updated_at DESC`
then `id`, and a page boundary never re-serves a row (extend the existing
boundary test with the new field); the folder twin. `query_plan_test.dart`
per point 3. `optimized_folder_content_page_test.dart` "the overflow menu"
group — the sort sheet offers Label, choosing it persists `labelAsc` to the
folder's `noteSortOrder`, and the menu's trailing sort label reads "Label".
A `schema_parity_test` run is mandatory if an index was added.

**Shipped 2026-09-13 (Opus implementation, two-reviewer pass, fixes).**
- **No index, no schema v40.** `EXPLAIN QUERY PLAN` for the label sort in a
  folder is `SEARCH notes USING INDEX idx_notes_position (folder_id=?)` +
  `USE TEMP B-TREE FOR ORDER BY` — byte-for-byte the plan the `title` and
  `updated_at` sorts have always had, which is point 3's "match the
  neighbours" case. A trial `idx_notes_folder_label` changed nothing: the
  `CASE` leading the ORDER BY is not indexable. `query_plan_test.dart` pins
  the shape *and* that the neighbour sort has the same one, so if `title`
  ever becomes index-ordered the label sort is owed the same.
- `_unlabelledLast` is a `CustomExpression<int>` (`CASE WHEN label = 0 THEN 1
  ELSE 0 END`), one private const per DAO (they name different tables'
  columns; importing one DAO from the other would be worse). `ascending` is
  deliberately not consulted for the label field — there is no `labelDesc`.
- Folders order by plain `name` (what `FolderSortField.name` already used,
  not `LOWER(name)`), then `id`. **The label sort is the only folder sort
  that ends on `id`** — the four older ones have no tiebreak at all, a
  pre-existing gap left alone so shipped orderings do not move; worth its
  own follow-up.
- **Both sort sheets scroll** (`SafeArea > SingleChildScrollView > Column`,
  `showRowActionSheet`'s precedent): seven rows (≈448 dp) overflowed
  `showModalBottomSheet`'s 9/16 cap on a 360×800 phone, and the widget
  tests at 2400 dp tall could not see it. Pinned at 360×640.
- Tests: `note_pagination_test.dart` "sorting by colour label" (3),
  `folder_pagination_test.dart` (new, 4), `query_plan_test.dart` (3),
  `query_count_test.dart` (1), two sort-sheet cases in the browser page
  test (one at 360×640). `volume_benchmark_test.dart`'s exhaustive
  `_column` switch gained the case.

**Paste-ready prompt:**

> Implement Slice B of `docs/colour-labels-roadmap.md` in
> D:\Alex\Programare\repos\anta\frontend\anta. Read that document's §0–§3
> and the Slice B block, then `CLAUDE.md` and the `anta-context`,
> `drift-migrations` and `l10n` skills. Deliverables: `NotesSortOrder.labelAsc`
> and `FoldersSortOrder.labelAsc` (appended, never inserted), `NoteSortField.label`
> / `FolderSortField.label` with the `CASE`-led ordering that ends on `id`, the
> two sort-sheet rows and the `_sortLabel` cases, `sortByLabel` in en/de/ro,
> and the index **only** under the condition in point 3 (both creation paths,
> schema v40, parity + plan tests). Run `dart run build_runner build
> --delete-conflicting-outputs` if any table/DAO annotation changed. Tests as
> listed. Do not touch search or the editor. Report: the `EXPLAIN QUERY PLAN`
> text for the new sort with and without a folder, whether you added the
> index and why, `flutter test` counts.

### Slice A — Filter by label in search

**Why:** the dot tells rows apart inside one folder; "everything red, from
anywhere" is the cross-folder question, and search is the surface that
already crosses folders. This is Finder's sidebar tag, delivered as a chip.

**Scope:**
1. State: `SearchState.labels` (`Set<ItemLabel>`, empty = no filter) and
   `SearchState.labelsInUse` (`List<ItemLabel>`, palette order). Event
   `SearchLabelsChanged(Set<ItemLabel>)`. `SearchOpened` and `SearchCleared`
   load `labelsInUse` through a new `NoteStorageService.labelsInUse({Set<String>?
   folderIds})` → `NoteDao.labelsInUse()` = `SELECT DISTINCT label FROM notes
   WHERE is_deleted = 0 AND label != 0` (one statement; the folder scope is
   applied in memory only if the scoped subtree is small — otherwise show the
   global set, a chip that yields nothing is not a bug).
2. Semantics of a selected label: it is a **filter on whatever pass is
   showing**, and it also makes the **empty query meaningful**. With
   `labels` non-empty and no query, the bloc runs the quick pass with an
   empty query instead of `_emitRecents`, and `quickSearch` lifts its
   empty-query early return **only when a label filter is present** (an
   empty query with no filter still returns `[]`). Results are the labelled
   notes in the scope, `updatedDesc`, listed under the title-hits section
   with no highlight. `SearchFilter` gains `labels` and `matches` checks it;
   `quickSearch` takes `labels:` the way it takes `folderIds:`. Clearing the
   last label with an empty query returns to idle recents.
3. Chips: `SearchScopeChips` becomes **one horizontally scrollable row**
   (`SingleChildScrollView(scrollDirection: horizontal)` with the same
   padding) instead of a `Wrap`, so `preferredHeight` is honest at any
   count: the two scope chips, then — only when `labelsInUse` is non-empty —
   a 1 px `rowDivider` separator 18 dp tall, then one compact `FilterChip`
   per in-use label showing a `LabelDot` at 12 dp and no text (semantics
   label = the colour's display name; `showCheckmark: false`; selected =
   `primaryContainer` fill like the scope chips). Multi-select is OR.
   At the root browser, where the scope chips are hidden, the row is shown
   **iff** `labelsInUse` is non-empty — find the conditional that hides the
   `bottom` and extend it; the standalone `SearchPage` shows the same widget.
4. Section header: when a label filter is active and the query is empty, the
   results section label reads the selected colours' names joined by " · "
   with the count (`labelledNotesHeader` ICU plural, en/de/ro); with a query
   the existing Titles / In text headers stay.
5. `AllNotesPage` does not learn labels here (§6).

**Tests:** `test/bloc/search_bloc_test.dart` — opening loads `labelsInUse`;
selecting a label with an empty query yields the labelled notes and phase
`quick`; adding a query narrows within the label; clearing the last label
with an empty query returns to idle recents; the `_generation` guard still
drops a stale pass (extend the existing race test with a label change).
`folder_search_service_test.dart` (or the file that covers `quickSearch`) —
empty query + label returns matches, empty query alone still returns `[]`,
`SearchFilter.matches` honours `labels`. Widget: `search_surface` /
`optimized_folder_content_page_test.dart` "search hosted in place" group —
the chip row height equals `preferredHeight` with seven labels in use at
360 dp (no overflow, scrolls), chips absent when nothing is labelled, root
shows the row only with labels in use, tapping a dot chip dispatches
`SearchLabelsChanged`.

**Shipped 2026-09-13 (Opus implementation, two-reviewer pass, fixes).** The
scope above is what shipped, with these deviations — the code is the truth:
- **The label-only listing is its own DAO query, not `quickSearch`'s
  empty-query rule.** Point 2's plan read `quickSearch`'s 300-newest page
  and filtered in memory, which builds 300 rows to show 50 and cannot see a
  labelled note older than the 300 newest (worse inside a folder scope).
  `NoteDao.labelledNotes({labels, folderIds, limit})` (`WHERE is_deleted = 0
  AND label IN (…) [AND folder_id IN (…)] ORDER BY updated_at DESC, id LIMIT
  ?`) and `countLabelledNotes` share one WHERE writer; unscoped the plan is
  `SCAN notes USING INDEX idx_notes_updated` + a temp b-tree for the `id`
  tiebreak only, scoped it leads with `idx_notes_position (folder_id=?)`
  and sorts the survivors (pinned as-is). `NoteStorageService.labelledNotes
  → LabelledNotes(notes, total)`, `FolderSearchService.labelledNotes` maps
  to `SearchResult(matches: const [])`. `quickSearch('')` returns `[]`
  again unconditionally; `labels:` on `quickSearch` and `SearchFilter.labels`
  (OR, empty = no filter, applied before the `limit` cut) cover the typed
  passes. The bloc's `_runLabelled` asks for `recentsPageSize` (50) and puts
  the rows in `titleHits`; `SearchState.labelledTotal` carries the COUNT so
  the header says how many exist, not how many are listed.
- **`labelsInUse` is scoped in SQL** (`AND folder_id IN (subtree)`) — the
  bloc resolves `_folderIdsFor(scope)` once and hands the same set to the
  pass and to `labelsInUse`, run in parallel (`Future.wait`); reloaded on
  open, clear, submit, scope change and the hosts' way-back refresh (a
  `SearchQueryChanged` whose query equals the one in state), **never on a
  fresh keystroke** (zero extra statements on the typing path, pinned). A
  stale set cannot overwrite a fresh one: `labelsInUse` is applied only if
  `state.scope` still equals the scope it was read for.
- **A chip tap inside the keystroke debounce filters the text on screen.**
  `SearchLabelsChanged` leaves `_pendingQuery` alone (the `SearchScopeChanged`
  rule, not the `SearchCleared` one) and `_onLabelsChanged` runs
  `_pendingQuery ?? state.query`, then nulls it so the debounced keystroke
  fires into nothing — one pass, with the text *and* the colour. The first
  implementation dropped the keystroke and listed "everything red" under a
  field that said "p".
- **The filter does not outlive the surface.** `SearchOpened({keepLabels})`:
  `InPlaceSearchController.open()` clears the colours (as it clears the
  query); `refresh()` and `SearchPage.didPopNext`, which re-dispatch
  `SearchOpened` for an empty query, pass `keepLabels: true`. `SearchCleared`
  (field emptied) keeps them — emptying the field with Red picked is how
  "everything red" is asked.
- **The root's chip row is there on the first frame.** `SearchLabelsPrimed`,
  dispatched from `InPlaceSearchController`'s constructor (the in-place
  hosts build the bloc at page mount), reads `labelsInUse` before search
  can open; without it `SearchFieldAppBar.bottom` flipped from null to 60 dp
  under a visible bar. `SearchPage` is not primed (it opens at once).
- **Chips**: `SearchScopeChips` is a fixed-height (`preferredHeight − md`)
  horizontal scroller; `folderScope` is nullable and `shows(folderScope:,
  labelsInUse:)` is the one predicate both hosts use for the root rule. A
  selected dot chip wears the swatch strip's 2 dp `primary` ring (the dot on
  `secondaryContainer` falls below 3:1 for yellow/orange/green — the ring
  carries the selection instead of fill contrast); chips stay 40×40. Dot
  semantics inside a chip are the colour name alone.
- **Header**: names joined with ", ", then " · N notes" from the ICU message
  (`labelledNotesHeader`, ro carries `few`); label-only rows show path ·
  date like the recents they replace (`showDate: state.isLabelOnly`).
- **The selection follows the offer** (emulator pass, 2026-09-13): a colour
  can stop being on offer while still selected — the only red note was
  relabelled from the editor and the way-back refresh dropped the red chip,
  leaving "no results" under a row with nothing selected and no way to
  clear it; a scope change to a folder where nothing wears the colour does
  the same. Wherever `labelsInUse` is applied, `_dropColoursNoLongerOffered`
  intersects `labels` with it and sends the pruned set through
  `SearchLabelsChanged`, so the right pass runs (recents once nothing is
  left). Two bloc tests; four older tests now declare the picked colour as
  in use, which is the only way a chip exists.
- **The root's row is laid out from the leading edge** (emulator pass): a
  Material 3 `AppBar` centres a `bottom` narrower than itself, so the
  shrink-wrapped row of two or three dot chips floated to the middle while
  every other host was left-aligned; the row's `SizedBox` now takes
  `double.infinity` width and the root test asserts the first chip starts at
  `AppSpacing.lg`.
- `ItemLabel.inPaletteOrder(Iterable)` is the one palette-order filter
  (DAO and header); `FolderSearchService.quickHitLimit` is the one 10.
- Tests: `search_bloc_test.dart` groups "label filtering" and "leaving and
  reopening", `folder_search_service_labels_test.dart` (new),
  `query_count_test.dart` "labels in use" + "the colour listing",
  `query_plan_test.dart`, `search_surface_header_test.dart` (new: the header
  renders the total over fewer rows), browser page "search hosted in place"
  cases (row height at 360 dp with seven colours, root rule, first-frame
  row, toggle dispatch, header), `search_page_test.dart` "colour label
  chips".
- Known: at ~2× text scale the pinned 48 dp row clips the word chips (the
  old `Wrap` clipped inside the same `preferredHeight`, so not a regression).
  The device pass of the row with the keyboard up (§5.2 item 4) is owed.

**Paste-ready prompt:**

> Implement Slice A of `docs/colour-labels-roadmap.md` in
> D:\Alex\Programare\repos\anta\frontend\anta. Read that document's §0–§3
> and the Slice A block, then `CLAUDE.md`, the `anta-context` and `l10n`
> skills, and the "Search is hosted in the browser in place" bullet of
> `COPILOT_CONTEXT.md` — the chips row's fixed `preferredHeight` and the
> one-`CustomScrollView` rule are load-bearing. Deliverables: `SearchState.labels`
> + `labelsInUse`, `SearchLabelsChanged`, `NoteDao.labelsInUse` (one
> statement, pinned by a `StatementCounter` test), `SearchFilter.labels`,
> `quickSearch(labels:)` with the empty-query rule exactly as written, the
> scrollable chip row with dot chips only for labels in use (root included),
> the labelled-results header, en/de/ro strings. Tests as listed. Do not
> touch sort or the editor. Report: how the root's hidden chips were handled,
> the chip row's measured height at 360 dp with seven labels, `flutter test`
> counts.

### Slice D — Named labels (optional polish) — DROPPED 2026-09-13 by the owner

Kept below as the record of what was considered; not to be built unless the
owner reopens it.

**Why:** "Red" means nothing a week later; "Client" does. Names also fix the
accessibility gap of seven hues that yellow/green/orange colour-blind users
cannot tell apart, and give the chips of Slice A and the sort row of Slice
B something to say.

**Scope:**
1. `SettingsKeys.labelNames = 'label_names'` — a JSON object `{ "red":
   "Client", … }` keyed by `ItemLabel.storageName`, missing = default name.
   `SettingsService.getLabelNames()` / `setLabelName(ItemLabel, String?)`
   (empty/whitespace clears), decoded like `markdownCustomColors`, added to
   the bulk-read key list and to `BackupService._exportSettings`'s
   allow-list (a round-trip test is required — the calendar keys are the
   documented example of an omission that silently loses data).
2. A tiny `LabelNames` static facade with a `ValueNotifier<Map<ItemLabel,
   String>> listenable`, filled by a `LabelNameService` singleton on the
   `DatabaseLifecycle` reset contract (copy `CalendarPalette` /
   `CalendarPaletteService`). `ItemLabelL10n.displayName(l10n)` consults the
   facade first, so `LabelDot`'s semantics, the swatch tooltips, Slice A's
   chip semantics and Slice B's sort row all pick the name up with no
   further edits. Rows must not read settings per build — the facade is the
   only reader.
3. UI: a "Labels" row in the Browsing section of the settings page pushing a
   `LabelNamesPage`: seven rows, each a 22 dp `LabelDot`, a `TextField`
   seeded with the current name and hinted with the default, saving on
   submit/blur through the service, max 24 characters (mirror
   `MarkdownColorPalette.maxNameLength`). Clearing restores the default.
   Searchable through `SettingsEntry(keywords:)`.
4. Backup: names ride as a settings key (point 1); labels themselves already
   ride on the rows. No archive change — an archive shares notes, not
   preferences.

**Tests:** service round-trip and `reset()` on database switch;
`backup_service_*_round_trip_test.dart` for the key; a widget test that a
named label's swatch tooltip and dot semantics read the name and revert on
clear; settings page test that the row exists and is searchable.

**Paste-ready prompt:**

> Implement Slice D of `docs/colour-labels-roadmap.md` in
> D:\Alex\Programare\repos\anta\frontend\anta. Read that document's §0–§3
> and the Slice D block, then `CLAUDE.md`, the `anta-context`,
> `drift-migrations` (for the `DatabaseLifecycle` contract) and `l10n`
> skills, and `lib/constants/calendar_palette.dart` +
> `lib/services/calendar_palette_service.dart` as the pattern to copy.
> Deliverables: the `label_names` setting through `SettingsService` +
> `SettingsKeys`, the `LabelNames` facade + `LabelNameService` on the reset
> contract, `displayName` consulting it, the `LabelNamesPage` behind a
> Browsing-section row, the backup allow-list entry, en/de/ro strings, tests
> as listed. Do not change what a label *is* — no schema, no archive change.
> Report: files, how the facade is filled at startup, `flutter test` counts.

## 5. Sequencing, execution model, verification

### 5.1 Standing preamble for every slice prompt

> Run every command from `D:\Alex\Programare\repos\anta\frontend\anta`
> (PowerShell). The tree may hold the owner's own uncommitted work — do not
> touch, revert, stash or commit anything you did not write; never run `git
> commit`, `git stash` or `git checkout`. No new markdown docs. Doc comments
> (`///`) are house style; no other comments. Tests are required.
> Validation before reporting: `dart run build_runner build
> --delete-conflicting-outputs` (if a table/DAO/annotation changed), `flutter
> gen-l10n` (if an ARB changed; `untranslated.txt` must stay `{}`), `dart
> analyze lib`, `dart analyze test`, `flutter test` with exact counts. A
> `sqlite3.dll` lock crash under `flutter test` is transient — rerun once.
> Widget tests run at 800 × 600: any new horizontal strip must also be
> pumped inside a 360 dp `SizedBox` (the Phase 1 swatch strip overflowed
> every real phone and passed every test). Update the labels bullet in
> `COPILOT_CONTEXT.md` and this roadmap's status line in the same change.

### 5.2 Order of operations

1. **Commit Phase 1 first**, on its own, without the owner's
   `event_editor_sheet.dart` / `event_template_editor_sheet.dart` /
   `event_editor_assume_absent_test.dart` edits (those belong to the
   presence work, `presence-assume-absent-v37`).
2. **Phase 1 device pass** (Android, the primary target), before or right
   after that commit:
   - a labelled and an unlabelled note row side by side: the dot is 10 dp,
     vertically centred, the title column did not move;
   - a folder row: dot before the count, count width unchanged;
   - long-press a note → the strip sits above Select, all eight swatches
     visible at the phone's width with **no overflow stripe**, the current
     one ringed; tap a colour → sheet closes, dot appears with no list jump;
   - selection mode → Label → sheet clears the gesture bar (the
     `viewPadding` rule), pick applies to notes **and** folders in one
     refresh, selection exits;
   - light and dark: yellow readable on both row surfaces; TalkBack reads
     "Yellow label" on the dot and the colour names on the swatches;
   - kill and relaunch after labelling: labels persist (v39 migration ran
     on the real file, `PRAGMA user_version` = 39);
   - backup export → import into a fresh database: labels survive.
3. Slices C → B → A → D, each: Opus implements from the paste-ready prompt,
   Fable reviews the whole diff (the Phase 1 review found one phone-width
   overflow, one redundant reload and one query-in-a-loop that 4,434 green
   tests did not), fixes land, then commit that slice alone.
4. After A: a device pass of the chip row at 360 dp with seven labels in use
   and the keyboard up (the row lives in the sliver bar's `bottom`; a height
   drift there shows as a jump under the field).

## 6. Deferred / rejected

- **Pin (sort to top).** Deferred, owner's call. If wanted: `pinned INTEGER
  NOT NULL DEFAULT 0` alongside `label`, leading every `orderBy` in
  `getNotesPaginated`; a pin glyph would go *after* the label dot at the
  trailing edge (L1 keeps the title's left edge fixed; the stripe shows a
  leading-edge overlay is possible, but a pin needs a glyph, not a bar).
  Separate roadmap.
- **A "Labels" smart row at the root / `AllNotesMode.label`.** Rejected for
  now: Slice A's "empty query + label chip" is the same list one tap away,
  and a third smart row would push the folders down for everyone.
- **Multiple labels per item, user-defined colours, tinted rows or folder
  glyphs.** Rejected by L1–L3; not to be reopened without a new mock.
- **Label in the note editor's app bar or as a coloured title.** Rejected:
  the editor's chrome is the mock's single accent, and the dot has no home
  in the collapsed bar.
- **Labels in markdown / text exports.** Not possible — those formats carry
  no metadata. JSON note exports and `_folder.json` already carry it.
