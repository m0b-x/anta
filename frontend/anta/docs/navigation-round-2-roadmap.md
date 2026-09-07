# Navigation Round 2 — Roadmap & Slice Prompts (2026-09-06)

**Status: Slices 1–5 DONE (Slice 1 committed 2026-09-06 as `dad64be`;
Slices 2–4 as `d7f0d78`; Slice 5 uncommitted on top of it). Slice 6
planned.** Baseline: `b0a8b87` (Session 9's wiki links are committed).
Design source: the round-2 mock artifact, revision 2.3 ("option 1"):
https://claude.ai/code/artifact/82c94d9b-0793-47a9-ae29-a036181fcccc
Research: four independent read-only passes on 2026-09-05 (browser page,
editor page, search + navigation plumbing, Flutter 3.44.2 / Material 3
facts). Line numbers below are as of `74b5b67` and will drift — re-grep
before editing.

Companion docs: `COPILOT_CONTEXT.md` ("Navigation And Launch Restore"),
`live-editor-review-and-slices-2026-09.md` (Session 9 wiki links, whose
note→note pushes are why the editor gains an "Open folder" row).

---

## 0. Verdict — will it work better?

Yes, with five corrections to the mock. The core of the design holds up
against both the code and the platform:

- **One icon per corner is the platform default, not a novelty.** Flutter's
  own `AppBar` already picks the drawer icon at the root and a back arrow
  when nested; Android's Up-button guidance says the same. The mock removes
  a collision the app invented (back + divider + hamburger in one corner)
  rather than adding a pattern.
- **The drawer keeps its reach for free.** `Scaffold` builds the edge-drag
  gesture from `drawer` / `drawerEnableOpenDragGesture` alone and never
  reads `AppBar.leading` (`scaffold.dart:2965-2985`). Removing the
  hamburger changes nothing about the swipe. A Settings row in each
  overflow menu is one `ScaffoldState.openDrawer()` call through the key
  both pages already register with `DrawerHostRegistry`.
- **The browser is already a `CustomScrollView`** with one merged sliver
  (`optimized_folder_content_page.dart:576-587`), so a collapsing
  `SliverAppBar.large` is a swap inside an existing sliver list, not a page
  rewrite.
- **Recents and "All notes" need no new query.** `NoteStorageService.
  loadNotesPaginated(folderId: null, sortOrder: updatedDesc)` and
  `NoteDao.getNoteCount(null)` already do it; the recursive folder scope is
  `FolderDao.getAllDescendantIds` (a `WITH RECURSIVE` CTE) that the move
  picker already relies on.

The five corrections (each is folded into a slice below):

1. **"Both use the search bloc that exists now" is false — there is no
   search bloc.** `SearchPage` drives `OptimizedNoteBloc` (`QuickSearchNotes`
   / `SearchNotes` / `ClearSearch`, `OptimizedNoteSearchResults`). That bloc
   also feeds the folder list, which is why the folder page re-runs
   `_loadData()` when search returns. Hosting search *inside* the folder
   page on the same bloc would clobber the list under it. A small
   dedicated `SearchBloc` is a **required** new piece (Slice 4), and it is
   what lets query/scope/scroll survive pushing a note.
2. **`SliverAppBar.large` builds `title` twice** (toolbar row and the
   default flexible space, `app_bar.dart:1375-1401`, `2118-2133`). The
   parent-name eyebrow must live in a custom `flexibleSpace`, never in a
   two-line `title`; a `TextField` or `GlobalKey` in `title` throws. The
   search field therefore **swaps the whole sliver** for a plain
   `SliverAppBar`, and the list needs `keyboardDismissBehavior: manual`
   or scrolling closes the keyboard (`scroll_view.dart:535-548`).
3. **The default expanded height cannot fit an eyebrow.** The expanded
   title box is `152 − 64 − 28 = 60 px`; a headline plus an eyebrow clips.
   Raise `expandedHeight` (≈ 168–176).
4. **`BackButton` drops `onLongPress`** (`action_buttons.dart:24-63`). The
   ancestor menu needs a hand-built `IconButton(icon: BackButtonIcon(),
   onLongPress: …)`, and a visible twin for TalkBack (the eyebrow tap),
   since long-press-only actions are invisible to screen readers.
5. **`popUntil` animates every intermediate route** (flutter#59990). A
   "pop to ancestor" three levels up flickers through two pages. Remove
   the intermediates with `Navigator.removeRoute` and pop once; the
   history observer sees `didRemove`/`didPop` symmetrically either way.

Two risks to budget for, neither a blocker:

- **Drag-reorder under a tall pinned header.** `SliverReorderableList`'s
  autoscroller measures the viewport, not the sliver (flutter#164064), so
  the top trigger zone sits behind the collapsed bar. One reorderable
  sliver over the merged list (never two) plus a `dragBoundaryProvider`
  is the recommended shape; verify on a device in Slice 3.
- **The Android back gesture vs. the left-edge drawer drag** already
  exists today (flutter#143152). With the hamburger gone from nested
  screens the swipe is the only gesture route, so Slice 1 keeps the
  Settings menu row as the reliable path and Slice 6 evaluates trimming
  `drawerEdgeDragWidth`.

What the research does *not* support: replacing the drawer with a
navigation bar (M3's preference at compact width). The owner rejected
drawer-as-navigator on 2026-09-03; the drawer stays a settings list.

---

## 1. Decisions

Taken as defaults so the slices can be written; override before Slice 2.

| # | Question (from the mock) | Default | Why |
| --- | --- | --- | --- |
| D1 | Parent name above the large title? | **Keep.** | Free once `getAncestors` is fetched for the long-press menu, and it is the visible, screen-reader-reachable twin of that menu. |
| D2 | Settings row in menus, or swipe only? | **Row in both menus.** | The swipe collides with the Android back gesture at the left edge; a row costs one line. |
| D3 | Smart rows at root? | **All notes: yes (Slice 6). Recent: yes, same slice, first to drop.** | Search idle already shows recents after Slice 5. |
| D4 | Folders grouped above notes, or interleaved by position? | **Grouped, per the mock.** | Today `mergeByPosition` can interleave. Reorder stays within a group; `_handleReorderMixed` already writes both orders. Flag if interleaving was ever used on purpose. |
| D5 | Folder row count | **Notes including descendants** (mock: Training = 5 + 3 + 4 + 11 = 23). | One batched CTE (Slice 3) replaces two queries per card. |
| D6 | Editor share | **Route through `ImportExportBloc`** like the card. | `NoteExportDialog` calls `SharePlus` directly today, which the import/export rules forbid. Fixed in passing in Slice 1. |
| D7 | Pop-to-folder / pop-to-ancestor | **Remove intermediates, then one pop.** | flutter#59990. |

---

## 2. New features this needs (the owner's question)

Beyond re-arranging existing controls, these are net-new:

1. **`SearchBloc`** (`lib/bloc/search/`) — query, scope, phase (idle /
   quick / full), results grouped by `SearchMatchType`, recents for idle.
   Removes the search events/state from `OptimizedNoteBloc`. Slice 4.
2. **Recursive search scope** — `FolderSearchService.search/quickSearch`
   accept a folder-id set built from `getAllDescendantIds`. Slice 4.
3. **`SearchSurface` widget** — one widget, two hosts (folder page in
   place, standalone route for tag taps). Slice 4 builds it in the
   standalone route, Slice 5 hosts it in place.
4. **Overflow menus** on both pages, including the editor's first-ever
   menu with Move / Delete / Open folder. Slice 1.
5. **`AppNavigator.popToFolder` / `popToAncestor`** helpers (predicate on
   the `NavDestination` stamp in `RouteSettings.arguments`). Slice 1.
6. **Delete-from-editor** — cancel pending saves, soft-delete, pop.
   New workflow, because auto-save would otherwise write into a deleted
   note. Slice 1.
7. **Large-title sliver bar** with a custom flexible space (parent
   eyebrow) and a search-mode sliver swap. Slices 2 and 5.
8. **Ancestor menu** on long-press Back (and eyebrow tap). Slice 2.
9. **Batched descendant note counts** — one DAO statement for N folders
   (today: two statements per card). Slice 3.
10. **Grouped list rows + bottom bar**, `showNotePreview` finally wired,
    FAB and create sheet retired. Slice 3.
11. **All notes / Recent pages** with two additive `NavDestinationKind`
    members for launch restore. Slice 6.
12. **Browser page widget-test harness** — none exists; the editor's
    harness is the template. Slice 1 creates it, every slice extends it.

Not needed: schema changes (none), backup format changes (none), new
settings keys except none — `showNotePreview` already exists.

---

## 3. Facts from the tree (re-grep before editing)

**Browser** — `lib/pages/optimized_folder_content_page.dart` (2320 lines).
Root is `widget.folderId == null` (`:515`); the route carries no parent.
`_scaffoldKey` registered with `DrawerHostRegistry` (`:131`, `:197`).
`Scaffold(drawer: isSelecting ? null : AppDrawer(), drawerEnableOpenDragGesture:
!isSelecting && _folderSwipeEnabled)` (`:518-521`). Normal bar =
`FolderAppBar` (`lib/widgets/unified_app_bars.dart:157-198`; nested leading
= `_IntegratedNavButtons` back + divider + hamburger `:110-139`; rendered by
the gradient `UnifiedAppBar.main` `:52-107`, fixed `kToolbarHeight`).
Actions: search → `AppNavigator.toSearch` then `_loadData()` (`:537-552`),
sort → `_showQuickSortOptions` (`:553-557`), move history badge →
`showMoveHistorySheet` (`:558-573`). Selection mode swaps in
`SelectionAppBar` + `SelectionActionBar`. Body: `RefreshIndicator` →
`CustomScrollView(controller: _scrollController, slivers: [...
_buildContentSlivers, _buildEmptyStateSection])` (`:576-587`).
`_buildMixedSliver` (`:1003-1124`) = nested `BlocBuilder`s → `mergeByPosition`
(`lib/models/content_item.dart:59`) → `SliverReorderableList` in selection
mode / `InfiniteScrollSliver` otherwise (`:1130-1170`). `_FolderCard`
(`:1465-1879`) issues two count queries per card with a 120 ms debounce
(`:1565-1582`); `_NoteCard` (`:1881-2288`) renders the preview
unconditionally (`:1953-1985`) — `showNotePreview`
(`settings_keys.dart:27`, `settings_service.dart:371-380`) has no reader.
FAB → `_showCreateOptions` (`:1349-1390`); `_pickAndImport` (`:1395-1425`);
`_showCreateFolderDialog` (`:1427-1454`); `_createNewNote` (`:1456-1462`).
Two `PopScope`s (`:616-641`). Empty-state copy `tapPlusToCreate` (`:1327`).

**Editor** — `lib/pages/optimized_note_editor_page.dart`. Constructor
`folderId`, `noteId?`, `metadata?` (`:69-79`) — no folder title. Scaffold
`:1507-1511` (`drawerEnableOpenDragGesture: noteSwipeEnabled`), registry
`:217` / `:1060`. Bar = `NoteAppBar` (`unified_app_bars.dart:200-290`,
back + hamburger, `leadingWidth: 96`); title tap → `_editTitle` (`:1900-1912`,
`AppDialogs.textInput`); actions = search toggle (`:1522-1530`,
`_toggleSearch` `:1087-1094`, `ReEditorSearchController`, `NoteSearchBar` in
the body `:1573-1580`) and the eye gated by `_canPreview` (`:1531-1543`).
`PopScope(canPop: false)` → `_saveBeforeExit` → pop (`:1491-1506`). Share =
`MarkdownBar.onShare` → `_showExportFormatDialog` (`:1889-1898`) →
`NoteExportDialog` → `SharePlus` directly. Tag tap → `toSearch(query:)`
(`:1389`); wiki tap → `_handleWikiLinkTap` → `toNoteEditor` (`:1411-1438`).
Move/delete exist only on the browser card: `MoveCoordinator.moveNote`
(`lib/services/move_coordinator.dart:78-96`), `DeleteOptimizedNote` →
`NoteStorageService.deleteNote` → `softDeleteNoteWithChunks`. Save
coordinator: `lib/controllers/note_save_coordinator.dart`.

**Search** — `lib/pages/search_page.dart` (`folderId`, `initialQuery`; per
keystroke `QuickSearchNotes`, Enter `SearchNotes`; flat `ListView`;
`SearchAppBar` `unified_app_bars.dart:494-565`). `OptimizedNoteBloc`
search handlers `optimized_note_bloc.dart:266-352`, 200 ms debounce `:39-44`.
`FolderSearchService` (`lib/services/folder_search_service.dart`): `search`
`:468` (inverted index, then loads up to 1000 notes), `quickSearch` `:539`
(title + preview over one 100-note page), `SearchFilter.matches` `:165-168`
(single folder, non-recursive), `SearchMatchType {title, content}` `:146`,
snippets `:632-671`. Descendants CTE `folder_dao.dart:386-406` /
`folder_repository.dart:392`; `getNoteCountWithDescendants`
`folder_dao.dart:520-525`; `getNoteCountInFolders` `note_dao.dart:65-83`.
`toSearch` is unstamped (`app_navigator.dart:201-207`).

**Navigation** — `lib/services/app_navigator.dart`: `_settingsFor` stamps
`RouteSettings(name: kind.name, arguments: destination)` (`:54-60`);
`toFolder` (`:153-163`), `toNoteEditor` (`:165`), `toNoteEditorInstant`
(`:184`), `popUntilFirst` only (`:113`). `NavDestinationKind` members are
persisted names (`lib/models/nav_destination.dart:19-30`); adding a member
needs no `stackVersion` bump. `NavigationHistoryObserver`
(`navigation_history_service.dart:128-184`) handles `didPop`/`didRemove`.
`DrawerHostRegistry.openTopDrawer()` (`lib/services/drawer_host_registry.dart:35`).
`FolderStorageService.getAncestors(folderId)` (`folder_storage_service.dart:274-295`,
root → parent, excludes self, cached-repo walk); sole caller
`folder_picker_dialog.dart:93`.

**Tests** — no browser page test. Template: `test/widgets/
optimized_note_editor_page_test.dart` (real drift on a background isolate,
so never `FakeAsync`; custom `settle`; services in `setUpAll`, blocs closed
in `tearDownAll`; `teardownPage` to stop timers). Navigation tests:
`test/services/navigation_history_service_test.dart`, `test/widgets/
navigation_history_observer_test.dart`, `test/models/nav_destination_test.dart`.
No `AppNavigator`, `DrawerHostRegistry`, `FolderSearchService` or
`SearchPage` tests. DB conventions: `test/database/query_plan_test.dart`,
`query_count_test.dart`, `schema_parity_test.dart`.

**l10n** — exist: `sortBy`, `sortFolders`, `sortNotes`, `moveHistory`,
`rename`, `moveToFolder`, `share`, `shareNote`, `shareFolder`, `delete`,
`deleteNote`, `deleteNoteConfirm`, `deleteThisNote`, `import`,
`importNoteOrFolder`, `createFolder`, `createNote`, `newNote`, `select`,
`settings` (**duplicated** at `app_en.arb:2373` and `:2569` — do not add a
third), `search`, `searchInFolder`, `searchAll`, `noSearchResults`,
`recentSearches`, `editTitle`, `findInNote`, `openFolder` (folder-picker
tooltip), `emptyFoldersHint`, `emptyNotesHint`, `tapPlusToCreate`.
Missing: `newFolder`, `everywhere`, `thisFolder`, `recent`, `allNotes`,
`titlesSection`, `inTextSection`, `openFolderNamed`, `goToFolder`,
`folderAndNoteCount` (ICU plural), `showAncestors`.

**Toolchain** — Flutter 3.44.2 stable, Dart 3.12.2, `sdk: ^3.10.4`.
`SliverAppBar.large`, `IconButton.onLongPress`, `showMenu(positionBuilder:)`
and `SliverReorderableList.onReorderItem` (`onReorder` is deprecated since
3.41) are all available.

---

## 4. Slices

Each slice ships on its own, leaves the suite green, and is committed
before the next starts. Order matters: 1 → 2 → 3 → 4 → 5 → 6. Slices 4
and 5 could be swapped ahead of 2 and 3 if search is the higher priority;
nothing in 4–5 depends on the sliver bar except Slice 5's sliver swap.

Every prompt is self-contained: paste it into a fresh Opus session opened
in `frontend/anta`. Prompts say "do not implement other slices" on
purpose — a slice that grows is the main way this kind of work stalls.

### Slice 1 — One icon per corner, overflow menus, editor note actions

**Shipped 2026-09-06** on `b0a8b87`, uncommitted. Deviations from the plan
below, each deliberate:

- `_IntegratedNavButtons` / `_NavButton` are **kept**, not deleted:
  `SettingsAppBar` still uses them and settings pages are out of this
  slice's scope. `FolderAppBar` and `NoteAppBar` no longer reference them.
- **New l10n keys: `noteNotFound` only.** `openFolder` was reused (its
  description generalised), and `sortByCustom` / `sortByUpdated` /
  `sortByTitle` / `sortByName` / `sortByCreated` already existed for the
  sort row's trailing text. `newFolder` was **not** added — nothing in this
  slice creates a folder (the FAB and its sheet are untouched until
  Slice 3). `noteNotFound` is new because move and share need a persisted
  note and had no message for "there is nothing to act on yet".
- The move-history badge also rides the `⋮` icon, so the count stays
  visible without opening the menu.
- The editor's share flushes through `NoteSaveCoordinator.saveBeforeExit`
  and re-reads the note (new `NoteStorageService.getNoteMetadata`) before
  dispatching: `ImportExportService.exportNote` loads the content by id, so
  the unsaved buffer would otherwise be exported stale.
- `_NoteCard._showExportFormatDialog` now calls the same
  `NoteExportDialog.chooseFormat`, so there is one chooser rather than two
  copies of the same option list.
- `SelectionController.activate()` is new — the Select row enters selection
  mode with nothing selected, which `add`/`toggle` could not express.
- The editor keeps its folder id in state (`_folderId`), because a move
  from its own menu changes it; the title-uniqueness scope and the wiki
  link's `preferFolderId` read the live value.
- The browser re-reads its own folder (`_folder`) after "Move folder" from
  its menu, for the same reason: the rename uniqueness check and the
  delete event both read `parentId` off it, and the stale record would
  point at the old parent.
- Known limitation, deliberately left: the editor's route stamp
  (`NavDestination.note`) keeps the folder the note was *opened* from. A
  move from the editor's menu followed by a process kill restores the note
  under its old folder; the note itself opens fine and its menu shows the
  new folder once the name loads. Route settings are immutable, and
  replacing the live editor route for this would cost more than it fixes.

Goal: nested folders and the editor show one back arrow; root shows the
menu; every overflow menu ends with Settings; the editor can move, delete
and jump to its folder. User-visible on day one; no sliver work yet.

Scope:
1. `FolderAppBar`: nested leading = a single hand-built
   `IconButton(icon: BackButtonIcon(), tooltip: back)`; delete
   `_IntegratedNavButtons` / `_NavButton`; root keeps the menu button.
   `NoteAppBar`: drop the hamburger (`showMenuButton` and its
   `leadingWidth`), keep back + title + save glyph.
2. Folder bar actions become exactly `[search][⋮]`. New
   `FolderOverflowMenu` (`lib/widgets/`): Sort by (current value as
   trailing text; opens `_showQuickSortOptions`), Select (enters
   selection mode), Move history (badge from `MoveHistoryService.changes`)
   ── Rename folder, Move folder, Share folder, Import (nested only; root
   menu = Sort, Select, Move history, Import, Settings) ── Delete folder ──
   Settings. Rename/Move/Share/Delete of the *current* folder reuse the
   card's service calls; the page needs its own folder's metadata
   (`FolderStorageService.getFolderById`). Delete of the current folder
   pops afterwards. Card menus stay for child items. The FAB stays until
   Slice 3.
3. Editor: new `NoteOverflowMenu`: "<Folder name>" with trailing "Open
   folder" (label from `getFolderById(folderId)` loaded once in
   `initState`; falls back to `l10n.folders` at root — a note is never at
   root, so this is defensive), Edit title, Move to folder, Share note,
   Delete note, Settings.
   - Open folder → new `AppNavigator.popToFolder(context, folderId)`:
     if a route stamped `NavDestination.folder` with that id exists on
     the stack, remove every route above it (`Navigator.removeRoute`,
     top-down, skipping the current route) then `pop()` once; otherwise
     (note reached by restore or a wiki link whose folder is not on the
     stack) `pushReplacement` with `toFolder`. Wiki-link chains
     (`[[A]]`→`[[B]]`) make the "not on the stack" branch real.
   - Move → `MoveCoordinator.moveNote`; after a successful move the
     page's `folderId` and menu label update (the note's `folderId` in
     `metadata` changes; re-fetch the folder name).
   - Delete → confirm with the card's dialog copy; then, in this order:
     `NoteSaveCoordinator` cancel pending + disable further saves (add a
     method if none exists — an auto-save after delete would write into a
     soft-deleted row, and early-create on a new note would resurrect it),
     `DeleteOptimizedNote`, `AppNavigator.pop`.
   - Share → dispatch `ExportNoteRequested(metadata, format, share: true)`
     on `ImportExportBloc` exactly like the card; migrate
     `NoteExportDialog` to return the chosen format instead of calling
     `SharePlus` (D6). The toolbar share button uses the same path.
   - Settings → `_scaffoldKey.currentState?.openDrawer()` from the button's
     context (the menu route is gone by the time `onSelected` runs).
4. Wire the same Settings row into the folder menu.
5. Edge swipe unchanged on both pages (`drawerEnableOpenDragGesture` as is).
6. l10n en/de/ro: `openFolderNamed` (or reuse `openFolder` only if the desc
   is generalised), `newFolder`, any "Sort by · Edited" trailing strings.
   `flutter gen-l10n`; check `untranslated.txt`.
7. Tests: create `test/widgets/optimized_folder_content_page_test.dart`
   from the editor harness (real DB, `settle`, `teardownPage`). Cases:
   root shows menu icon and no back; nested shows back and no menu;
   overflow menu rows in order for root vs nested; Settings row opens the
   drawer (`find.byType(AppDrawer)`). Editor test additions: no menu icon;
   overflow rows; delete disables saves and pops (assert no save after
   delete via the coordinator's fake/spy); popToFolder unit test with a
   `NavigatorObserver` (removes intermediates, one pop; falls back to
   pushReplacement).
8. Docs: COPILOT_CONTEXT "Navigation And Launch Restore" gains a short
   "app bar convention" paragraph (root = menu, nested = back, Settings
   row) and a `popToFolder` note; this file's status line.

Exit: `dart analyze lib` clean, `flutter test` green, on-device: back
arrow only on nested folder and editor, drawer via swipe and via both
menus, delete from editor does not resurrect the note (reopen the folder,
note is gone; check `is_deleted` if in doubt), share from editor goes
through the bloc's snackbar path.

```text
PROMPT — Slice 1 (navigation round 2)

Repo: D:\Alex\Programare\repos\anta, Flutter app in frontend/anta. Run every
command from frontend/anta. Load the `anta-context` skill first, then `l10n`,
then read docs/navigation-round-2-roadmap.md sections 0–3 and "Slice 1" in
full — it is the spec; do not re-derive it and do not implement any other
slice. Implement Slice 1 exactly as written there, on a clean tree (stop
and say so if `git status` is not clean).

Rules (from CLAUDE.md, restated because they are the ones most often
broken): no code comments of any kind in new or edited code (doc comments
/// that already exist stay). Every user-visible string goes through
AppLocalizations — edit app_en.arb, app_de.arb, app_ro.arb together, run
`flutter gen-l10n`, check untranslated.txt is empty; the `settings` key is
already duplicated in app_en.arb, reuse it, do not add another. Never
bypass Page → BLoC → Service → Repository → DAO. Settings only through
SettingsService/SettingsKeys. Exports only through ImportExportBloc and
shareExport, never SharePlus directly (this slice removes the one
violation in NoteExportDialog). Tests are welcome and expected; use the
harness pattern in test/widgets/optimized_note_editor_page_test.dart (real
drift on a background isolate: never FakeAsync, use its settle helper
shape, register services in setUpAll, close blocs in tearDownAll, unmount
the page before the test ends). No new markdown docs; update the existing
ones the slice names.

Order of work: (1) AppNavigator.popToFolder + unit test; (2) FolderAppBar /
NoteAppBar leading changes; (3) FolderOverflowMenu widget + wiring, FAB
untouched; (4) NoteOverflowMenu widget + Open folder / Edit title / Move /
Share (bloc path, NoteExportDialog returns a format) / Delete
(cancel saves → DeleteOptimizedNote → pop) / Settings; (5) l10n; (6) the new
browser page test file + editor test additions; (7) docs. Re-grep every
line number the roadmap cites; they drift.

Traps: `PopupMenuButton.onSelected` runs after the menu route is gone —
open the drawer through the page's scaffold key, not the item's context.
A pending auto-save or early-create after delete writes into a
soft-deleted note; disable the coordinator before dispatching the delete.
`Navigator.popUntil` animates every intermediate route; remove
intermediates with removeRoute and pop once. Windows shell: no python, do
not use perl -i on ARB files; use the Read/Edit/Write tools.

Finish with: `dart analyze lib`, `flutter test`, a summary listing every
file touched, every new l10n key, the test names added, and anything in
the spec you deviated from and why. Do not commit.
```

### Slice 2 — Large-title sliver bar with parent eyebrow, ancestor menu

**Shipped 2026-09-06** on `dad64be`, uncommitted. Deviations from the plan
below, each deliberate:

- **The gradient decision: both bars lose it.** `UnifiedAppBar.main` —
  `NoteAppBar` and `SelectionAppBar` — now renders a plain M3 `AppBar` on
  `colorScheme.surface`, with `scrolledUnderElevation` supplying the only
  colour change. The alternative (keeping it and matching the sliver's
  `backgroundColor` to its top colour) would have put 172 px of
  `inversePrimary` at the top of every folder in light mode, which is not
  what the mock draws — its bars are flat `--m-ground` in both themes —
  and a gradient cannot follow the collapse. `UnifiedAppBar.settings`
  keeps its gradient: settings pages were explicitly out of scope, so
  `AppBarStyle` still has two members. `SearchAppBar`'s hardcoded
  `inversePrimary` went with them, in passing: it used to match
  `FolderAppBar` and would otherwise have been the only lavender bar left
  in the app. Slice 5 replaces that surface anyway.
- **The ancestor menu lists nearest-parent first**, ending with the root
  under a home icon — the mock's "Long-press on Back" panel shows
  `Training` then `Folders` from inside `Winter block`, and a menu opened
  by holding Back reads as a back stack, not as a breadcrumb. The scope
  line's "top-down" is therefore reading order, not hierarchy order.
- **The menu anchors under whichever control was touched**, not always
  under the leading icon: the eyebrow's own context anchors the
  eyebrow-tap menu. Sharing one `GlobalKey` across the toolbar and the
  flexible space — two subtrees the delegate rebuilds on every scroll
  tick — buys nothing, and the two anchors are within a few pixels of
  each other horizontally.
- **The back button's `CustomSemanticsAction` needs `MergeSemantics`.**
  A bare `Semantics(customSemanticsActions:)` above an `IconButton`
  settles the annotation on the node *enclosing* the button, so TalkBack
  offered "Show parent folders" for the whole bar and not for the arrow;
  the assertion in the suite is what caught it.
- **`popToAncestor`'s root case is not `popUntilFirst`.** The plan named
  it, but `popUntil` pops one route at a time — the very thing D7 exists
  to avoid. The root is addressed by `Route.isFirst` (it is `home` and
  carries no `NavDestination` stamp) and collapsed onto with the same
  remove-then-one-pop helper `popToFolder` uses, now extracted as
  `_livePageRoutes` / `_collapseOnto`.
- **The selection-mode swap has to pay for itself.** The sliver is 172 px
  of scroll extent *inside* the viewport; `SelectionAppBar` is
  `kToolbarHeight` *outside* it. Keeping the offset would have carried
  every row up by 116 px on each long press and back down on each exit —
  the layout shift the project's UX bar forbids. The `_selection.changes`
  listener now detects the edge and jumps the controller by
  `FolderSliverAppBar.expandedHeight − kToolbarHeight` in the **same
  synchronous tick** as the `setState` (a post-frame callback would paint
  one frame at the wrong offset, which is the jump itself). Leaving
  restores the offset entered at *plus* whatever was scrolled while
  selecting, so a partly expanded bar comes back exactly — entering at 50
  returns to 50, not 116. The result is clamped at 0 only; clamping
  against `maxScrollExtent` is impossible there (the new extent is not
  laid out yet) and the physics settle the rare shrunk-content case.
- **`RefreshIndicator` gained an `edgeOffset`.** It still triggers — the
  pinned sliver does not eat overscroll — but the spinner dropped from
  the top of the body, which the expanded bar covers. `edgeOffset` is
  purely positional in the framework, so nothing about the gesture
  changed.
- The collapsed bar is 64 px (the large variant's own collapsed height,
  as the scope says) while `NoteAppBar` is `kToolbarHeight`, 56. Matching
  exactly would mean hand-computing `collapsedHeight` from
  `MediaQuery.paddingOf(context).top`, which fights the variant. Colours
  and icon treatment match, which is what "match the collapsed look"
  asked for.
- **The root bar now reads "Folders", not "ANTA"** — the scope says
  `l10n.folders` and the mock draws it, and the ancestor menu's home row
  says the same word, but it does mean the app name has left the root
  bar. `main.dart` still constructs the page with `title: 'ANTA'`; the
  root simply no longer renders it.
- The mock's "little extra top padding" at the root has no equivalent
  here: the expanded title is bottom-aligned in both cases (that is what
  makes it slide under the toolbar), so a missing eyebrow already leaves
  the extra space above it.
- `FolderAppBar` is deleted; `_IntegratedNavButtons` / `_NavButton` stay,
  still used by `SettingsAppBar`.
- **New l10n key: `showAncestors` only.** `folders` already existed and is
  reused for both the root eyebrow and the menu's home row.
- Device verification still owed: collapse and pull-back feel, no title
  clipping at the largest font size, and TalkBack reading the back
  button's custom action.

Goal: the browser bar opens tall with the folder name large, the parent's
name muted above it, and collapses on scroll into the editor-shaped bar;
long-press on Back (or tap on the eyebrow) lists ancestors.

Scope:
1. Replace `FolderAppBar` in the browser with a `SliverAppBar.large`
   as the first sliver of the existing `CustomScrollView` (`appBar:` is
   then null outside selection mode; selection mode keeps `SelectionAppBar`
   as a box app bar and omits the sliver). `pinned: true`, `expandedHeight`
   ≈ 172, `toolbarHeight` 64 (the large variant's collapsed height),
   `leading` = the Slice 1 back button (nested) / menu button (root),
   `actions` = `[search][⋮]`, `title` = a one-line folder name (this is
   what shows when collapsed). Supply a **custom `flexibleSpace`** that
   reads `FlexibleSpaceBarSettings` and draws eyebrow + large title with
   the framework's own fade curve (`isScrolledUnder` semantics:
   `shrinkOffset > maxExtent - minExtent`). Never put a second line, a
   `GlobalKey` or a `FocusNode` in `title` — `.large` builds it twice.
   Root: no eyebrow, title "Folders" (`l10n.folders`), a little extra top
   padding as in the mock.
2. Match the collapsed look to `NoteAppBar` (same background, same
   icon colour). Decide the gradient once: either both bars lose it or
   `NoteAppBar` keeps it and the sliver's `backgroundColor` matches its
   top colour; record the choice in the decision log. Remove the
   now-unused parts of `UnifiedAppBar`.
3. Ancestors: on `initState` (nested only) call
   `FolderStorageService.getAncestors(folderId)` once; eyebrow = last
   ancestor's name or `l10n.folders`. Long-press on the back button and
   tap on the eyebrow open `showMenu(positionBuilder:)` anchored under the
   leading icon listing every ancestor top-down ending with "Folders"
   (home icon). Each row → new `AppNavigator.popToAncestor(context,
   folderId?)` (null = root → `popUntilFirst`; otherwise the Slice 1
   `popToFolder`). Accessibility: the back button gets a
   `CustomSemanticsAction` for the ancestor list; the eyebrow is a
   `Semantics(button: true)` with a label.
4. Refresh: `RefreshIndicator` stays; confirm it still triggers with the
   sliver bar (it needs the scrollable's overscroll, which the pinned
   sliver does not eat).
5. Keyboard: no field in the bar yet, but set `keyboardDismissBehavior:
   ScrollViewKeyboardDismissBehavior.manual` now so Slice 5 does not
   fight it.
6. Short content: with fewer rows than a screen the bar stays expanded
   (that is the framework's behaviour, not a bug — do not add a
   `SliverFillRemaining` hack to force collapse). Empty state renders
   below the expanded bar.
7. l10n en/de/ro: `showAncestors` (semantic label / tooltip).
8. Tests (extend the Slice 1 harness): nested page shows eyebrow with
   the parent name; root shows none; scrolling past the threshold shows
   the collapsed title (drive the `ScrollController`); long-press on the
   back button shows a menu whose rows are the ancestors + Folders; tapping
   the "Folders" row leaves only the root route (NavigatorObserver);
   `popToAncestor` unit tests.
9. Docs: COPILOT_CONTEXT app-bar paragraph (sliver, custom flexible
   space rule, why `title` is single-line), this file.

Exit: analyze/test green; device: collapse and pull-back feel right, no
title clipping at the largest font size, ancestors menu pops without
flicker, TalkBack reads the back button's custom action.

```text
PROMPT — Slice 2 (navigation round 2)

Repo: D:\Alex\Programare\repos\anta, Flutter app in frontend/anta. Run every
command from frontend/anta. Load the `anta-context` skill, then `l10n`, then
read docs/navigation-round-2-roadmap.md sections 0–3 and "Slice 2" in full —
it is the spec. Slice 1 is already merged; verify (nested folder bar shows
a single back arrow, FolderOverflowMenu exists) and stop if not. Implement
Slice 2 only, on a clean tree.

Rules: no code comments in new or edited code (existing /// stays). All
strings via AppLocalizations, en/de/ro together, `flutter gen-l10n`,
untranslated.txt empty. Never bypass Page → BLoC → Service → Repository →
DAO. No new markdown docs. Tests expected, extending
test/widgets/optimized_folder_content_page_test.dart (real drift, never
FakeAsync, settle helper, teardownPage).

Framework facts you must respect (Flutter 3.44.2): SliverAppBar.large
builds `title` twice (toolbar and default flexibleSpace) — a two-line
title, GlobalKey or FocusNode there throws or duplicates; put eyebrow +
large title in your own flexibleSpace reading FlexibleSpaceBarSettings,
and keep `title` a single Text for the collapsed state. Default expanded
title box is 60 px tall, so raise expandedHeight to about 172. BackButton
drops onLongPress: hand-build IconButton(icon: BackButtonIcon(),
onPressed, onLongPress). Anchor the ancestor menu with
showMenu(positionBuilder:). popUntil animates each intermediate route:
reuse Slice 1's popToFolder (removeRoute then one pop). Set
keyboardDismissBehavior: manual on the CustomScrollView now. A list
shorter than the screen leaves the bar expanded; that is correct.

Order: (1) popToAncestor helper + tests; (2) sliver bar with custom
flexibleSpace, selection mode keeps SelectionAppBar; (3) ancestors fetch,
eyebrow, long-press + eyebrow-tap menu, semantics; (4) style match with
NoteAppBar, remove dead UnifiedAppBar code; (5) l10n; (6) tests; (7) docs.
Re-grep every cited line number.

Finish with `dart analyze lib`, `flutter test`, and a summary: files
touched, l10n keys, tests added, deviations with reasons, plus the gradient
decision you took. Do not commit.
```

### Slice 3 — Grouped rows, note preview setting, bottom bar, FAB retired

**Shipped 2026-09-06** on `dad64be`, uncommitted alongside Slice 2.
Deviations from the plan below, each deliberate:

- **The count string is three keys, not one.** The scope asks for one ICU
  plural key with three shapes, but "3 folders, 5 notes" needs *two*
  independently pluralised numbers, and a single message can only express
  that as a plural nested inside a plural — 3 folder forms × 4 note forms
  written out per language, with Romanian's `few` in both positions. It
  would be unreadable and untranslatable in practice. Instead
  `folderCountLabel` and `noteCountLabel` are ordinary plural keys and
  `folderAndNoteCount` joins two already-rendered halves (`"{folders},
  {notes}"`), so a locale can still change the separator. All three shapes
  the scope lists are produced, each half stays a sentence a translator can
  read, and the zero case renders nothing at all — the empty state already
  says it.
- **`tapPlusToCreate` was replaced, not reworded.** With the `+` gone the
  key name would have been a lie; the new key is `createFromBarBelow` and
  the old one is left in the ARBs untouched (nothing reads it, and deleting
  a key is a separate, riskier edit than adding one).
- **The note row's date is compact and locale-aware, not relative.** The
  scope says "relative date"; a real one ("2 days ago") needs at least five
  new plural/adverb keys in three languages, which is a bigger l10n change
  than the whole rest of the slice. `intl` gives the same compactness for
  free: the time for something edited today, day-and-month within this
  year, the short date beyond it. Worth revisiting if the mock's exact
  wording matters.
- **The note row dropped the content size.** The old card showed
  `12.4 KB` next to the date; the mock's row is title + date + preview, and
  the second line has no room for a third field once the preview is on.
- **Section labels appear only when both groups are present**, which is
  the one rule that satisfies all three clauses of the scope's parenthesis
  at once: a nested folder shows "Notes" only alongside folders, and the
  root — which never has notes — gains its "Folders" label with the smart
  rows in Slice 6, not before.
- **`_loadFolderCounts` clears without `setState`.** It is called from the
  list's own builder, so the empty-folder path would otherwise be a
  rebuild during build; with no folder rows on screen there is nothing
  whose count could repaint anyway. This was a real crash in three
  existing cases before it was fixed.
- **The bottom bar's count comes from `paginatedFolders.totalCount` /
  `paginatedNotes.totalCount`**, in `BlocBuilder`s of its own rather than
  off the page's `_visibleFolders`. The bar is constructed before the
  list's builders run, so reading the fields would have shown last frame's
  numbers; and the totals are exact where the loaded page is not.
- **No `dragBoundaryProvider`, and the device check the scope asks for is
  moot.** flutter#164064 is about the autoscroll trigger zone hiding
  behind a tall pinned bar — but reordering only exists in selection mode,
  and Slice 2 established that selection mode replaces the sliver with a
  box `SelectionAppBar` outside the scroll view. There is no pinned sliver
  over the reorderable list to hide anything.
- `_FolderCard` / `_NoteCard` / `_DragFeedback` moved out of the page into
  `lib/widgets/folder_row.dart`, `note_row.dart` and `content_rows.dart`
  as `FolderRow` / `NoteRow` / `DragFeedbackChip`, which is what lets the
  tests address them by type. The page lost ~840 lines.
- **Test trap worth keeping.** `_handleReorderMixed`'s writes are
  fire-and-forget *and started inside the case's fake clock*, so ending
  the case strands sixteen row writes mid-transaction and the next case's
  first query queues behind a lock nothing releases — the symptom is a
  hang, not a failure. The reorder cases end with a `drainWrites` that
  alternates real delays and pumps (`settle`); real time alone does not do
  it. Separately, a settings write in a `testWidgets` body must go through
  `tester.runAsync` for the same reason.
- Device verification still owed: a 200-folder root scrolling without
  count jank, drag-reorder autoscroll in selection mode, and the bottom
  bar clearing the gesture bar on a real device.
- Review pass (same day), three fixes: `_loadFolderCounts` drops a result
  whose id list is no longer the one on screen (two in-flight reads could
  otherwise land out of order and leave a fresh page showing zeros);
  `FolderRow` always renders its subtitle line, so the row does not grow
  by 16 px when the count arrives; the drop-target highlight moved into
  `ContentRowShell` (`isDropTarget`), where it follows the row's own corner
  radii instead of framing the 16 px inset around it.

Goal: the list looks like the mock (folder rows with one count, note
rows with date + optional preview, section labels), counts cost one
query, the bottom bar replaces the FAB.

Scope:
1. Rows: `FolderRow` (icon, name, count, chevron) and `NoteRow` (title;
   second line = relative date + " · " + first preview line when
   `showNotePreview` is on, date alone when off). Grouped containers
   with rounded corners and inset dividers, section labels "Folders" /
   "Notes" (nested only shows the "Notes" label when folders are also
   present; root shows "Folders" under the smart-row group once Slice 6
   adds it). Card menus, long-press → selection, `LongPressDraggable`
   source and `DragTarget` on folders are preserved 1:1 from the cards.
   Money-ledger preview lines keep their monospace figures (reuse the
   existing preview text; do not parse the ledger here).
2. Ordering (D4): folders first, then notes, each in its own sort order;
   `mergeByPosition` is replaced by concatenation for display. Reorder:
   **one** `SliverReorderableList` over the concatenated list in
   selection mode using `onReorderItem` (not the deprecated `onReorder`);
   header rows are non-draggable items; `onReorderItem` clamps a move to
   its own group; `_handleReorderMixed` is simplified accordingly
   (`MixedReorderService` may become per-type — keep its transaction).
   Add a `dragBoundaryProvider` if the device test shows autoscroll dead
   zones under the pinned bar (flutter#164064).
3. Counts (D5): new `FolderDao.noteCountsWithDescendants(List<String>
   folderIds) → Map<String, int>` as one `WITH RECURSIVE` statement
   (`tree(root, id)` seeded from the ids, joined to non-deleted notes,
   grouped by root), exposed through `FolderRepository` →
   `FolderStorageService`. The page loads counts once per visible page of
   folders (and on `changesForParent` / `changesForFolder`, debounced),
   not per row. Add a `test/database/query_count_test.dart` case
   (statement count independent of folder count) and a query-plan case
   (index use on `folders.parent_id` and `notes.folder_id`).
4. `showNotePreview`: `EditorSettings`-style read in the page's
   `_loadSettings`; re-read on `didPopNext` (the setting can change in
   the drawer's settings page under the browser).
5. Bottom bar (`bottomNavigationBar` outside selection mode): left
   "New folder" icon button → `_showCreateFolderDialog`; centre count
   text via one ICU plural key (`folderAndNoteCount`: "3 folders, 5
   notes" / "5 folders" / "4 notes"); right = "New note" (nested) or
   "Import" (root). Delete the FAB, `_showCreateOptions`, and the
   `_isSortSheetOpen` FAB-lift; Import stays in the overflow menu too.
   Bottom clearance: pad by `max(viewInsets.bottom, viewPadding.bottom)`
   (the app's most-repeated bug). Reword `tapPlusToCreate`.
6. l10n en/de/ro: `newFolder`, `folderAndNoteCount` (plural, three
   shapes), `notePreviewOff`? (no — nothing to say), reworded
   `tapPlusToCreate`.
7. Tests: rows render grouped with labels; preview line hidden when the
   setting is off; count text for the three plural shapes; bottom bar
   buttons by root/nested; reorder clamps within group (drive
   `onReorderItem` directly); DB tests above.
8. Docs: COPILOT_CONTEXT browser paragraph (grouped order, one count
   query), `docs/money-ledger-feature.md` only if the preview line
   changed (it should not), this file.

Exit: analyze/test green; device: 200-folder root scrolls without count
jank, reorder works in selection mode including autoscroll near the bar,
bottom bar clear of the gesture bar.

```text
PROMPT — Slice 3 (navigation round 2)

Repo: D:\Alex\Programare\repos\anta, Flutter app in frontend/anta. Run every
command from frontend/anta. Load `anta-context`, `drift-migrations` (for the
new DAO query and its tests; there is NO schema change in this slice —
stop if you think one is needed) and `l10n`, then read
docs/navigation-round-2-roadmap.md sections 0–3 and "Slice 3" in full.
Slices 1–2 are merged (sliver bar with eyebrow exists); verify, then
implement Slice 3 only, on a clean tree.

Rules: no code comments in new or edited code (existing /// stays). All
strings via AppLocalizations, en/de/ro together, `flutter gen-l10n`,
untranslated.txt empty; the count string is one ICU plural key with the
three shapes the spec lists. Never bypass Page → BLoC → Service →
Repository → DAO — the count query is DAO → repository → service → page.
No new markdown docs. Tests expected: extend
test/widgets/optimized_folder_content_page_test.dart (real drift, never
FakeAsync) and add DB cases to test/database/query_count_test.dart and
query_plan_test.dart following their existing style (NativeDatabase.memory,
no wall-clock assertions).

Facts: today's _FolderCard runs two queries per card
(optimized_folder_content_page.dart around :1565, re-grep); replace with
one batched WITH RECURSIVE statement. SliverReorderableList.onReorder is
deprecated — use onReorderItem. Keep exactly one reorderable sliver over
the concatenated folders-then-notes list; header rows are non-draggable
items and moves are clamped within their group. Preserve LongPressDraggable
/ DragTarget move-by-drop, long-press selection, card menus, MixedReorderService's
transaction. Pad the bottom bar by max(viewInsets.bottom, viewPadding.bottom).
Retire the FAB and _showCreateOptions; Import stays in the overflow menu
and takes the root's right bottom slot.

Order: (1) DAO query + repository + service + DB tests; (2) FolderRow /
NoteRow widgets with showNotePreview; (3) list body regroup + reorder
clamp; (4) bottom bar, FAB removal, empty-state copy; (5) l10n; (6) widget
tests; (7) docs. Re-grep every cited line number.

Finish with `dart analyze lib`, `flutter test`, and a summary: files
touched, the SQL of the new query, l10n keys, tests added, deviations with
reasons, and whether a dragBoundaryProvider was needed. Do not commit.
```

### Slice 4 — SearchBloc, recursive scope, grouped results (standalone route)

**Shipped 2026-09-06** on `dad64be`, uncommitted alongside Slices 2 and 3.
Deviations from the plan below, each deliberate:

- **The bloc talks to three services, not two.** The scope line says
  "`FolderSearchService` and `NoteStorageService` only", but scope items 2
  and 3 of the same list require `FolderStorageService.subtreeIds` and
  `getAncestors`. The rule the "only" was protecting — never reach past a
  service into a repository or DAO — holds: the bloc has no repository and
  no DAO.
- **`SearchSubmitted` carries its query; `SearchOpened` does not.** The plan
  wrote `SearchSubmitted()` reading the query out of state, but
  `SearchQueryChanged` is debounced with `switchMap`, so the tag path
  (`SearchOpened` + query + submit) would have raced: the full search would
  land, and 200 ms later the debounced quick pass would paint over it. The
  field is the source of truth for what was submitted, so it is passed. Same
  reason the page dispatches `SearchCleared()` rather than
  `SearchQueryChanged('')` on an emptied field — clearing must not wait out
  a debounce.
- **One `SearchState` with a `phase`, not a sealed hierarchy.** Every phase
  renders the same three regions and carries the same scope and query; a
  hierarchy would have re-declared both in each case. Events stay sealed.
- **Folder paths live in the state as a `folderId -> segments` map**, not on
  each row. That *is* the "batch and dedupe by folder id" the scope asks
  for — the map is the dedupe — and it keeps `recents` a plain
  `List<NoteMetadata>` instead of a new pair type. `FolderStorageService.
  folderPathSegments` returns segments rather than a joined string, so the
  ` › ` separator stays in the widget with the rest of the rendering.
- **Rows are a new `SearchResultRow`, not `NoteRow` itself.** The scope says
  "the Slice 3 `NoteRow` look", and it is that look — same `ContentRowShell`,
  same leading icon, same title style — but `NoteRow`'s second line is the
  edit date joined to the stored preview, and a result has two more things
  to say in that space (the folder path, and the highlighted excerpt).
  Reusing the widget would have meant three new optional parameters and a
  second layout inside it.
- **Highlights come only from `SearchMatch.startIndex/endIndex`.** The old
  page re-scanned the text with `toLowerCase().indexOf(query)`, which is a
  second fold and disagreed with the service about diacritics; a row with an
  out-of-range or empty span renders plain rather than throwing.
- **`quickSearch` pages unscoped and filters in memory**, at 300 rows — the
  scope's own fallback, because the DAO can page by one folder id and a
  subtree is many. A `getNotesInFolders` DAO method is still the real fix
  when the ceiling starts to bite.
- **`SearchFilter.folderId` was replaced, not supplemented.** Its only two
  callers were the handler being deleted and the service itself, so keeping
  a single-folder field would have left a second, non-recursive way to scope
  a search — exactly the divergence this slice exists to remove. An empty
  set now means "nothing", which is what a scope on a deleted folder needs.
- **`toSearch` gained `folderName`.** The chip needs a label and the page had
  only an id; the browser passes `_folder?.name ?? widget.title`, and
  `thisFolder` is the fallback when a caller has no name. Resolving the name
  inside the bloc was the alternative and would have made every open await a
  folder read before it could draw a chip.
- **The `debounce` transformer moved to `lib/utils/bloc_helpers.dart`.** It
  was a top-level function in `optimized_note_bloc.dart` whose only user was
  the `QuickSearchNotes` registration this slice deletes; leaving it there
  would have made the new bloc import the old one. `bloc_helpers.dart` was
  being edited anyway — its `matchesFolderContext` named
  `OptimizedNoteSearchResults`.
- **`OptimizedNoteBloc` keeps its `searchService`.** Only the three search
  handlers, events and the results state are gone; the bloc still calls
  `updateIndex` / `removeFromIndex` / `dispose` on create, update and delete,
  which is what keeps the index in step with the notes.
- **The perf cap needed a real fix, not a verification.** Scope item 7 said
  "it may already — verify": it did not. `search()` loaded the content of
  every hit and then took `limit` *after* sorting. Relevance comes off the
  index, so ranking, filtering and cutting all moved ahead of the first
  content read. `test/services/folder_search_service_limit_test.dart` counts
  `loadNoteContent` calls against a 60-hit query.
- **Test traps worth keeping.** (1) `ContentSectionHeader` upper-cases its
  label, so `find.text('Titles')` finds nothing — read `.label` off the
  widget instead. (2) A folder name is on screen twice once results have
  paths (the chip and a row), so chip assertions need
  `find.widgetWithText(ChoiceChip, …)`. (3) The bloc suite's storage fakes
  `extend` their services over a lazily-opened `NativeDatabase.memory()` that
  is never queried — cheaper and less brittle than two dozen
  `UnimplementedError` stubs. (4) `FolderSearchService.buildIndex` crosses
  into a `compute` isolate above 50 notes; that works under `flutter test`,
  but build the index explicitly before counting anything, or the bulk pass's
  own content reads are in the total. (5) A stale `flutter_tester.exe` holds
  `build/native_assets/windows/sqlite3.dll` and makes the *next*
  `flutter test` die with a `PathAccessException` that looks like a tool bug.
- Review pass (same day), one bug class, three fixes: **cross-event races in
  `SearchBloc`**. bloc 9.2.0 defaults to a concurrent transformer and only
  `SearchQueryChanged` overrides it, so handlers of *different* event types
  overlap and the slowest one won. (1) A private `_generation` counter, bumped
  by every handler that changes what is on screen and re-checked after the
  last await immediately before each `emit` — without it a tag open's recents
  landing after its own submitted search wiped the hits and blanked the query
  while the field still showed the tag, and a quick pass landing after
  `SearchCleared` repainted hits under an empty field. The widget test only
  passed because real drift happened to answer the recents query first. (2) A
  guard at the top of `_onQueryChanged`: a debounced quick pass for text a
  full pass is already showing returns instead of downgrading it — typing and
  pressing Enter inside 200 ms did exactly that, and carrying the query on
  `SearchSubmitted` did not prevent it. (3) `_emitRecents` no longer takes or
  emits a scope; every caller already has the right one in state, and the
  captured copy snapped the chip back when a scope change raced the opening
  recents load. Four regression cases under "races between event types" drive
  the orderings through `Completer` gates on the fakes.
- Device verification still owed: a tag tap from the editor landing in
  grouped results, and search-from-a-folder finding a note two levels down,
  both on a real device rather than the 800x600 test surface.

Goal: search has its own bloc and widget, folder scope includes
subfolders, results are grouped Titles / In text, idle shows recents.
Delivered first in the existing standalone route (tag taps use it), so it
ships user value before the in-place host exists.

Scope:
1. `lib/bloc/search/` — `SearchBloc` (sealed events + `Equatable` states,
   pattern `test/bloc/sync_bloc_test.dart`): events `SearchOpened({scope})`,
   `SearchQueryChanged(query)` (debounced 200 ms, `switchMap`),
   `SearchSubmitted()`, `SearchScopeChanged(scope)`, `SearchCleared()`.
   State: `scope` (`SearchScope.folder(folderId, name)` recursive |
   `SearchScope.everywhere`), `query`, `phase` (idle / quick / full),
   `recents` (idle), `titleHits` and `contentHits` (split by
   `SearchMatchType` — a note with both appears under Titles only), and
   `isSearching`. The bloc talks to `FolderSearchService` and
   `NoteStorageService` only.
2. `FolderSearchService`: `search`/`quickSearch` accept `Set<String>?
   folderIds` (null = everywhere). `SearchFilter` gains the set;
   `quickSearch` filters its DB page by the set — and since the page is
   one folder today, switch it to `folderId: null` + set filter, or
   better, page by the set (a `getNotesInFolders` DAO method does not
   exist; `getNotesPaginated(folderId: null)` + in-memory filter is
   acceptable for v1 with a 300-row page). The set comes from
   `FolderRepository.getAllDescendantIds(folderId)` + the folder itself,
   computed by a new `FolderStorageService.subtreeIds(folderId)`. Reuse
   `normalizeForSearch` / `searchTokens` — never a second fold.
3. Recents for idle: `loadNotesPaginated(folderId: null, pageSize: 20,
   sortOrder: updatedDesc)`, each row with its folder path
   (`getAncestors` on the note's folder through the cached repo; batch,
   dedupe by folder id). Path rendering "Training › Winter block".
4. `SearchSurface` widget (`lib/widgets/search_surface.dart`): takes the
   bloc from context, renders scope chips (`ChoiceChip`s: "<folder name>"
   / "Everywhere"; hidden when opened from root or from a tag, where
   scope is Everywhere) and the three states (idle recents; typing = quick
   hits grouped; submitted = full hits grouped) using the Slice 3
   `NoteRow` look plus a snippet line with the match highlighted from
   `SearchMatch.startIndex/endIndex`. Result tap → `toNoteEditorInstant`.
5. `SearchPage` becomes a thin host: provides the bloc, `SearchAppBar`
   with the field, body = `SearchSurface`. `initialQuery` (tag taps) →
   `SearchOpened(everywhere)` + `SearchQueryChanged` + `SearchSubmitted`.
   Back from a pushed note returns to the same bloc state (the page is
   below the note; nothing to restore).
6. Remove `SearchNotes` / `QuickSearchNotes` / `ClearSearch` and
   `OptimizedNoteSearchResults` from `OptimizedNoteBloc`, and the folder
   page's `_loadData()` after `toSearch` (`:544-549`) — the reason for it
   is gone.
7. Perf guard: `search()` loads up to 1000 notes then contents of all
   hits; cap hits at `limit` before loading content (it may already —
   verify) and add a `test/utils` or `test/services` case that a 60-hit
   query loads at most `limit` contents (count via a fake repository).
8. l10n en/de/ro: `everywhere`, `thisFolder` (fallback when the folder
   name is empty), `recent`, `titlesSection`, `inTextSection`.
9. Tests: `test/bloc/search_bloc_test.dart` against a fake service
   (debounce, scope change re-runs, split by match type, idle recents,
   clear); `test/services/folder_search_service_scope_test.dart` (recursive
   set filters, everywhere ignores the set); a `SearchPage` widget test
   (tag query opens on Everywhere with grouped results). DB: no new query.
10. Docs: COPILOT_CONTEXT "Data And Persistence Rules" search bullet
    (recursive scope, SearchBloc owns search state), this file.

Exit: analyze/test green; tag tap from the editor lands in grouped
results with Everywhere selected; searching from a folder finds notes in
its subfolders; the folder page no longer reloads after search.

```text
PROMPT — Slice 4 (navigation round 2)

Repo: D:\Alex\Programare\repos\anta, Flutter app in frontend/anta. Run every
command from frontend/anta. Load `anta-context` and `l10n`, then read
docs/navigation-round-2-roadmap.md sections 0–3 and "Slice 4" in full — it
is the spec. Slices 1–3 are merged (NoteRow widget exists); verify, then
implement Slice 4 only, on a clean tree. This slice creates the app's
first SearchBloc; it is deliberately delivered in the existing standalone
SearchPage route — do NOT host search inside the folder page yet (that is
Slice 5).

Rules: no code comments in new or edited code (existing /// stays). All
strings via AppLocalizations, en/de/ro together, `flutter gen-l10n`,
untranslated.txt empty. Never bypass Page → BLoC → Service → Repository →
DAO; the bloc talks to services only. One search normalization: reuse
normalizeForSearch / searchTokens / tokenizeForSearch from
lib/services/folder_search_service.dart, never a local toLowerCase or
diacritics fold. Bloc shape: sealed events, Equatable states, thin
handlers, debounce with the existing `debounce` transformer pattern in
optimized_note_bloc.dart. No new markdown docs. Tests expected:
test/bloc/search_bloc_test.dart against a fake service (copy the pattern
in test/bloc/sync_bloc_test.dart), a service scope test, and a SearchPage
widget test (real drift, never FakeAsync — see the harness in
test/widgets/optimized_note_editor_page_test.dart).

Facts: there is no search bloc today — SearchPage drives OptimizedNoteBloc
(SearchNotes / QuickSearchNotes / ClearSearch, OptimizedNoteSearchResults,
handlers around optimized_note_bloc.dart:266-352). Remove those after the
new bloc is wired, and remove the folder page's `_loadData()` after
toSearch. Scope today is a single folder via SearchFilter.folderId
(folder_search_service.dart ~:165); recursion = FolderDao.getAllDescendantIds
(~:386) exposed on FolderRepository. SearchMatchType {title, content}
exists; group by it. Recents = NoteStorageService.loadNotesPaginated(
folderId: null, sortOrder: updatedDesc). Folder path for a row =
FolderStorageService.getAncestors (cached repo walk; batch and dedupe).

Order: (1) service scope set + subtreeIds + tests; (2) SearchBloc + tests;
(3) SearchSurface widget; (4) SearchPage host + tag-tap path; (5) remove
search from OptimizedNoteBloc and the folder page reload; (6) perf cap on
content loads + test; (7) l10n; (8) docs. Re-grep every cited line number.

Finish with `dart analyze lib`, `flutter test`, and a summary: files
touched, bloc events/states, l10n keys, tests added, deviations with
reasons. Do not commit.
```

### Slice 5 — Search hosted in place in the browser

**Shipped 2026-09-06** on `d7f0d78`, uncommitted. Deviations from the plan
below, each deliberate:

- **The three `PopScope`s became one.** The scope says they "compose"; they
  cannot. `ModalRoute.onPopInvokedWithResult` calls **every** registered
  `PopEntry`'s callback, so nesting them would run the selection handler and
  the search handler for a single gesture — which is why the page already
  used mutually exclusive `if` branches. But branches are worse here than
  they were: swapping between two sibling `PopScope`s changes the tree shape
  above the `Scaffold`, so the whole subtree is rebuilt and the scroll
  position — the thing this slice exists to preserve — goes with it. There
  is now one `PopScope` whose `canPop` is false while any of the three
  apply, and whose handler runs them in priority order: selection, search,
  then the nested-folder swipe case. It also fixes a latent bug: the root
  page had *no* `PopScope`, so entering selection mode there used to reset
  the list to the top.
- **`_compensateBarSwap` was generalized, not duplicated.** Slice 2's
  selection compensation and this slice's "save the folder offset on enter,
  put it back on exit" are the same requirement from two sides, so the
  method now switches on a `_BarMode` (`normal` / `selection` / `search`).
  Selection keeps its exact behaviour (shift by the bar difference, add
  back anything scrolled meanwhile); search jumps to 0 on the way in —
  results open at their own top, not 300 px into someone else's list — and
  restores the saved offset untouched on the way out.
- **The jump is synchronous, not "after the first frame".** The scope asks
  for a post-frame `jumpTo` on exit; the same synchronous tick as the
  `setState` is what Slice 2 established and it is correct here too. The
  scroll activity re-evaluates itself in `applyNewDimensions` once the
  folder slivers are laid out in that same frame, and a post-frame callback
  would paint one frame at the wrong offset first. The offset-restore case
  asserts the exact pixel value.
- **`SearchSurface` needed no sliver mode.** Slice 4 already built its body
  as slivers behind the static `SearchSurface.resultSlivers(context, state)`
  and already had the chip row as its own `SearchScopeChips` widget, which
  is exactly the seam the scope asked for. The only addition is
  `SearchScopeChips.preferredHeight`, because `SliverAppBar.bottom` wants a
  height up front (one chip at the default padded tap target plus the row's
  own top padding — a widget test asserts the row fits it).
- **One `CustomScrollView`, one `RefreshIndicator`, both always mounted.**
  A second scroll view for search would be a different element and would
  take the scroll position with it, so only the `slivers` list changes;
  and lifting the `RefreshIndicator` out while searching would do the same
  thing one level up, so it stays and is disabled through
  `notificationPredicate` (pulling on results would refresh the folder list
  hidden behind them). Its `edgeOffset` drops to 0 in search mode for the
  same reason it does in selection mode.
- **Selection is unreachable from search, so the guard is untestable from
  the outside.** The scope's "entering selection exits search" case has no
  user path: the overflow menu is the only door into selection mode and it
  is off screen while searching, and long-press needs a row. The guard is
  in the listener anyway (`_leaveSearch()` before the selection swap, so
  the folder list gets its offset back before the swap measures from it);
  the test asserts the unreachability instead.
- **Review fixes (Fable, 2026-09-07).** (1) The guard above did not do
  what it said: by the time the selection listener runs, selection is
  already active, so `_compensateBarSwap()` inside `_leaveSearch()` saw
  search → *selection*, not search → normal, and saved the results' offset
  as the folder's. `_compensateBarSwap` now takes an optional explicit
  target, `_leaveSearch` pays for search → normal, and `_openSearch` pays
  for selection → normal before normal → search, so both cross-mode
  handoffs land on the folder offset — latent today, since neither path
  is reachable, but the mechanism is now right by construction. (2) The
  page unfocuses the field in `didPushNext` while searching: a route
  regaining focus hands it back to the child that had it, and a field
  regaining focus reopens the keyboard, so coming back from a result would
  have covered the results with the keyboard. Query, hits and scroll still
  survive; only the keyboard stays down until the field is tapped again.
- **No new l10n keys.** `searchInFolder` / `searchAll` are the hint,
  `clearSearch` the clear button's tooltip, and the chips and sections
  reuse Slice 4's keys. `untranslated.txt` is `{}`.
- **Test traps worth keeping.** (1) `pumpAndSettle` never returns while a
  pass is in flight — `SearchSurface` paints a `CircularProgressIndicator`
  — so every search action goes through a `flush` helper that pumps a fixed
  amount instead. (2) The field's `EditableText` puts a **second**
  `Scrollable` inside the `CustomScrollView`, so the suite's
  `scrollPosition` helper now takes the first (depth-first) match. (3) A
  fourth note went into `Loose notes` so one query can hit a title and
  three bodies and produce both sections; `quickSearch` sorts by relevance
  before `take(limit)`, so a title hit will always crowd out body hits when
  there are more than ten of them.
- Device verification still owed: the one-handed flow end to end (search,
  type, open a note, back to the same results at the same scroll, back to
  the folder, back out), and that the keyboard survives scrolling results.

Goal: the search icon turns the browser bar into a field with scope
chips; the header and bottom bar fold away; Back leaves search before it
leaves the folder; opening a result and coming back restores query, scope
and scroll.

Scope:
1. Page state `_searching` (bool) plus a page-owned `SearchBloc`
   (`BlocProvider` above the scaffold, created in `initState`, closed in
   `dispose`). Search icon → `SearchOpened(scope: folder(folderId, title))`
   or `everywhere` at root; `_searching = true`; focus the field.
2. Sliver swap: while `_searching`, the first sliver is a plain
   `SliverAppBar(pinned: true)` whose `leading` is the back button
   (exits search), `title` a `TextField` (`FocusNode` owned by the page,
   `keyboardDismissBehavior` is already manual from Slice 2), trailing
   clear button; `bottom: PreferredSize` = the chip row from
   `SearchSurface` (expose the chip row as a separate widget so it can
   sit in `bottom`). Below it, `SearchSurface`'s body slivers (give the
   surface a sliver mode next to its box mode, the way
   `agenda_list_view.dart` documents its dual mode). The bottom bar is
   hidden while searching. The large sliver and list return on exit with
   the previous scroll offset (keep the `ScrollController`; save the
   folder list offset on enter, `jumpTo` on exit after the first frame).
3. Back handling: `PopScope(canPop: !_searching)`; system back or the bar
   arrow exits search first (bloc `SearchCleared`, `_searching = false`),
   and only a second back leaves the folder. The existing nested
   `PopScope` (swipe-kill) and the selection `PopScope` compose with it —
   selection mode and search mode are mutually exclusive (entering one
   exits the other).
4. Result tap pushes the note as today; the page stays mounted below,
   so query/scope/scroll survive — but `didPopNext` must **not** reset
   search (it currently re-reads settings; keep that, skip anything that
   reloads the list while `_searching`). The `SearchBloc` refreshes hits
   on `didPopNext` (`SearchSubmitted` again if `phase == full`, quick
   otherwise) so an edited note's snippet is fresh.
5. Root: chips hidden, scope Everywhere.
6. Editor: unchanged — its search icon is find-in-note; state the
   asymmetry in the docs. Tag taps keep the standalone route.
7. Launch restore: search is screen state, deliberately not a
   `NavDestination`; nothing to do, but add a test that the recorded
   stack does not change when search opens or closes.
8. l10n: `searchInFolder` / `searchAll` already exist for the hint.
9. Tests (browser harness): icon enters search with chips and recents;
   typing shows grouped hits; back exits search before folder (NavigatorObserver
   sees no pop on the first back); scroll offset restored on exit;
   selection mode entry exits search; the recorded location stack is
   untouched.
10. Docs: COPILOT_CONTEXT browser + search bullets, this file.

Exit: analyze/test green; device: one-handed flow — search icon, type,
open a note, Back returns to the same results at the same scroll, Back
again clears search, Back again leaves the folder; the keyboard does not
close while scrolling results.

```text
PROMPT — Slice 5 (navigation round 2)

Repo: D:\Alex\Programare\repos\anta, Flutter app in frontend/anta. Run every
command from frontend/anta. Load `anta-context` and `l10n`, then read
docs/navigation-round-2-roadmap.md sections 0–3 and "Slice 5" in full — it
is the spec. Slices 1–4 are merged (SearchBloc and SearchSurface exist);
verify, then implement Slice 5 only, on a clean tree.

Rules: no code comments in new or edited code (existing /// stays). All
strings via AppLocalizations, en/de/ro together, `flutter gen-l10n`,
untranslated.txt empty. Never bypass Page → BLoC → Service → Repository →
DAO. No new markdown docs. Tests expected in
test/widgets/optimized_folder_content_page_test.dart (real drift, never
FakeAsync) plus a navigation-history assertion using the patterns in
test/widgets/navigation_history_observer_test.dart.

Framework facts (Flutter 3.44.2): SliverAppBar.large builds `title` twice,
so search mode must swap the whole first sliver for a plain
SliverAppBar(pinned: true) with the TextField as title and the chip row in
`bottom:`; never put the field in the large bar. The CustomScrollView must
keep keyboardDismissBehavior: manual or scrolling results closes the
keyboard. Search is screen state, not a route: it must not be stamped as a
NavDestination and must not change the recorded location stack. The page
stays mounted under a pushed note, so state survives by itself — do not
add a restore mechanism; do make sure didPopNext does not reset it.
PopScope: canPop is false while searching; back exits search first.
Selection mode and search mode are mutually exclusive.

Order: (1) page-owned SearchBloc + _searching state + PopScope; (2) sliver
swap with field, chips in bottom, SearchSurface sliver mode, bottom bar
hidden; (3) scroll offset save/restore on enter/exit; (4) didPopNext
refresh; (5) tests; (6) docs. Re-grep every cited line number.

Finish with `dart analyze lib`, `flutter test`, and a summary: files
touched, tests added, deviations with reasons, and a note on how the three
PopScopes compose. Do not commit.
```

### Slice 6 — Root smart rows (All notes, Recent) and polish

Goal: the root gains "All notes <count>" and "Recent" rows; both pages
restore on launch; the leftovers of the redesign are closed.

Scope:
1. `AllNotesPage` (`lib/pages/all_notes_page.dart`): the Slice 2 sliver
   bar (back, title "All notes", search icon → in-place search with scope
   Everywhere reusing Slice 5's mechanics — extract the search-host
   mixin/controller from the folder page if the duplication exceeds a
   screen), `NoteRow` list from `OptimizedNoteBloc`
   `LoadNotesPaginated(folderId: null, sortOrder: <notes sort pref>)`
   with each row showing its folder path as the eyebrow of the subtitle;
   no folders, no reorder, no bottom bar; card menu rows (rename, move,
   share, delete) work as in a folder. Confirm `OptimizedNoteBloc` and
   `NoteBlocFilters.forFolder` accept `null` for "all" (they may treat
   null as "no filter" already — verify, do not assume).
2. `RecentNotesPage`: same page with a fixed `updatedDesc` order and a
   cap (50) — implement as a mode of `AllNotesPage`, not a copy.
3. Root rows: first group above "Folders": "All notes" with the count
   from `NoteDao.getNoteCount(null)` (through repository → service; refresh
   on note change streams), and "Recent" (no count). Rows use the
   `FolderRow` look with the mock's icons.
4. Launch restore: two additive `NavDestinationKind` members `allNotes`,
   `recentNotes` (no params, `isNoteSubstrate` true so a note above them
   restores; `reopensDrawerOnPop` false). No `stackVersion` bump — the
   list semantics are unchanged. Extend `nav_destination_test.dart`
   (encode/decode round trip, unknown-kind truncation still holds) and
   the replay path in `AppNavigator._pageFor`.
5. Polish, each a one-liner in the decision log: trim
   `drawerEdgeDragWidth` on both pages if device testing shows the
   Android back gesture opening the drawer (start at 16 px + inset,
   keep the setting-driven `drawerEnableOpenDragGesture`); delete the
   duplicate `settings` key in the ARBs if nothing references the
   second one; remove `UnifiedAppBar` if nothing else uses it; reword
   `emptyFoldersHint` if it still mentions a "+" button.
6. l10n en/de/ro: `allNotes`, `recent`, `allNotesCount` (plural, if the
   trailing number needs a label — otherwise a bare number).
7. Tests: root shows the two rows with the live count; `AllNotesPage`
   lists notes from several folders with paths; restore round trip for
   the two kinds; the Recent cap.
8. Docs: COPILOT_CONTEXT "Navigation And Launch Restore" (new kinds and
   why no bump), browser paragraph, this file's status → DONE, and the
   mock artifact's "Your call" answers recorded in section 1 here.

Exit: analyze/test green; device: All notes with 500 notes scrolls
smoothly with paths; kill the app on the Recent page and relaunch — it
comes back; drawer still opens by swipe on every page.

```text
PROMPT — Slice 6 (navigation round 2)

Repo: D:\Alex\Programare\repos\anta, Flutter app in frontend/anta. Run every
command from frontend/anta. Load `anta-context` and `l10n`, then read
docs/navigation-round-2-roadmap.md sections 0–3 and "Slice 6" in full — it
is the spec, and read the "Navigation And Launch Restore" section of
COPILOT_CONTEXT.md before touching NavDestination. Slices 1–5 are merged;
verify (in-place search works in a folder), then implement Slice 6 only,
on a clean tree.

Rules: no code comments in new or edited code (existing /// stays). All
strings via AppLocalizations, en/de/ro together, `flutter gen-l10n`,
untranslated.txt empty. Never bypass Page → BLoC → Service → Repository →
DAO. NavDestinationKind names are persisted: add members, never rename or
reorder existing ones, no stackVersion bump for an additive kind. Never
await a push during restore replay. No new markdown docs. Tests expected:
browser harness, a new all_notes_page widget test (real drift, never
FakeAsync), test/models/nav_destination_test.dart and the restore replay
tests extended.

Facts: NoteStorageService.loadNotesPaginated(folderId: null) already lists
every folder's notes; NoteDao.getNoteCount(null) is the global count;
FolderStorageService.getAncestors gives a row's path (batch + dedupe by
folder id). Verify whether OptimizedNoteBloc / NoteBlocFilters.forFolder
treat null as "all" before relying on it. RecentNotesPage is a mode of
AllNotesPage, not a copy. Extract the in-place search host from the folder
page only if sharing it saves more than a screen of duplication.

Order: (1) count + all-notes plumbing through service/repository (no new
SQL expected — stop and say so if you find you need one); (2) AllNotesPage
with the recent mode; (3) root smart rows; (4) NavDestination kinds +
restore replay + tests; (5) polish items, each recorded as a decision-log
line; (6) l10n; (7) tests; (8) docs, roadmap status → DONE. Re-grep every
cited line number.

Finish with `dart analyze lib`, `flutter test`, and a summary: files
touched, l10n keys, the two new kinds, tests added, polish items taken or
skipped with reasons. Do not commit.
```

---

## 5. Sequencing, execution model, verification

- **Execution model**: each slice is one fresh Opus session with its
  prompt; the owner commits between slices. Fable's job ends here and
  resumes only for a review pass after Slices 3 and 5 (the two with the
  most surface): a five-pass read-only review as in
  `live-editor-review-and-slices-2026-09.md`, fixes applied by Opus.
- **Precondition**: commit the Session 9 tree (`74b5b67` + 52 files)
  first. Every prompt refuses a dirty tree.
- **Estimated size** (Opus sessions): S1 medium, S2 medium, S3 large,
  S4 large, S5 medium, S6 medium. S3 and S4 are the ones most likely to
  need a second session.
- **Device checklist after S6** (Android, one hand): root → folder →
  subfolder → note → wiki link → note: Back four times returns to root;
  overflow → Open folder from the second note lands on its folder with
  no intermediate flicker; long-press Back at depth three → Folders;
  search from a subfolder finds a note two levels down; TalkBack: back
  button announces its custom action; drawer opens by swipe on every
  screen and by the Settings row in every menu; kill and relaunch from
  the Recent page.
- **Rollback**: each slice is UI-only except S3 (one DAO query, no
  schema) and S6 (two enum members). Reverting S6 after users have
  parked on All notes truncates their restored stack at that entry —
  harmless by the decoder's design.

## 6. Deferred / rejected

- **Predictive back** (Android 14+ animations): still not enabled in the
  manifest; the nested `PopScope`s would need `canPop` truthfulness
  first. Out of scope, unchanged from the mock.
- **Navigation bar instead of the drawer**: M3's preference at compact
  width, rejected by the owner on 2026-09-03; the drawer stays a
  settings list.
- **`SearchAnchor` / `SearchBar`**: no slot for scope chips under the
  field and a `SearchController` lifecycle that does not survive pushing
  a result (flutter#154051, #155180). Hand-rolled sliver swap chosen.
- **Two reorderable slivers** (folders, notes): a drag cannot cross
  them, which reads as a bug; one list with a clamp instead.
- **Non-animated `popUntil`**: flutter#57304 is open; removeRoute + pop
  is the workaround and stays.
- **Folder route carrying `parentTitle`**: rejected in favour of the
  page fetching `getAncestors` itself — no `NavDestination` param, no
  restore-replay change, and the long-press menu needs the full chain
  anyway.
