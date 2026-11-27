# Markdown settings on the settings kit — design record (2026-11-27)

**Status: PROPOSED — nothing is built.** A designer's judgement and specification of the Markdown settings page, made from renders of the page as it is (real fonts, light and dark, en / de / ro, text scale 1.0 / 1.3 / 2.0, 360 and 412 wide) on 2026-11-27 while the owner was away. It waits for his answer on the lettered decisions of §5 — each was taken by default and each names the option not taken. The renders, the measurements and the mock are in `build/session-2026-11-27/md_settings/` (git-ignored; copied there from the session's scratchpad).

The page is `lib/pages/markdown_settings_page.dart` (2,663 lines), the last large settings surface that is not on the settings kit. `docs/settings-rework-roadmap.md` §9 deferred it ("Markdown settings and its sub-pages on the language (S20) … a rework of its own with its own record"); this is that record. Every render a section cites is a file under `renders/` in the folder above; the measurements are in `renders/measurements.txt` (the page as it is), `renders/proto_measurements.txt` (the proposed values built once into a scratch prototype) and `renders/words.txt` (the widest words of every built-in label and caption). The mock is `markdown_settings_mock.html` in the same folder: 360 wide, light and dark, built from the app's tokens.

One render of the current page is missing: the drag at de 2.0, whose scratch test failed because only two cards fit the frame. The drag is rendered at de 1.0 dark instead (`renders/state_de_1.0_dark_360_f_drag.png`).

**Contents:** §1 What is wrong today · §2 The direction · §3 What stays, and the must-not-change list · §4 Risks · §5 Decisions for the owner · §6 What the design-reviewer re-renders and asserts after a build · §7 Later slices · §8 Slice plan.

## 1. What is wrong today

Worst first. "Evidence" names the render under `renders/` or the measurement file that shows it.

