# The folder browser's sheets on the UI language — design record (2026-11-27)

**Status: PROPOSED — nothing is built.** A designer's judgement and specification, made from renders of the surfaces as they are on 2026-11-27 while the owner was away, of tier B of `docs/ui-language-adoption-roadmap.md`: the sheets and pickers that open from the folder browser. It waits for his answer on the lettered decisions of §5, and on the master's open decision 2 (the confirm dialog), which it takes a position on. The renders, the measurements and the mock are in `build/session-2026-11-27/browser_sheets/` (git-ignored).

Contents: §0 What the master's §4.2 says that is no longer true · §1 Diagnosis · §2 Spec · §3 What stays · §4 Risks · §5 Decisions · §6 Renders and measurements for the review · §7 Slices · §8 How to run this

How the evidence was made: real-font renders (Roboto and MaterialIcons from the SDK cache) of the real widgets, in `AppTheme.light()` and `dark()`, on 360 × 780 and 412 × 915 with a 24 dp status bar and a 24 dp gesture bar, at text scales 1.0, 1.3 and 2.0, in en, de and (for the proposal) ro. The sort sheets, the long-press sheet and move history were reached through the browser page itself on the page suite's harness (a real database, real rows, a real long press). The move picker was opened through `showFolderPickerDialog` on its own suite's database helper, the label picker through `showLabelPickerSheet`, and the dialogs through `AppDialogs`. The proposal was built once from the language's primitives with the real strings and rendered on the same matrix. The scale is linear (`TextScaler.linear`), so a 2.0 render over-sizes the large roles a little compared with Android's curve. Every height below is `tester.getRect`; every ratio comes from the tokens.

## 0. What the master's §4.2 says that is no longer true

