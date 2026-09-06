# Navigation Round 2 — Roadmap & Slice Prompts (2026-09-06)

**Status: Slice 1 DONE (2026-09-06, on `b0a8b87`, uncommitted). Slices 2–6
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