| # | Weakness | Rule it breaks | Evidence |
|---|---|---|---|
| 1 | **The shortcut text column is 88 dp at every scale.** The `ListTile`'s leading (handle 48 + glyph 24) and trailing (2 × 48) leave 88 of the 328 dp card. Words break mid-word even in English at 1.0: "Strikethrou\|gh". In German at 1.0: "Kontrollkäs\|tchen", "Aufzählung\|sliste", "Nummerier\|te Liste", "Durchgestri\|chen", "Über\|schriftenmenü". At de 2.0: "Num\|merie\|rte\|Liste", "STAND\|ARD", "Na\|chher", and cards up to 426 dp tall. | Text survives 1.3 and German; WCAG 1.4.4 | `page_en_1.0_light_360_f05.png`, `page_de_2.0_light_360_f09.png`, `measurements.txt` (the `card` lines) |
| 2 | The utility cards have a 136 dp text column. At de 2.0: "Rückgän\|gig", "Verknüpf\|ungen\|neu\|anordne\|n" (a 298 dp card). | Same | `page_de_2.0_light_360_f04.png` |
| 3 | Section headers are 17 / 600 with a 26 dp `primary` glyph, a different scale from every kit page. At de 2.0: "Autovervollständ\|igung", "Hilfsschaltfläche\|n". The shortcuts header breaks into five lines ("Mark\|down\|-Verk\|nüpfu\|ngen") beside an always-on count pill. Sections are separated by `outline` at 0.2 `Divider`s (1.25:1); there are no groups. | The kit's header (11 / 500 uppercase, `onSurfaceVariant`, a 48 dp box); hierarchy by type, not size | `page_de_2.0_light_360_f00.png`, `state_de_2.0_light_360_c_chip.png` |
| 4 | **The fold chevron is inverted against the kit**: `expand_more` when open, `^` when folded. **Fold-all skips Autocomplete**: `'vocabulary'` is missing from the set `_setAllSectionsExpanded` writes. | Kit consistency; a bug | `folded_de_2.0_light_360.png` (Autocomplete stays open after fold-all) |
| 5 | The app bar title "Markdown-Verknüpfungen" needs 201.9 dp. Its slot with the back arrow and two actions is 176 dp, so it ellipsizes at **de 1.0** already, not only at 2.0. The hub row names this page "Editor and markdown". | The bar's title names the route | `proto_measurements.txt` (the `old title … needs` lines) |
| 6 | Five switches use `Transform.scale(0.8)`: the hit box is 48 × 38.4 dp. The category `FilterChip`s use compact density with shrink-wrapped targets: 30 dp tall at 1.0 (38 at 2.0). The ratio slider's overlay radius is 16. | 48 dp targets | `measurements.txt` (the `switch rect` and `chip` lines) |
| 7 | Contrast in light: shortcut subtitles (`onSurface` at 0.6 on the card) are 4.35:1. Descriptions (`onSurface` at 0.6 on `pageGround`) are 4.29:1. The DEFAULT pill is 4.40:1 and set at 10 sp bold, under the 11 sp floor. A hidden row's title is 3.22:1 and its subtitle 1.90:1. The empty state (`onSurface` at 0.5) is 3.19:1. The `unfold_more` glyph is 3.19:1, the lock glyph 1.90:1, the money rows' 0.45 dimming 2.78:1. For reference, `onSurfaceVariant` is 8.47:1 on the card and 8.13:1 on `pageGround`. In dark the same alphas read 5.54, 5.76, 6.29, 4.26, 2.37 and 4.36:1. | WCAG 1.4.3; captions are `onSurfaceVariant`; disabled is 38 % | `measurements.txt` (the `contrast` lines) |
| 8 | The pinned header is painted `surface` (#FEF7FF), a light band over `pageGround` (#F3EDF7); in dark `surface` happens to equal `pageGround`. An invisible "Clear" slot is always reserved: 78 dp in de 1.0, 152 dp in de 2.0, so "Ohne Kategor…" is cut and only two chips show. With no categories at all, a lone "Uncategorized" chip shows — a filter that selects everything. | The kit's ground; disabled, never reserved-and-invisible | `page_en_1.0_light_360_f04.png`, `page_de_2.0_light_360_f09.png` |
| 9 | The FAB has no tooltip, so it has no accessible name. It floats over unrelated controls (the money value, the utility eyes, the rows' ⋮). With the keyboard up it sits on the chip row. | Every icon-only button is named; keyboard | `page_en_1.0_light_360_f00.png`, `state_de_2.0_light_360_d_search_kb.png` |
| 10 | The utility list is a **shrink-wrapped `ReorderableListView` inside the page scroll**, so its drag cannot auto-scroll the page. It holds 14 rows × 80 = 1,120 dp, more than the 732 dp viewport at 1.0. Its handle is not wired to an index. Neither list has a drag-free reorder for a screen reader. | Never a shrink-wrapped reorderable list; WCAG 2.5.7 | Read from the code, by the mechanism the page's own comment documents for the shortcut list. Plausible, not yet seen on a device. |
| 11 | Menus are `PopupMenuButton`s with `Colors.red` on the destructive items. The profile picker is a hand-built `showMenu`. The ratio slider appears and disappears with the split switch, so everything below it moves. Money's dependent rows use `Opacity(0.45)` + `IgnorePointer` instead of 38 %. Cards are elevated. | `FormMenuChoiceItem` menus; disabled is 38 %, in place; no `Card` | `page_en_1.0_light_360_f00.png`, `page_en_1.0_light_360_f01.png` |

The heading-level chips the 2026-11-01 review recorded are not on this page; they belong to the sub-pages (§7).

The measured page as it is, at 360 × 780 unless marked (scroll extent, `measurements.txt`): en 1.0 5,351 dp; de 1.0 6,193; de 1.3 8,203; de 2.0 16,782 (light and dark); de 2.0 at 412 wide 11,244. The pinned header's extent is 110 dp at 1.0 and 130 at de 2.0; its search field is 48 dp at 1.0 and 68 at 2.0.

## 2. The direction

### 2.1 The idiom, and why it reads as one page

The whole page speaks the settings kit. Its two reorderable lists — the utility buttons and the shortcuts — are kit groups drawn one row at a time, as sliver sections in the page's own `CustomScrollView`.

Both kinds of section share the same ground (`pageGround`), the same group (`rowGroup` at `RowMetrics.groupRadius`), the same hairline (`rowDivider`) and the same section header. The boundary between them is semantic: the **MARKDOWN SHORTCUTS** header. Above it every row is a setting; below it every row is one of the user's things, with a handle and a ⋮. That is the boundary the calendar settings page and the categories page draw, here on one page.

### 2.2 The order

1. Toolbar layout
2. Text colors
3. Money ledger
4. Autocomplete
5. Utility buttons
6. Bar profiles — moved here from the top; it scopes only the shortcuts (decision B)
7. Markdown shortcuts

### 2.3 The structure

- `SliverPadding(top: RowMetrics.groupInset)`.
- `SliverToBoxAdapter(SettingsSectionList(shrinkWrap: true, padding: EdgeInsets.symmetric(horizontal: RowMetrics.groupInset), query: SettingsQuery.empty, collapsedSections, onToggleSection))` for sections 1–4.
- The utility sliver section (§2.5).
- A second shrink-wrapped kit box, the same way, for Bar profiles.
- The shortcuts sliver section (§2.5).
- `SliverPadding(bottom: AppSpacing.fabClearance)`.

The body is not built until the stored fold set has loaded, as the other kit pages do. That replaces `_foldAnimationsEnabled`: the first frame is already folded, so nothing animates on entry. The `markdownSettingsList` identifier stays on the `CustomScrollView`.

### 2.4 The two kit pieces

- **Hoisted, not new: `SettingsSectionHeader`**, made public in `lib/widgets/settings_section_list.dart` from `SettingsSectionCard._buildHeader`. It takes `title`, `collapsed`, `onToggle`, `count` and `identifier`. `SettingsSectionCard` builds through it, so the kit's goldens must not change.
- **The one new primitive: `FormReorderRow`** in `lib/widgets/form_rows/reorder_row.dart`, exported by `form_rows.dart`, with a static `FormReorderRow.wordsFit(context, labels:, captions:, trailingCount:)`. Its anatomy is §2.6, its stacking rule §2.7.

### 2.5 The elements

| Element | Current | Proposed (token · value · constant) |
|---|---|---|
| App bar | Title `markdownShortcuts`; a fold icon and a ⋮ | `SettingsAppBar(title: l10n.settingsRowEditor)`. Actions: the ⋮ only, id `markdownBarMenu`. Its menu is `showFormMenu` with `FormMenuItemRow`s: Collapse all / Expand all (`unfold_less_rounded` / `unfold_more_rounded`, new id `markdown-fold-all`), `resetToDefault` (`refresh_rounded`), `removeAllCustom` (`delete_sweep_outlined`, `color: colorScheme.error`). The measured title slot at 360 is 224 dp, against de 216.5 / en 216.0 / ro 195.7 at the bar's 1.34 clamp: it fits at every scale (decision C). |
| Section headers (all seven) | 17 / 600 + a 26 dp glyph + a `Divider` | The kit's header: a 48 dp box, the label at `RowMetrics.sectionLabel*` (11 / 500, uppercase, letter spacing 0.88) in `onSurfaceVariant`, `headingLevel: 2`; the chevron `expand_more_rounded` 22 dp, turning 0.5 when open, over `FormMetrics.settingsFoldDuration`. No glyph, no `Divider`. Fold ids `toolbar`, `colors`, `money`, `vocabulary`, `utility`, `profiles`, `shortcuts` — unchanged. |
| Toolbar: the preview | A box with an `outline` at 0.3 border, radius 8 | The section's `intro:`. `Padding(horizontal: RowMetrics.groupInset)`, a 1 dp `outlineVariant` border at `FormMetrics.menuRadius` (12), `ClipRRect`. `MarkdownBar`'s arguments unchanged. |
| Toolbar: Split toolbar, Pin undo and redo | A `Row` + a `Transform.scale(0.8)` `Switch` | `SwitchListTile` entries: the kit's 48 dp row; the whole row toggles. |
| Toolbar: the ratio | A caption in `onSurface` at 0.6 + a custom `SliderTheme` (track 4, thumb 8, overlay 16); hidden while split is off | A kit entry: `MergeSemantics(Padding(FormMetrics.settingsControlRowPadding, Column[the readout "Shortcuts 70% · Utilities 30%" in the kit's title style with tabular figures, Slider(theme default)]))`. Always present; disabled (the title at 38 %, `onChanged: null`) while split is off (decision J). `semanticFormatterCallback` reads the readout. Stays continuous and writes on change end, as today. |
| Text colors | A section + an `OutlinedButton` | One kit row: `ListTile(title: editColors, trailing: Icon(chevron_right_rounded))`, new id `markdown-colors-row`. |
| Money ledger | Hand-built rows, `Opacity(0.45)` | The master switch: `SwitchListTile` with title and description. Start balance and Currency symbol: `SettingsYieldingTile(enabled: moneyEnabled)`, the 0.6 alpha removed. Symbol after amount: `SwitchListTile(onChanged: enabled ? … : null)`. Per-note currency: `ListTile(enabled: moneyEnabled, trailing: chevron)`. Ids `markdownMoneyStart`, `markdownMoneySymbol`, `markdownPerNoteCurrency` kept. |
| Autocomplete | Hand-built rows | `SwitchListTile` (label and description). The trigger: a `settingsChoiceRow` entry with `identifier: markdownVocabularyTrigger`; its title and description dim through the entry's styles (`FormMetrics.disabledOpacity`), and its `padding` override is dropped. Edit lists: `ListTile(enabled: vocabularyEnabled, trailing: chevron)`, new id `markdown-vocabularies-row`. |
| Utility section | A hint caption + a search + shrink-wrapped `Card`s | `SettingsSectionHeader`; then, when it shows, the search: `SettingsSearchField` in `FormMetrics.settingsSearchPadding`, with `ReorderLockedHint` while filtering; then `SliverPadding(horizontal: RowMetrics.groupInset)` › `DecoratedSliver(rowGroup, RowMetrics.groupRadius)` › `SliverMainAxisGroup[intro, SliverReorderableList of FormReorderRow]`. The intro is `utilityButtonsHint` in `settingsCaptionStyle` / `onSurfaceVariant`, padded `FormMetrics.settingsRowPadding` with `FormMetrics.settingsRowVerticalPadding` (11) top and bottom, no hairline under it. A plain `SliverList` while filtering. Ids `markdownUtility(id)` kept. |
| Utility row | `Card` + `ListTile`; the glyph `primary`; the lock `onSurface` at 0.3 | `FormReorderRow`: the glyph in `onSurfaceVariant`; the caption Visible / Hidden / Always visible; one trailing — the eye `FormTrailingButton` (`visibility_outlined` / `visibility_off_outlined`, tooltip `hide` / `show`), or on the locked row `lock_outline` in a 48 dp slot (decorative). The handle is wired to its index. |
| Bar profiles | A header + a hand-built row (a compact `IconButton`, 20 dp icons, a "Default" pill) | One kit row, `contentPadding` start `RowMetrics.groupInset`, end 0. Leading: a fixed `view_day_outlined`. Title: `[the name 15 / 400, one line, ellipsis][gap 7][unfold_more_rounded at RowMetrics.chevronSize (18) in onSurfaceVariant]`. A tap opens `showFormMenu` of `FormMenuChoiceItem`s, the bar being edited checked. Trailing: `FormTrailingButton(add_rounded, tooltip addBar)` and `FormTrailingButton(more_vert_rounded, id markdownProfileMenu)`; its menu items are `FormMenuItemRow`s, delete in `error`, the assign item keeping `markdownPerNoteBars`. The pill is dropped from the row and the picker (decision P). |
| Shortcuts header | A glyph + 17 / 600 + an always-on count pill | `SettingsSectionHeader(title: l10n.markdownShortcuts, id: 'shortcuts')`. The title string stays: the guide quotes it as "the list's own header". The count slot shows `shortcutCountFiltered` while filtering, the kit's `settingsSectionCollapsedCount` when folded, and nothing otherwise (decision O). |
| Pinned header | `surface`; the search; compact `FilterChip`s 30 dp; an invisible text "Clear" slot | `Material(color: pageGround)`. The search: `SettingsSearchField` in a new `FormMetrics.settingsPinnedSearchPadding = EdgeInsets.fromLTRB(RowMetrics.groupInset, 8, RowMetrics.groupInset, 8)`, replacing the page-private `_shortcutSearchPadding`. The chip row: `SizedBox(height: FormMetrics.chipTapTarget)` › `Row[Expanded(horizontal SingleChildScrollView, start padding RowMetrics.groupInset, FormChip × n each followed by FormMetrics.chipSpacing), FormTrailingButton(filter_alt_off_outlined, tooltip clearFilters, onPressed: filtering ? clear : null, new id markdown-shortcut-clear-filters), SizedBox(width: RowMetrics.groupInset)]`. Its glyph sits at x 320, the column of the search field's ✕ and the rows' ⋮ (decision I). The chip row shows only while at least one category exists (decision H). Extent = `SettingsSearchField.heightFor(context) + settingsPinnedSearchPadding.vertical + (chips ? FormMetrics.chipTapTarget : 0)`. |
| Shortcut list | `Card`s in a `SliverPadding` | `SliverPadding(horizontal: RowMetrics.groupInset)` › `DecoratedSliver(rowGroup, RowMetrics.groupRadius)` › `SliverReorderableList` with `onReorderStart` dropping focus. A plain `SliverList` while filtering. The drag proxy: `reorderDragProxy` over `ClipRRect(RowMetrics.groupRadius)` + `ColoredBox(rowGroup)`, with `borderRadius: RowMetrics.groupRadius`. Ids `markdownShortcutRow(id)`, `markdownShortcutVisibility(id)`, `markdownShortcutMenu(id)` kept. |
| Shortcut row | An 88 dp text column; the DEFAULT and category pills; `Opacity(0.5)` when hidden | `FormReorderRow`: label `localizedLabel`; caption `MarkdownSettingsUtils.getShortcutSubtitle` + (a category ? `" · " + category`) (decision F); trailing the eye `FormTrailingButton` and the ⋮ `FormTrailingButton`. The ⋮ opens `showFormMenu`: `setCategory` (`label_outline_rounded`), then for custom rows only `edit` (`edit_outlined`) and `delete` (`delete_outline_rounded`, `error`). |
| Empty states | `onSurface` at 0.5, sizes 64 / 18 / 14 | The glyph at `RowMetrics.emptyStateGlyphSize` (48) in `onSurfaceVariant`, the gap `RowMetrics.gap`, the title at `RowMetrics.titleFontSize` (15) in `onSurfaceVariant`, `tapToAddShortcut` in `settingsCaptionStyle`, vertical padding `RowMetrics.emptyStatePadding` (48). The no-match state keeps its `TextButton(clearFilters)`. |
| FAB | No tooltip, no id, always shown | `FloatingActionButton(heroTag: null, tooltip: l10n.newShortcut, child: Icon(add_rounded))`, new id `markdown-shortcut-add`. Hidden while `MediaQuery.viewInsetsOf(context).bottom > 0` — the categories page's rule (decision K). |

### 2.6 `FormReorderRow` — the anatomy

Every constant below already exists.

*Side by side:*

- Floor `RowMetrics.twoLineMinHeight` (62).
- `[RowMetrics.reorderHandleLead 4][ReorderHandle 48 (FormMetrics.dragHandleSlot)][glyph box RowMetrics.glyphSize 22][RowMetrics.gap 14][texts][trailing FormTrailingButton × n]`.
- The texts: vertical padding `RowMetrics.twoLinePadding.vertical / 2`. The label 15 / 400 (`RowMetrics.titleFontSize`) at height 20 / 15 (`FormMetrics.labelLineHeight`) in `onSurface`, or `onSurfaceVariant` when off. `RowMetrics.lineGap` 2. The caption 13 / 400 (`RowMetrics.secondLineFontSize`) at height 18 / 13 (`FormMetrics.captionLineHeight`) in `onSurfaceVariant`. Both wrap by word, with no `maxLines`.
- A hairline *above* every row but the first: `rowDivider`, 1 dp (`RowMetrics.dividerThickness`), indent `RowMetrics.reorderGlyphTextInset` (88).

*Stacked:*

- Line 1: `[RowMetrics.groupInset 16][glyph 22][RowMetrics.gap 14][texts][FormMetrics.rowEndPadding 12]`.
- Line 2, the control line: `[RowMetrics.reorderHandleLead 4][handle 48] … [trailing]`.
- The hairline indent is `RowMetrics.dividerIndentWithGlyph` (52).

*Off (a hidden shortcut or utility):* the glyph at `FormMetrics.disabledOpacity`, the label in `onSurfaceVariant`, the caption unchanged. That reads 8.5–9 : 1 in both themes. The eye shows the state.

*Interaction:* no row tap (unchanged). A long press anywhere lifts the row (`ReorderableDelayedDragStartListener`, the caller's). A tap on the handle is swallowed with `GestureDetector(onTap: () {})`, as on the categories page.

*Semantics:*

- One container node carries `identifier`.
- Inside it, a text node: the label "name\ncaption", plus `categoryReorderLabel(name)` while drag is on, and `customSemanticsActions` for `categoryMoveUp` / `categoryMoveDown` (decision M). Each action is absent at its own end of the list and while filtering.
- The handle is excluded from semantics; the trailing buttons are sibling nodes.

### 2.7 The stacking rule (decision E)

A list's rows stack when any word of any built-in label or caption does not fit the side-by-side column, measured in the row's resolved text styles (the ambient style merged with the label's or the caption's — the letter spacing counts):

- Side-by-side column = row width − 88 − 48 × the number of trailing buttons.
- The shortcut list measures `DefaultMarkdownShortcuts` (localized) and their captions.
- The utility list measures the definitions' labels and Visible / Hidden / Always visible.

This decides by locale, text scale and width, never by the user's data — `FormStepperRow`'s `widestLabel` idea. A user's own long word can still break; that is data, accepted.

The widest built-in words (`words.txt`, Roboto, linear scale, before letter spacing):

| Locale | Label word | 1.0 | 1.3 | 1.6 | 2.0 | Caption word at 2.0 |
|---|---|---|---|---|---|---|
| en | "Strikethrough" | 89.5 | 116.4 | 143.2 | 179.0 | `"==yellow:"` 124.4 |
| de | "Kontrollkästchen" | 112.4 | 146.2 | 179.9 | 224.9 | "Überschriftenmenü" 221.3 (110.7 at 1.0, 143.9 at 1.3) |
| ro | "Numerotată" | 79.7 | 103.6 | 127.5 | 159.3 | `"==yellow:"` 124.4 |

With the row's letter spacing, "Kontrollkästchen" needs about 151 dp at de 1.3 and about 233 dp at de 2.0, and "Überschriftenmenü" about 230 at 2.0. A fixed scale threshold of 1.6 was tried in the prototype and broke "Kontrollkästchen" from de 1.3 to 1.6; moving only the trailing buttons under the text (column 228) still broke it at de 2.0 by 5 dp. Moving the handle onto the control line too gives the 264 dp column the table below shows.

### 2.8 Per-cell measurements (proposed)

From the prototype, `proto_measurements.txt`. Tolerance ±1 dp throughout.

| Cell | Row mode | Text column | Shortcut row heights | Built-in mid-word breaks | Pinned extent |
|---|---|---|---|---|---|
| en / de / ro 1.0 · 360 | side by side | 144 | 62–115 | 0 | 112 |
| en 1.3 · 360 | side by side ("Strikethrough" ≈120 < 144) | 144 | — | 0 | 118 |
| de 1.3 · 360 | stacked ("Kontrollkästchen" ≈151 > 144) | 264 | 117–141 | 0 | 118 |
| de / ro 2.0 · 360 | stacked | 264 ("Kontrollkästchen" ≈233, "Überschriftenmenü" ≈230) | 144–257 | 0 | 132 |
| de 2.0 · 412 | stacked | 316 | 144–253 | 0 | 132 |

- Today's pinned extent is 110 / — / 130, so the header's budget is held within 2 dp.
- The chip row is 48 dp at every scale; the `FormChip` body is at most 37 dp at 2.0. Chips measured 74.4 × 48 and 148.4 × 48 at 1.0, 87.8 × 48 and 183.2 × 48 at 1.3, 119.2 × 48 and 264.3 × 48 at 2.0.
- The section header is a 48 dp box at every scale; its label is 16 / 21 / 32 dp tall at 1.0 / 1.3 / 2.0 and never breaks mid-word.
- Captions that hold markdown code may still break at punctuation, for example inside `"](url)"`. That is code, not a word, and is accepted.
- The app bar title slot is 224 dp at 360 and 276 dp at 412 once fold-all leaves the bar. Measured titles: "Editor and markdown" 161.2 at 1.0, "Editor und Markdown" 161.5 at 1.0, 210.0 at 1.3 and 216.5 at 2.0 (the bar's 1.34 clamp), "Editor și markdown" 195.7 at 2.0 — none ellipsized.
- In the kit rows the switch targets are the whole 48 dp row (the `Switch` itself is 60 × 40).

### 2.9 Page length

Scroll extent at 780 dp tall. The prototype drew 3 of the 14 utility rows; the "≈" figures add the 11 it did not draw.

| Cell | Now | Proposed |
|---|---|---|
| en 1.0 · 360 | 5,351 | 3,538 (≈ 4,220 with all rows) |
| de 1.3 · 360 | 8,203 | 6,147 (≈ 7,440) |
| de 2.0 · 360 | 16,782 | 8,454 (≈ 10,050, −40 %) |
| ro 2.0 · 360 | — | 8,324 |
| de 2.0 · 412 | 11,244 | 8,230 |

### 2.10 The fold

The page takes the kit's fold for its box sections, and the same stored set drives the two sliver sections through `SettingsSectionHeader`.

- The key `SettingsKeys.markdownSectionsCollapsed` and all seven ids are unchanged, so every stored value keeps working.
- The sliver sections keep the current fade-out controller pattern, at `FormMetrics.settingsFoldDuration` (180 ms) instead of 250 ms; the utility section gets one of its own.
- The ⋮ menu's Collapse all writes all seven ids, including `vocabulary` (decision D).
- While a list's filter is active its section cannot fold — the kit's rule that a fold never swallows a search hit, applied locally.

## 3. What stays, and the must-not-change list

What stays and why:

- Every handler and stored value. The ratio slider stays continuous and writes on change end.
- The shortcut list stays a direct `SliverReorderableList` of the page's viewport. `DecoratedSliver` and `SliverPadding` are slivers, so `Scrollable.of` still resolves to the page and the drag's auto-scroll is intact.
- Drag is off, and the handles grey in place, while a query or a chip is active; `ReorderLockedHint` stays.
- `SettingsSearchField` stays the shortcut search; it is already the kit's.
- The bar preview's arguments, and the dialogs (`AppDialogs.textInput` / `AppDialogs.confirm`; the bespoke `_CategoryDialog` only loses its 0.6 alpha for `onSurfaceVariant`).
- The profile model, the `MarkdownBarBloc` wiring and every `SemanticsIds` value.
- The section title string `markdownShortcuts`.

The must-not-change list the spec was re-read against — a reviewer re-reads it against the diff:

1. Every handler, and every value the page stores, behaves and is written as today. The only behaviour changes are those §5 marks "yes" (C, D, H, I, J, K).
2. The drag auto-scroll structure: the shortcut list is a direct sliver of the page's `CustomScrollView`, never a shrink-wrapped nested list. The utility list becomes one too.
3. Drag is off while a query or a category chip is active (a plain `SliverList`), in both lists.
4. The persisted fold state: the key `SettingsKeys.markdownSectionsCollapsed` and its seven ids `profiles`, `toolbar`, `colors`, `money`, `vocabulary`, `utility`, `shortcuts`, each still naming the same section. A stored value written before the rework restores the same folds.
5. Every `SemanticsIds` value the page carries today: `settingsBarMarkdown`, `markdownSettingsList`, `markdownBarMenu`, `markdownProfileMenu`, `markdownPerNoteBars`, `markdownMoneyStart`, `markdownMoneySymbol`, `markdownPerNoteCurrency`, `markdownVocabularyTrigger`, `markdownUtility(id)`, `markdownShortcutRow(id)`, `markdownShortcutVisibility(id)`, `markdownShortcutMenu(id)`. The saved device flow `tool/qa/flows/settings/05_hub_editor.txt` targets `settings-bar-markdown`, `markdown-settings-list`, `markdown-bar-menu` and `markdown-vocabulary-trigger`; all four are kept, and `markdown-settings-list` stays on the `CustomScrollView`. New ids are additions only.
6. The strings: no new string. The bar title (decision C), the FAB's tooltip (K) and the reorder actions (M) reuse existing keys — `settingsRowEditor`, `newShortcut`, `categoryReorderLabel`, `categoryMoveUp`, `categoryMoveDown`. No caption wording changes (decision G keeps it).
7. No new state-management or navigation pattern.

## 4. Risks

- **Height.** With the keyboard up (460 dp visible at 360 × 780, a 320 dp IME) the rows get 300 dp at en 1.0 (about four rows) and 280 dp at de 2.0 (at least one stacked row, 144–257 dp). The pinned header is 112 / 118 / 132 dp at 1.0 / 1.3 / 2.0, at most 17 % of 780.
- **German at 1.3** stacks, so rows are 117–141 dp instead of 62–100. The page stays shorter than today, but this is the visible cost of decision E.
- **Linear 2.0 is harsher than Android's 200 %.** The stacked column still has 31 dp to spare for "Kontrollkästchen". A user's own long word can still break; that is data, accepted.
- **Dark.** The pinned ground `pageGround` equals `surface` in dark, so dark looks as before; light loses its band. The selected chip's fill against `pageGround` is the stock `FormChip`.
- **Semantics.** The shrink-wrapped kit lists add non-scrolling list nodes inside `markdown-settings-list`. The device flow's `scroll-to id:markdown-vocabulary-trigger` must be re-run.
- **Tests that pin today's structure.** `test/pages/markdown_settings_page_test.dart` finds rows by `Card`. `test/widgets/settings_navigation_contract_test.dart:1707` pins the title as `markdownShortcuts`. `test/widgets/settings_kit_guidelines_test.dart` pumps this page. The guide test (`test/widgets/guide_book_page_test.dart`) is unaffected, because the section title is kept.
- **Glyph coverage.** "↵" draws as tofu in the renders (Roboto lacks it). Judge it on a device; the Android emoji-font trap applies.

## 5. Decisions for the owner

Each was taken by default and each is reversible.

| | Decision | Not taken | Changes behaviour? |
|---|---|---|---|
| A | The page speaks the kit throughout; the two lists are kit groups drawn a row at a time, in sliver sections on one page. | The shortcut list on a page of its own, the categories page's shape. | No |
| B | Bar profiles move from first to directly above Markdown shortcuts, the only thing they scope. | Keep them first. | No |
| C | The bar title becomes `settingsRowEditor` ("Editor and markdown" / "Editor und Markdown" / "Editor și markdown"), the name the hub row and the guide already use. Fold-all moves into the bar's ⋮ menu so the title fits at every scale. | Keep the title and the fold icon; the title ellipsizes from de 1.0. | Yes |
| D | Fold-all also folds Autocomplete (the missing `'vocabulary'` id). | Keep the omission. | Yes |
| E | Rows stack by the measured built-in-word rule (§2.7), and a stacked row moves its handle onto the control line. | A fixed 1.6 threshold, which breaks "Kontrollkästchen" from de 1.3 to 1.6; or dropping the glyph. | No |
| F | The DEFAULT pill goes; the category becomes a caption fact, "· Format". | Keep both pills (they fail 4.5:1 and the 11 sp floor); or add "· Default" through `defaultBar`. | No |
| G | The caption wording stays "Before: … \| After: …"; the layout holds without a change. | A word-free pattern caption such as `**…**` or `[…](url)` — it needs no translation, but it drops `beforeAfterText`. | No |
| H | The chip row hides while no category exists, so the lone "Uncategorized" chip goes. | Keep it. | Yes |
| I | Clear filters becomes a 48 dp icon (`filter_alt_off_outlined`, tooltip `clearFilters`), disabled while no filter is on. | The reserved, invisible text slot. | Yes |
| J | The ratio slider stays on the page and is disabled while split is off. | Hide it, as today. | Yes |
| K | Keep the FAB, with a tooltip and an id, hidden while the keyboard is up. | A "+ New shortcut" action row at the head of the list and no FAB. | Yes |
| L | One new primitive, `FormReorderRow` in `form_rows/`, plus the hoisted `SettingsSectionHeader`. | Page-private rows, which the later sub-page slices would copy. | No |
| M | A screen reader reorders through the existing `categoryMoveUp` / `categoryMoveDown` / `categoryReorderLabel` keys; their texts are generic. | New generic keys in all three ARBs; or no actions. | No |
| N | The utility search stays, because it is on the must-not-change list. | Drop it — 14 fixed entries, a second search field that also locks drag. This is the designer's preference if the owner allows it. | No |
| O | The shortcuts header shows a count only when folded (the kit's "n options") or while filtering ("6 / 34"). | The always-on total. | No |
| P | The profile row has a fixed `view_day` glyph and no "Default" pill; the picker menu checks the bar being edited. | Keep the pill. | No |

## 6. What the design-reviewer re-renders and asserts after a build

Re-render the same matrix as `measurements.txt` and `proto_measurements.txt`:

- en / de / ro × 1.0 / 1.3 / 2.0 × 360, plus de 2.0 × 412, in light and dark.
- The states: every section open; every section folded through the menu (all seven fold); the shortcuts header pinned over rows; a chip on (Clear enabled, handles grey); a search with the keyboard faked at 320 (the FAB absent); the empty result; the empty list; a row lifted; a hidden row.

Assert with numbers, never by eye:

- **Text and title.** No built-in label or word is broken mid-word in any cell (checked through `RenderParagraph` line boundaries). The text column is 144 / 264 / 316 as §2.8 gives it, ±1. The app bar title is not ellipsized in any cell.
- **Pinned header.** The extent equals the formula of §2.5 (112 / 118 / 132, ±1). The chip row is 48 dp tall, and every chip's target is at least 48.
- **Targets.** Switch rows are at least 48 dp.
- **Colour.** The pinned header's ground is `pageGround`. Caption and empty-state colours are `onSurfaceVariant`, by token.
- **Lists.** The hairline indent is 88 side by side and 52 stacked. Both lists auto-scroll while a row is dragged at de 2.0 — for the utility list that is new behaviour.
- **Ids and flow.** Every existing id is present, and the device flow `05_hub_editor` passes.

The reference renders, under `renders/`:

- **Current:** `page_en_1.0_light_360_f00.png`, `page_en_1.0_light_360_f01.png`, `page_en_1.0_light_360_f04.png`, `page_en_1.0_light_360_f05.png`; `page_de_2.0_light_360_f00.png`, `page_de_2.0_light_360_f01.png`, `page_de_2.0_light_360_f04.png`, `page_de_2.0_light_360_f09.png`; `state_en_1.0_light_360_c_chip.png`; `state_en_1.0_light_360_e_empty_kb.png`; `state_de_2.0_light_360_c_chip.png`; `state_de_2.0_light_360_d_search_kb.png`; `state_de_1.0_dark_360_f_drag.png`; `folded_de_2.0_light_360.png`.
- **Proposed:** `proto_en_1.0_light_360_top.png`, `proto_en_1.0_light_360_pinned.png`, `proto_en_1.0_light_360_drag.png`; `proto_de_2.0_light_360_shortcuts.png`, `proto_de_2.0_light_360_pinned.png`, `proto_de_2.0_light_360_empty_kb.png`; `proto_de_2.0_dark_360_mid.png`.
- **Word widths:** `words.txt`.
- **Mock:** `markdown_settings_mock.html`, one folder up.

## 7. Later slices — listed, not designed

In the order the designer would take them:

1. **Vocabularies and the vocabulary editor** (`lib/pages/vocabularies_page.dart`, 256 lines; `lib/pages/vocabulary_editor_page.dart`, 230). They hold the §9 defects of the settings rework — the 0.6 alphas, the `fontSize: 17` header, the `Transform.scale(0.8)` switches — plus `Card`s and an extended FAB. The list goes onto the categories page's shape, with `FormReorderRow` where it reorders; the editor goes onto form rows.
2. **Bar assignment** (`lib/pages/note_bar_assignment_page.dart`, 334 lines). A `Card` list with 0.6 alphas becomes content rows on the kit's ground.
3. **Colors** (`lib/pages/markdown_colors_page.dart`, 379 lines). The syntax `Card` and the FAB move to kit or form rows, the swatches to `FormSwatchRow`.
4. **The shortcut editor** (`lib/pages/shortcut_editor_page.dart`, 2,033 lines: the heading-level chips, raw font sizes 11–18, alphas 0.3–0.8, a direct `SegmentedButton`, an extended FAB). It moves onto grouped form rows: a `FormTitleRow`-like label, `FormPickerRow` for the insert type, `FormStepperRow` for the repeat, `FormSwitchRow`, `settingsChoiceRow` for the counter operation. It is big enough for a record of its own.

## 8. Slice plan

- **S1 — The kit pieces.**
  - Files: `lib/widgets/settings_section_list.dart` (hoist `SettingsSectionHeader`; `SettingsSectionCard` builds through it); `lib/widgets/form_rows/reorder_row.dart` and `lib/widgets/form_rows.dart` (`FormReorderRow` and `FormReorderRow.wordsFit`); `lib/constants/form_metrics.dart` (`settingsPinnedSearchPadding`); `test/widgets/form_rows_test.dart`.
  - Gate: the settings, calendar settings and alerts goldens are unchanged; new cases cover side by side against stacked at 1.0 / 1.3 / 2.0 × 360 / 412, the 48 dp targets, the hairline indents 88 / 52, the move actions absent at the ends, and the off state's tokens; analyze is clean and the whole suite is green.
- **S2 — The config sections onto the kit.**
  - Files: `lib/pages/markdown_settings_page.dart`, split into part files under `lib/pages/markdown_settings_page/`; `lib/constants/semantics_ids.dart` (`markdown-fold-all`, `markdown-colors-row`, `markdown-vocabularies-row`, `markdown-shortcut-clear-filters`, `markdown-shortcut-add`); `test/pages/markdown_settings_page_test.dart`; `test/widgets/settings_navigation_contract_test.dart`.
  - Scope: Toolbar, Colors, Money and Autocomplete as a shrink-wrapped kit box; Bar profiles as its own box above the shortcuts; menus through `showFormMenu`; the title and fold-all moves; the body gated on the settings load.
  - Gate: every existing id is present; a legacy stored fold set round-trips, and fold-all folds seven; no overflow at de 2.0 × 360; switch rows at least 48 dp; the title not ellipsized at de 1.0 / 1.3 / 2.0.
- **S3 — The utility list as a sliver section.**
  - Files: the page's part file; `test/pages/markdown_settings_page_test.dart`.
  - Gate: dragging the first row to the last at de 2.0 scrolls the page; drag is off while filtering; the handles are wired to their index; the `markdownUtility(id)` ids are kept; the move-up / move-down actions reorder.
- **S4 — The shortcut list, the pinned header and the FAB.**
  - Files: the page's part files; `test/pages/markdown_settings_page_test.dart`; `test/pages/markdown_settings_destructive_test.dart`.
  - Gate: no built-in word broken mid-word in en / de / ro × 1.0 / 1.3 / 2.0 × 360 / 412; the pinned extent equals the formula; the chips hide while no category exists; the existing drag auto-scroll test stays green and drag is off while filtering; the FAB is named and absent with the keyboard up; the empty states use the tokens of §2.5.
- **S5 — The device pass and the design review.**
  - The `qa` settings flows (`05_hub_editor`), then dark, German and 2.0; `qa errors` clean.
  - Drag both lists past the fold on the device; check the "↵" glyph's coverage on the device.
  - A `design-reviewer` in a fresh context re-renders and asserts §6.

## 9. How to run this

Nothing starts before the owner has answered §5. "Yes to all" is an answer; a changed letter changes the slice that carries it — C, D and J are S2's; E, F and L are S1's and S4's; H, I, K and O are S4's; N is S3's.

- **The session:** a Fable 5.2 lead at `high`. The decisions are closed once §5 is answered, but S1 hoists the header every kit page draws through and adds a row primitive to the form rows, so the lead reads each slice's report against the kit's goldens before the next slice starts.
- **Per slice, in sequence** (one `flutter test` at a time): one `implementer` in a worktree of its own, briefed with §2, §3 and its own lines of §8; one `reviewer` on the diff against §3's list; for S2 to S4 one `design-reviewer` in a fresh context on §6, which is never shown §1's reasoning; the whole-suite gate from the lead.
- **S5** is one `qa-runner` (`qa pass settings -d emulator-5556`, then the hand checks §8 names) and the closing `design-reviewer`.
- **At each slice boundary** the status line is corrected, the uncommitted files are counted and a ready commit is offered; what a slice leaves is written into a Deferred section added then.
- The sub-pages of §7 are later records. This one ends at the page.