Re-read against the tree on 2026-11-27 (the worktree copy of `main` plus the session's uncommitted work):

| §4.2 / master line | Then | Today |
| --- | --- | --- |
| Browser page, 2,444 lines | | 3,252 lines |
| Folder and note rows, `content_rows.dart` 380 lines | | 529 lines; `folder_row.dart` 446, `note_row.dart` 479 |
| Row long-press sheet, `content_rows.dart:272–345`, ~75 lines, "HR + MAT" | 40 × 4 pill, 16 / 600 title, `Divider`, `ListTile` | Now `content_rows.dart:260–422` (`RowAction`, `showRowActionSheet`, `_OneNodeWhenOff`). Still the hand-rolled pill (40 × 4 in full `onSurfaceVariant`), a centred 16 / 600 title and `ListTile`s, but it has grown the partner states: an action that is disabled in place with a caption, a tick on the share row, a `headerBuilder` slot that holds the colour strip (or "Only Ana can change this" on the partner's row), and ids on every action (`row-action-*`). Its bottom padding is already `max(viewInsets, viewPadding)`. It is in no case of `sheet_bottom_clearance_test.dart`. `guide_sync_try_folder.dart` opens it too. |
| Sort chooser + two sort sheets, `…page.dart:1444–1674`; "the selection in bold primary, no checked semantics" | | Now `…page.dart:1897–2127`. The chosen row is bold `primary` **and** carries a trailing ✓. The semantics are worse than "none": the chosen `ListTile` reports `hasSelectedState` without `isSelected`, so a screen reader is told it is *not* selected (measured on "Last updated (Descending)"). A seventh note order and a fifth folder order (Label) were added by the colour-labels work. The only ids are none. |
| Move history, 203 lines, "HR + MAT (`DraggableScrollableSheet`)", tests none | | Unchanged: 203 lines, still a `DraggableScrollableSheet` (0.45 / 0.3 / 0.75), no ids, and still no widget suite (`move_history_service_test` covers the service). |
| The label picker | Not listed in §4.2 | `showLabelPickerSheet` in `label_swatch_strip.dart` — the colour-labels work did **not** put it on the language. It is the same hand-rolled chrome as the long-press sheet (pill, centred 16 / 600 "Label", `Divider`) around `LabelSwatchStrip`. It has a suite (`label_picker_sheet_test`, 182 lines, its own clearance case) and the id `label-picker`. It is opened by the selection bar's Label **and by the note editor** (`note_actions.dart:194`), so migrating it moves an editor surface too. |
| Move-to folder picker, `folder_picker_dialog.dart`, `AlertDialog`, 743 lines, no tests | | 980 lines; three purposes now (move, the Sharing page's "Share a folder", "Copy to my notes"), five call sites (`move_coordinator.dart` ×3, `shared_note_copy.dart`, `share_folders_sheets.dart`); a suite of its own (`folder_picker_dialog_test`, 713 lines); ids `folder-picker-search / -confirm / -cancel / -up / -row-<id>`, two of them targeted by the share flows `04_n` and `04_o`; it already reads `FormCaptionSlot` and `FormMetrics` for the share refusal and clamps its title at `dialogTitleMaxTextScale`. Still an `AlertDialog` with a fixed 460 dp body. |
| New folder / rename / delete / import progress via `app_dialogs.dart`, tests none | | `AppDialogs` has a suite (`app_dialogs_test`, 647 lines). Since 2026-11-07 every builder scrolls its body and clamps the title at 1.2 and the actions at 1.6. "Import progress" in the browser is `AppDialogs.showLoading` (spinner and a line), not `AppDialogs.progress`. |
| Master §3 decision 2: "`app_dialogs.dart:53–61, 74–85`; `AppDialogs` has no test suite" | | `confirm` is now `app_dialogs.dart:48–108` (the 48 dp icon at 70–78, the error fill at 91–98); the suite exists. The browser's own deletes pass no icon, so the browser shows the error-filled confirm without the 48 dp icon. |
| Master §0: "Outside the calendar no area has a QA fixture or saved flows" | | The browser has a suite: `tool/qa/flows/browser/` (`00_root`, `01_note_edit`, `02_reorder`) on `tool/qa/fixtures/basic.json`. None of its flows opens a sheet of this tier other than the long-press sheet's Select; the share suite's `04_n` / `04_o` open the move picker. |

## 1. Diagnosis

Renders: `browser_sheets/now/<state>_<cell>.png`, strips of five cells in `browser_sheets/montage/now_<state>.png` (light 1.0 en · dark 1.0 en · light 1.3 de · light 2.0 de · dark 2.0 de, all 360 × 780); numbers in `browser_sheets/now/measurements.txt`.

**The move-to picker** (`montage/now_picker_*.png`) — off the language, and broken with the keyboard up.
- A dialog whose body is a fixed 460 dp. With the keyboard up (320 dp) it overflows in every 360-wide cell: by 53 px at 1.0 en, 80 at 1.3 en, 118 at 1.3 de, 151 at 2.0 de, and by 16 px even at 412 × 915 in de 2.0 (`now_picker_keyboard.png`: at de 2.0 one result row is left and the second is cut through). A picker is a bottom sheet in the language ("Which idiom a surface takes").
- Targets under 48: the Up button measures 24 × 24 inside a 32 × 32 constraint; a path segment 60 × 24; the recents strip is a 36 dp `ListView`, so at 2.0 the chip is cut through its text (`now_picker_root.png`, cells 4–5). App rule 48 dp; design-practices §2.
- Three type sizes and three boxes compete above the list: an outlined search field, an outlined grey "Currently in" box with a 12 px glyph and an `labelSmall` overline, an `labelSmall` "Recent" overline and a 600-weight "SUBFOLDERS OF …" overline in a second style. The current segment is `primary` w700. Off the ramp (the language's section label is 11 / 500 / 0.88; emphasis is weight 500 and the `onSurface` role).
- Folder rows are dense `ListTile`s (48 dp, body text smaller than the browser's 15). Search results name a folder without where it is: two "Week 1" folders cannot be told apart (`now_picker_search.png`).
- The confirm sits bottom-right under a stacked Cancel at large text (`now_picker_root.png`, cells 4–5: "Abbrechen" above a two-line "Nach Stammordne…").

**The sort chooser and the two sort sheets** (`now_sort_chooser_folder.png`, `now_sort_folders.png`, `now_sort_notes.png`) — off the language.
- Two hops to one choice: ⋮ → Sort by → a chooser of two `ListTile`s → a sheet. No handle, no ✕, no title in the chooser; the sort sheets' title row is a 24 dp icon beside `titleMedium` 16 / 500.
- The note sheet is capped by Material's 9/16 (438.8 dp on 360 × 780): its seventh row, Label, is below the fold at 1.0 en, and at de 2.0 four of seven are visible.
- The choice is carried by bold `primary` text and a ✓ with **no** checked or selected state in semantics — the chosen row reports `hasSelectedState` without `isSelected`, so it is announced as not selected (design-practices §7; app rule: choices are `FormCheckRow` / `FormRadioRow`).
- Glyphs name the value, not the field (two identical A→Z glyphs for A-Z and Z-A, two calendars for the two date orders) — "a row's glyph names the field, never the value".
- In a folder on manual order (`positionAsc`), no row is ticked and nothing says why.

**The long-press sheet** (`now_longpress_folder.png`, `_note`, `_longname`) — chrome off the language, rows nearly on it.
- Hand-rolled chrome: a 40 × 4 pill in full `onSurfaceVariant`, a centred 16 / 600 title (off the ramp; the language's title is 17 / 500, left-aligned, beside a ✕), full-width `Divider`s.
- Capped at 9/16 (438.8 dp at 360 × 780): Delete sits on the bottom edge at 1.0 and, at de 2.0, Send a copy and Delete are below the fold — the destructive action is the one you have to scroll to find.
- `ListTile`s at 56 dp with 16 / 400 labels and `onSurfaceVariant` icons, where every language sheet uses 48 dp rows, 15 / 400 labels and 22 px `primary` glyphs.
- A long name is cut to one line ("Oberkörper und Rum…" at 2.0) — the title is the only thing on the sheet that says which row was pressed.
- What is already right and stays: the ids, the disabled-in-place partner rows with a full-strength caption, the bottom clearance, Select first.

**Move history** (`now_history_entries.png`, `now_history_empty.png`) — off the language and broken at de 2.0.
- At de 2.0 the header's "Verschiebeverlauf" is squeezed by the Clear button into a column four syllables tall, broken mid-word ("Vers / chieb / everl / auf"); the first entry's `ListTile` is 493 dp tall, its title squeezed by the trailing time and Undo (WCAG 1.4.4; app rule: no broken word at 2.0).
- Contrast from the tokens over the sheet's `surfaceContainerLow`: the "Moved to …" line is `onSurfaceVariant` at 70 % = **3.86:1** in light (below 4.5:1); an undone entry's title at 40 % = 2.00:1 light / 2.71:1 dark and its time and "Undone" at 30 % = **1.65:1** light / 2.08:1 dark — the line that says what happened is the one nobody can read. The handle at 40 % is 2.00:1 (that is also `FormSheetHandle`'s alpha app-wide; outside this tier).
- The Undo `IconButton` is `VisualDensity.compact`: 40 × 40.
- A draggable sheet at 45 % with an empty state floating in its middle; Clear is hidden, not disabled, when there is nothing to clear; a strikethrough carries "undone" alongside the faded colour.
- No ids, no suite.

**The label picker** (`now_label.png`) — fine in function, chrome off the language: the same pill, centred 16 / 600 title and `Divider` as the long-press sheet. The strip's cells are 41 × 48 dp at 360 (47.5 at 412) by the strip's own documented compromise; it stays.

**The dialogs** (`now_dialog_*.png`) — on `AppDialogs`, which is the language's dialog layer; they scroll and clamp correctly at de 2.0 (the 2026-11-07 work). One gap, master decision 2: the destructive confirms (delete folder, delete note, delete selection, clear move history) are an error-filled `FilledButton` beside a `TextButton` cancel, where the language's rule and `confirmDiscard` are a `FilledButton.tonal` confirm. The error fill is measured fine for contrast (white on `error` 6.54:1 light; dark draws `onPrimary` on `error`, not `onError` — legible, but not the pair M3 names). Rename opens with the caret at the end of the old name, and New folder accepts an empty name and drops it silently.

## 2. Spec

### 2.1 The shared part — every sheet of this tier

| Element | Proposed | Constant / token |
| --- | --- | --- |
| Shape | **Sub-sheet** (`showModalBottomSheet(isScrollControlled: true, useSafeArea: true, showDragHandle: false, backgroundColor: pageGround, shape: top radius sheetRadius)` → `ConstrainedBox(maxHeight: height × sheetHeightFactor)` → `Column(min, stretch)`) for the long-press sheet, the label picker, the sort sheet and move history. **Filler** (the same route flags → `FractionallySizedBox(heightFactor: sheetHeightFactor)` → `Column(stretch)`, route drag, no `PopScope`, no hairline) for the move picker. | `FormMetrics.sheetRadius` 28, `sheetHeightFactor` 0.92, `SurfaceRoles.pageGround` |
| Handle | `FormSheetHandle` (32 × 4 in a 22 dp strip) | `handleStripHeight`, `handleWidth`, `handleHeight` |
| Header | `FormSheetHeader`: ✕ `close_rounded` in a 48 dp target · left-aligned title 17 / 500 `onSurface` · one trailing action or `SizedBox.shrink()` with `trailingInset: headerActionInset` | `headerHeight` 48, `headerTitleSize` 17, `headerActionInset` 8 |
| ✕ tooltip | `close` where the sheet acts and returns nothing (long press, sort, history); `cancel` where it returns a pick (label picker, move picker) | strings exist |
| Body | `SingleChildScrollView` padded `groupInset, bodyTop, groupInset, bodyBottom + clearance` (the picker: its list and its footer, §2.6) | `RowMetrics.groupInset` 16, `FormMetrics.bodyTop` 8, `bodyBottom` 24 |
| Clearance | `max(MediaQuery.viewInsetsOf.bottom, MediaQuery.viewPaddingOf.bottom)` on the scroll view's bottom padding, or on the picker's footer; every sheet joins `sheet_bottom_clearance_test.dart` | — |
| Groups | `FormRowGroup` on `rowGroup`, radius 14, gap 18, hairline `rowDivider` at the row's indent; `FormSectionLabel` 11 / 500 / 0.88 `onSurfaceVariant` uppercase over a group only where a sheet has two groups | `RowMetrics.groupRadius`, `groupGap`, `SurfaceRoles.rowGroup`, `rowDivider` |
| An action row | `FormPickerRow(glyph:, label:, onTap:, showChevron: false, identifier:)` — glyph 22 `primary`, label 15 / 400 `onSurface`, 48 dp min; disabled = `enabled: false` (38 % on glyph and label, the caption full, announced disabled); with a caption `checkRowShape: true` (62 dp). Destructive: `glyphColor` and `labelColor` `error`. | `rowMinHeight` 48, `twoLineRowMinHeight` 62, `disabledOpacity` 0.38 |
| A choice row | `FormCheckRow(exclusive: true)` — no glyph, plain indent, the ✓ 20 `primary` in a 48 dp slot, weight 500 on the chosen label; semantics `inMutuallyExclusiveGroup` + `checked` | `trailingIconSize` 20, `trailingButtonSize` 48 |
| An entry row (history) | `FormPickerRow(glyph:, label:, value:, caption:, onTap: null, trailingButton: FormTrailingButton)` — a read row with a second target | — |
| Semantics refresh | `FormSheetSemanticsRefresh` around the box of a sheet that resizes on a dialog's answer: **move history only** (Clear empties it). The long-press and sort sheets pop before anything opens above them. | — |
| Scale | Rows grow with their text (never ellipsize a label); the header stays one row except where §2.2 / §2.5 opt into `stackTitleAtLargeText` | — |

Re-read against the must-not-change list (§3): every action, its order and what it does; the gestures that open each surface; what a sort choice stores; move and undo; every flow id; no string changes — none is needed (the sort sheet's group labels reuse `folders` / `notes`, its root title `sortFolders`, the ✕ tooltips `close` / `cancel`).

### 2.2 The long-press sheet (`showRowActionSheet`, `content_rows.dart`)

| Element | Current | Proposed |
| --- | --- | --- |
| Route | `showModalBottomSheet` default (9/16 cap, `surfaceContainerLow`) | sub-sheet (§2.1) |
| Handle | 40 × 4, `onSurfaceVariant` 100 %, 12 dp margins | `FormSheetHandle` |
| Title | centred, 16 / 600, one line, ellipsis, then a full-width `Divider` | `FormSheetHeader(✕ close · item name · SizedBox.shrink, stackTitleAtLargeText: true, leadingIdentifier: row-action-close)`; the name stacks under the ✕ on two lines (`headerTitleMaxLines`) whenever it does not fit beside it, at any scale (D-H). No divider. |
| Colour strip | `LabelSwatchStrip` between two `Divider`s, 8 dp above and below | a band on the ground, no group (D-I): `LabelSwatchStrip(padding: EdgeInsets.zero)` directly in the body (the body's `groupInset` is the strip's edge), `FormMetrics.swatchRowBottomPadding` (12) below it; cells stay (W − 32) / 8 = 41.0 dp at 360. Id on the band: `row-action-labels` (Slice 0). |
| Partner line | `SharedReadOnlyLine(banded: false)` in the same slot | unchanged, in the band's slot |
| Actions | `ListTile` 56 dp, 16 / 400, icon `onSurfaceVariant` | one `FormRowGroup` of `FormPickerRow` action rows (§2.1) in today's order: Select · Rename · Move to folder · [Share with / Shared with {name}] · Send a copy · [Copy to my notes]. Glyphs as today, rounded (`check_circle_outline_rounded`, `edit_rounded`, `drive_file_move_outlined`, `group_rounded`, `share_rounded`, `content_copy_rounded`). |
| The share row (paired, folder) | `ListTile` with a trailing ✓, the caption as subtitle | `FormCheckRow(glyph: group_rounded, label: share.label, caption: share.caption, checked: share.checked, onChanged: share.enabled ? (_) => onPartnerShare : null, identifier: row-action-share)` — a checkbox, so the state is spoken (D-J) |
| Delete | last `ListTile`, `error` | its own one-row group under the actions (D-G): `FormPickerRow(glyph: delete_rounded, glyphColor: error, labelColor: error, label: delete, showChevron: false, identifier: row-action-delete)`; disabled on the partner's row as today |
| Disabled (partner) | `_OneNodeWhenOff` + `ListTile(enabled: false)` | `enabled: false` on the row; `_OneNodeWhenOff` retires |
| `headerBuilder` API | builder between dividers | kept (the strip still pops the sheet's own context) |

Measured (`proposed/measurements.txt`): 447 dp at 1.0 (folder, note), 507 for a long name at 1.0 and for every row at de 2.0, 617 for a long name at de 2.0, 638 / 640 for the partner's and a shared folder's sheet at de 2.0 — all under the 717.6 dp clamp, so nothing scrolls in any cell (today Delete is below the fold at de 2.0). Rows 48 dp at 1.0 and 1.3, 52 at 2.0.

### 2.3 The label picker (`showLabelPickerSheet`)

Sub-sheet; `FormSheetHeader(✕ cancel · labelAction · SizedBox.shrink, leadingIdentifier: label-picker-close)`; the body is the strip band of §2.2 under `Semantics(identifier: label-picker)` as today. 174 dp at every scale (the header is the only text). Resolves to the pick or `null` as today. The editor's Label (`note_actions.dart`) gets the same sheet.

### 2.4 The sort sheet (replaces `_showQuickSortOptions`, `_showFolderSortOptions`, `_showNoteSortOptions`)

| Element | Current | Proposed |
| --- | --- | --- |
| Way in | ⋮ → Sort by → chooser → Sort folders / Sort notes → sheet | ⋮ → Sort by → **one sheet** (D-D) |
| Header | none (chooser); icon + `titleMedium` (sheets) | ✕ `close` · "Sort by" (`sortBy`) in a folder, "Sort folders" (`sortFolders`) at the root · nothing; id `browser-sort-close` |
| Groups | one sheet per kind | in a folder: `FormSectionLabel(folders)` + a group of the five folder orders, `FormSectionLabel(notes)` + a group of the seven note orders; at the root: the folder group alone, unlabelled (a one-group sub-sheet carries none) |
| Rows | `ListTile` with a glyph, bold `primary` + ✓ when chosen | `FormCheckRow(exclusive: true)`, no glyph, labels as today (`'${sortByName} (A-Z)'` …); id per order: `browser-sort-folder-name-asc / -name-desc / -created-desc / -created-asc / -label`, `browser-sort-note-title-asc / -title-desc / -updated-desc / -updated-asc / -created-desc / -created-asc / -label` (Slice 0 puts them on today's tiles) |
| A pick | pops, then `_sortFoldersBy` / `_sortNotesBy` | the same: pops, then writes (D-E) |
| Manual order | no row ticked | the same (D-F) |
| Where it lives | three methods in the page | one widget, `lib/widgets/browser_sort_sheet.dart` (`BrowserSortSheet.show(context, folders:, notes:)` returning the picked order or `null`), so the page keeps only the writes |

Measured: at the root 370 dp (1.0) / 470 (de 2.0). In a folder the content (≈ 760 dp at 1.0) reaches the 717.6 dp clamp on 360 × 780, so the last note row comes in with a scroll of about 40 dp; at 412 × 915 it is 770 dp, whole. At de 2.0 the date rows wrap to two lines (92 dp) and the sheet scrolls by design. Rows 48 / 52 / 92 dp.

### 2.5 Move history (`move_history_sheet.dart`)

| Element | Current | Proposed |
| --- | --- | --- |
| Route | `DraggableScrollableSheet` 0.45 / 0.3 / 0.75 | sub-sheet, content-tall under the clamp, wrapped in `FormSheetSemanticsRefresh` |
| Header | history glyph + `titleMedium` + `TextButton` Clear, hidden when empty | ✕ `close` · "Move history" · `FormHeaderTextButton(clearHistory, color: error, onPressed: empty ? null : _confirmClear, identifier: move-history-clear)` — disabled in place when empty (D-K); `stackTitleAtLargeText: true` (the title drops under the ✕ and Clear as soon as they do not fit, from de 1.3) |
| List | `ListView.builder` of dense `ListTile`s | `Flexible(ListView.builder(shrinkWrap: true, padding: groupInset, bodyTop, groupInset, bodyBottom + clearance))` of `FormRowShell(first:, last:, trailingGap: false)` rows — lazy: 300 entries build 9 rows (measured) |
| Entry | `ListTile`: glyph, 500 title, 12 px subtitle at 70 %, 11 px time, compact Undo | `FormPickerRow(glyph: note → description_outlined, folder → folder_outlined; label: item name; value: the time ("5m"); caption: movedToTarget(target) or undone; onTap: null; trailingButton: FormTrailingButton(undo_rounded, tooltip: undo, color: primary, identifier: move-history-undo-<index>))` — label 15 / 400 `onSurface`, value 15 `onSurfaceVariant` tabular, caption 13 `onSurfaceVariant` 100 % (8.88:1 light, 9.56:1 dark on `rowGroup`), Undo 48 × 48 |
| Undone entry | strikethrough, 40 % / 30 % alphas | `enabled: false`: glyph, label and value at 38 %, the caption "Undone" at full strength, Undo disabled in place; no strikethrough |
| Empty | centred text in a 45 % sheet | `FormCaption(noMoveHistory, padding: groupCaptionPadding)` under the header; 144 dp (1.0), 221 (de 2.0) |
| Ticker, stream | 1-minute `setState`, the service's `changes` | unchanged |

Measured: 400 dp with three entries at 1.0; at de 2.0 the clamp (717.6) and the list scrolls. At de 2.0 the header's Clear ellipsizes ("Verlauf lösc…") at `headerActionMaxShare`; its node keeps the whole word.

### 2.6 The move-to picker (`folder_picker_dialog.dart` → `folder_picker_sheet.dart`)

A **filler** (D-A): the body switches between browse and search and is a live-search list.

| Element | Current | Proposed |
| --- | --- | --- |
| Shape | `AlertDialog`, body fixed 460 dp | filler box, `sheetHeightFactor` (695.5 dp of 780 after the status bar; 819.7 of 915) |
| Header | dialog title clamped at 1.2 | ✕ `cancel`, id `folder-picker-cancel` (moved from the Cancel button) · the purpose title (`moveToTitle` / `shareAddFolder` / `sharedNoteCopy`) · nothing; one row at every scale, the title ellipsizing at de 2.0 (D-B) |
| Search | outlined `TextField`, 20 px glyph, compact ✕ | a pinned band: `FormRowGroup(trailingGap: false)[FormSearchRow(hint: searchFolders, clearTooltip: clearSearch, identifier: folder-picker-search)]`, `bodyTop` (8) below it |
| Recents | `labelSmall` overline + a 36 dp horizontal `ListView` of `ActionChip`s | `FormSectionLabel(recentDestinations)` + a horizontal `SingleChildScrollView` row of `FormChip(glyph: history_rounded, selected: false, onTap: confirm)` at `chipSpacing` 8 — 48 dp targets, the chip growing past 160 % instead of being cut; ids `folder-picker-recent-<index>` |
| Location | outlined `surfaceContainerHigh` box, "Currently in" overline, 24 dp Up, 24 dp segments, current in `primary` w700 | a band on the ground (D-C): `FormTrailingButton(arrow_upward_rounded, tooltip: back, onPressed: root ? null : up, identifier: folder-picker-up)` then a horizontal scroller (`reverse: true`, so the current folder is in view) of segments — each a 48 dp-tall ink well, `FormMetrics.pickerCrumbPadding` (new, `EdgeInsets.symmetric(horizontal: 4)`), 15 / 500, ancestors `primary` (they are links), the current one `onSurface` and not a button, `FormChevron` (18 `outline`) between them. The "Currently in" overline and the box retire. |
| List label | "SUBFOLDERS OF X", 600, its own style | `FormSectionLabel(subfoldersOf(name))` |
| Folder rows | dense `ListTile`, `folder` glyph, a passive chevron | `FormRowGroup` of `FormPickerRow(glyph: folder_rounded, glyphColor: AppColors.folderIcon, label: name, onTap: drill in, identifier: folder-picker-row-<id>)` with its chevron; the share sign after the name through `FormPickerRow.labelTrailing` (the tier's one primitive change, mirroring `FormMeterRow.labelTrailing`), the "Shared with" label kept on the node |
| Search results | `ListTile`s, a tap confirms | the same group without a chevron (`showChevron: false`) — a result commits, a browse row drills; the share pick's refused result `enabled: false` with `shareFolderAlready` as its caption at full strength |
| Empty / none / loading | centred text in 24 dp padding; a full-size spinner | `FormCaption(noSubfolders / noFoldersAvailable / noFoldersFound, padding: groupCaptionPadding)`; a `rowBusyIndicatorSize` spinner centred in the list |
| Confirm | `TextButton` Cancel + `FilledButton.icon` "Move to X" (two lines) in the dialog's action bar | a fixed footer: `FilledButton.icon` full width, `minimumSize: Size.fromHeight(rowMinHeight)`, the purpose glyph at `buttonGlyphSize`, `moveToDestination(name)` / `pickShareConfirm` / `pickCopyConfirm` in two lines at most, id `folder-picker-confirm`; padding `groupInset, bodyTop, groupInset, bodyTop + clearance` — the footer carries the clearance and rides the keyboard |
| Share refusal | `FormCaptionSlot` above the actions | the same slot, above the footer button (`pickerReasonPadding`, `pickerReasonLines`) |
| Ids | — | every existing id kept; new `folder-picker-recent-<index>` |

Measured: browse list 481.5 dp at 1.0 and 429.5 at de 2.0 on 360 × 780; with the keyboard up (320 dp) the list keeps 185.5 dp (3 result rows whole) at 1.0 en, 133.5 dp (2) at de 2.0, 165.5 at en / ro 2.0, 309.7 (5) at 412 × 915; **no overflow in any cell** (today: every 360 cell overflows). Footer 88 dp, 120 at de 2.0 (two-line label). Stacking the title at de 2.0 would cost 59 dp and leave one result row under the keyboard (`proposed/measurements_picker_stacked.txt`) — hence D-B.

### 2.7 The dialogs (`AppDialogs`)

Only what the browser's dialogs need, pending master decision 2 (D-L): the destructive confirm becomes the language's pair — `TextButton` cancel + `FilledButton.tonal` confirm, no error fill, no 48 dp icon unless a caller passes one — inside `AppDialogs.confirm(isDestructive: true)`, so every delete in the app reads the same (about 77 calls). The confirm id stays `sheet-confirm`. Rename (folder and note, from the row sheet and the folder's ⋮) opens with `selectAll: true`; New folder and both renames pass `allowEmpty: false` (D-M). Loading stays as it is.

## 3. What stays and why

- **Every action, its order and its effect**; Select first, the partner's rows disabled in place with the reason at full strength, Copy to my notes only on the partner's note. These are settled by the colour-labels and share records.
- **The colour strip's 41 dp cells**: eight cells cannot be 48 wide on 360 without scrolling; putting the strip in a group would cut them to 37 dp, so it stands on the ground.
- **What a sort writes** (`FoldersSortOrder` / `NotesSortOrder` names on the folder row; the root's in memory), the menu row's value text, and that a pick closes the sheet.
- **The picker's logic**: where it opens (inside the source's folder), the tombstone rules, the partner exclusion, the share refusals, recents (none for a share), a search result committing at once, the start-at-current-folder behaviour; `showFolderPickerDialog`'s return contract (`null` / `''` / id).
- **Move history's** service, stream, ticker and per-entry undo through `MoveCoordinator.undoEntry`.
- **`AppDialogs`** as the one dialog layer, its scroll and clamps; the loading dialog.
- **The page's ⋮ menu** (tier A's business).

## 4. Risks

- **Height budgets.** The sort sheet reaches the 0.92 clamp on 360 × 780 at 1.0 and needs a short scroll for the last note row; at 412 it fits. The long-press sheet's tallest case (a shared folder at de 2.0) is 640 dp of 717.6. The picker under the keyboard at de 2.0 keeps two rows; the header is held to one row for that reason (D-B).
- **Text scale on device.** The renders are linear; Android's 200 % curve draws 15 sp at about 26–27 sp, so device heights at 2.0 come out a little *smaller* than measured — the budgets hold.
- **German.** "Verschieben nach…" ellipsizes in the picker's header at 2.0 (D-B); "Verlauf löschen" ellipsizes in the history header at 2.0 (its node keeps the word). Nothing breaks mid-word in the proposal; today history does.
- **Dark.** All roles; `error` on `rowGroup` 6.21:1 light, 9.54:1 dark; `primary` 6.12 / 9.56; disabled rows are exempt and their captions stay full.
- **Semantics.** The sort rows gain `checked`; the share row a checkbox; every history Undo is named "Undo" (it follows its row's node in traversal; a per-row label would need a string — not proposed). The move picker's ✕ now carries `folder-picker-cancel`; any flow that tapped the old Cancel text keeps working by id. The sort chooser's ids from Slice 0 retire in Slice 2 — say so in the flows' comments.
- **Keyboard.** The picker's footer rides the keyboard; its field never autofocuses (`FormSearchRow`), so the sheet opens with the keyboard down, as the dialog did.
- **Reach of the change.** The label picker is also the editor's; the long-press sheet is also the sync guide's try-it folder; the move picker is also the Sharing page's and Copy to my notes'. Their suites (`label_picker_sheet_test`, the guide's, `share_folders_sheets`, `shared_note_copy`) move with the slices that touch them.
- **Test churn.** The page suite's "a long press on a row" group reads `ListTile` titles; `folder_picker_dialog_test` finds `AlertDialog` text; `browser_partner_rows_test` and `content_rows_test` read the sheet — all rewritten in the slice that changes their sheet.
- **A process left behind.** A `flutter_tester` (pid 14612, started 15:43) from a stopped scratch run in this worktree could not be stopped from the designer's session; stop it before running the suite there.

## 5. Decisions

Each is the designer's default, taken while the owner was away, reversible, recommended option first.

| | Default | Not taken | Changes behaviour? |
| --- | --- | --- | --- |
| D-A | **The move-to picker becomes a filler sheet** (0.92 box, pinned search, one confirm in a fixed footer naming the destination). It overflows under the keyboard in every 360 cell today; as a sheet it keeps 2–5 rows above the keyboard with no overflow. Applies to all three purposes. | Keep the `AlertDialog` and restyle its rows: the fixed body still has to be cut to fit the keyboard, and the confirm stays top-to-bottom far from the thumb. | No — the same picks and results; Cancel moves to the ✕ (same id). |
| D-B | **The picker's header stays one row; the title ellipsizes at de 2.0** — the footer button says the destination in full. | Stack the title at large text: 59 dp more, one result row left above the keyboard at de 2.0. | No |
| D-C | **The location becomes a band: a 48 dp Up and 48 dp path segments; the outlined box and the "Currently in" overline retire** (the `currentlyIn` key stays in the ARBs until tier G deletes unused keys). | Keep the boxed address bar with its overline. | No (a visible line goes) |
| D-D | **One "Sort by" sheet with two labelled groups; the chooser step retires** — one tap fewer, both current orders visible at once. | A two-row chooser sub-sheet (`Folders … Name ›`, `Notes … Last updated ›`) in front of two sort sheets. | **Yes** — the chooser step goes. |
| D-E | **A pick writes the order and closes the sheet**, as today. | Stay open and apply live, to set both kinds in one visit. | No |
| D-F | **On manual order no row is ticked**, as today (the ⋮ row still says "Custom order"). | A checked, inert "Custom order" row in the group, or the label's trailing count slot saying it. | No |
| D-G | **Delete stands in a group of its own** under the actions. | Delete as the last row of the one group. | No — the order is kept. |
| D-H | **The long-press title stacks under the ✕ on two lines when the name does not fit** (`stackTitleAtLargeText`). | One line with an ellipsis, as today. | No |
| D-I | **The colour strip is a band on the ground**, cells 41 dp. | `FormSwatchRow` inside a group: cells 37 dp at 360. | No |
| D-J | **The partner share row is a `FormCheckRow` with a checkbox** — its state is spoken. | A picker row whose label alone says "Shared with" (the tick dropped). | No |
| D-K | **Move history: undone entries dim to 38 % with "Undone" at full strength, no strikethrough; Clear is disabled in place when there is nothing to clear.** | Keep the strikethrough; hide Clear when empty; or Clear as a destructive row at the list's end. | No (Clear visible but off when empty) |
| D-L | **Master decision 2: the language's confirm** — `TextButton` cancel + `FilledButton.tonal` confirm in `AppDialogs.confirm(isDestructive: true)`, app-wide, the browser's deletes and Clear history included. | B: keep the error-filled confirm everywhere. C: tonal in the browser only — a third style, which the language refuses. | No (a look, app-wide) |
| D-M | **Rename opens with the name selected whole; New folder and Rename keep Save off while the name is empty.** | As today: caret at the end; an empty name accepted and dropped silently. | **Yes**, small. |
| D-N | **Search results stay a bare name**, as today. | A caption with the parent path, so two "Week 1"s can be told apart — needs `FolderNameIndex` to return paths; deferred. | No |

## 6. Renders and measurements for the review

Paths are under `browser_sheets/`: `now/` (today), `proposed/` (the proposal as built in the scratch test), `montage/` (five-cell strips), each with a `measurements.txt`; `browser-sheets-mock.html` is the mock.

The `design-reviewer` re-renders, after each slice, on light / dark × 1.0 / 1.3 / 2.0 × en / de (ro for the picker and the long-press sheet) × 360 × 780 (412 × 915 for the sort sheet and the picker):

- the long-press sheet for a folder, a note, a long German name, the partner's folder (all disabled, the partner line), a paired folder shared through its parent (the share row disabled with its caption); assert no scroll at de 2.0 (sheet ≤ 717.6 dp), rows 48 / 52 dp, strip cells 41.0 ±0.5 dp at 360;
- the label picker (174 ±1 dp, every scale);
- the sort sheet at the root and in a folder, each order chosen once, and manual order; the chosen row's node `checked` and `inMutuallyExclusiveGroup`; root 370 / 470 ±1 dp;
- move history: three entries with one undone, empty, after Clear (the refresh: the ✕'s semantics rect within 1 px of its paint after three frames), 300 entries (≤ 12 rows built); every caption ≥ 4.5:1 from the tokens;
- the picker at the root, deep (Root › Training › Winter block › Week 1), a long current name (footer two lines), search with results, nothing found, the keyboard up at 320 dp with "w" typed; no overflow; list ≥ 185 dp at 1.0 and ≥ 133 dp at de 2.0 with the keyboard up; Up and every segment 48 dp tall; the share and copy purposes once each;
- the four browser dialogs (delete folder with notes, rename, new folder, clear history) at de 2.0, after D-L / D-M are answered.

## 7. Slices

In build order; one implementer and one reviewer per slice; the gate after each is `dart analyze lib`, the whole suite, `test/qa/flows_lint_test.dart`, and the browser suite on the fleet guest.

**Slice 0 — the safety net, on today's UI.** The fixture is `tool/qa/fixtures/basic.json` as it is (Training › Week 1, Session 1–2, Money › January): no new fixture. New `SemanticsIds` (kebab-case, never renamed): `folder-menu-sort`, `folder-menu-move-history` (the ⋮ items), `browser-sort-open-folders`, `browser-sort-open-notes` (today's chooser; they retire in Slice 2), the twelve `browser-sort-folder-* / browser-sort-note-*` of §2.4 on today's tiles, `move-history-sheet`, `move-history-clear`, `move-history-undo-<index>`, `row-action-labels` (the strip's band), `label-swatch-<label>` (eight, `none` first), `selection-label` (the selection bar's Label). New flows in `tool/qa/flows/browser/`, each from a fresh seed: `03_long_press.txt` (a folder's and a note's sheet: every `row-action-*` id present, the strip band, back closes), `04_sort.txt` (Training's notes by Title A-Z then Z-A, `expect --ordered` both ways; the folders' order at the root), `05_move_history.txt` (Session 1 moved to Week 1 through `row-action-move` → `folder-picker-confirm`, the history sheet lists it, `move-history-undo-0` restores it, `move-history-clear` → `sheet-confirm` empties it), `06_picker.txt` (search, nothing found, Up, a recent chip, cancel by `folder-picker-cancel`), `07_label.txt` (selection → `selection-label` → `label-swatch-red` → the row carries it); `_labels.txt` gains `Week 1`, `Session 1`, `Session 2`. A first widget suite for move history (`test/widgets/move_history_sheet_test.dart`: entries, undo, clear through the confirm, empty, the ids). Files: `semantics_ids.dart`, `folder_overflow_menu.dart`, `optimized_folder_content_page.dart`, `move_history_sheet.dart`, `content_rows.dart`, `label_swatch_strip.dart`, `selection_action_bar.dart`, the flows, the new suite. Gate: the browser suite green on the old UI, twice.

**Slice 1 — the long-press sheet and the label picker.** `content_rows.dart` (`showRowActionSheet` on the sub-sheet chrome, `_OneNodeWhenOff` retired, `row-action-close`), `label_swatch_strip.dart` (`padding:`; `showLabelPickerSheet` on the chrome, `label-picker-close`), callers unchanged (`folder_row.dart`, `note_row.dart`, `guide_sync_try_folder.dart`, `note_actions.dart`). Tests: `content_rows_test`, `label_picker_sheet_test`, `browser_partner_rows_test`, the page suite's long-press group, the clearance test gains both sheets, de 2.0 at 360 × 780 with no overflow. Gate also: flows 02, 03, 07.

**Slice 2 — the sort sheet.** New `lib/widgets/browser_sort_sheet.dart`; the page's three methods reduce to one call and the two writes; `browser-sort-close`; the chooser ids leave the flows. Tests: a `browser_sort_sheet_test` (the pick returned, `null` on ✕ / barrier / back, the checked node, root vs folder groups, de 2.0), the page suite's sort cases, the clearance test. Gate also: flow 04.

**Slice 3 — move history.** `move_history_sheet.dart` rewritten (§2.5) inside `FormSheetSemanticsRefresh`; `move-history-close`. Tests: the Slice 0 suite rewritten for the new chrome plus laziness (300 entries) and the refresh after Clear; the clearance test. Gate also: flow 05.

**Slice 4 — the move-to picker.** `folder_picker_dialog.dart` → `folder_picker_sheet.dart` (`showFolderPickerSheet`, the same arguments and return), `FormPickerRow.labelTrailing` (+ `form_rows_test`), `FormMetrics.pickerCrumbPadding`; call sites `move_coordinator.dart` ×3, `shared_note_copy.dart`, `share_folders_sheets.dart`. Tests: `folder_picker_dialog_test` → `folder_picker_sheet_test` (every case kept, plus the keyboard at de 2.0 with no overflow and ≥ 2 rows, the 48 dp targets), the clearance test with its keyboard case. Gate also: flow 06 and the share suite's `04_n`, `04_o` on the pair.

**Slice 5 — the dialogs, only once D-L and D-M are answered.** `app_dialogs.dart` (`confirm`), `app_dialogs_test`; the rename and new-folder calls in `folder_row.dart`, `note_row.dart`, `optimized_folder_content_page.dart`. Gate also: every flow that answers a delete (`sync_pair/02`, `share/04_o`).

**The closing device pass:** the browser suite, then `qa set theme=dark locale=de text-scale=2.0` and the same flows with their screenshots beside the renders of §6; `qa errors` clean; the master's §7 gains this tier's row.

## 8. How to run this

Nothing starts before the owner has answered §5. "Yes to all" is an answer; D-A to D-C are Slice 4's, D-D to D-F Slice 2's, D-G to D-J Slice 1's, D-K Slice 3's, and D-L and D-M are Slice 5's and the master record's decision 2 — an app-wide change of look that he may want to take apart from the rest.

- **Slice 0 needs no decision** and may be built first: it adds ids, device flows and a first move-history suite on today's UI, so every later slice is caught by a flow that was green before it.
- **The session:** a Fable 5.2 lead at `high`; with §5 answered nothing is left to decide, so an Opus 5.5 session may build it directly instead.
- **Per slice, in sequence** (one `flutter test` at a time): one `implementer` in a worktree of its own, briefed with §2's shared part, its own surface's table, §3 and its lines of §7; one `reviewer` on the diff against §3; one `design-reviewer` in a fresh context on §6, never shown §1's reasoning; the whole-suite gate from the lead; then `qa pass browser -d emulator-5556` with Slice 0's flows.
- **At each slice boundary** the status line is corrected, the uncommitted files are counted and a ready commit is offered; the master record's §7 gains the tier's row.
