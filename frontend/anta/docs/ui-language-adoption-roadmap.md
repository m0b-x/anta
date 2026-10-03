# UI Language Adoption — the app-wide master record (2026-10-02)

**Status: PLAN.** Inventory taken 2026-10-02 at `d501f42` by two read-only
audits; no tier outside the calendar has started and the tier order in §6 is
a proposal the owner has not decided. The calendar runs from its own master,
`docs/calendar-language-adoption-roadmap.md` (Tier 1 committed `7e0423b`,
Tier 2 in progress since 2026-10-02). Written because the owner said on
2026-10-02 that the whole UI is to be reworked, slowly, the way the calendar
was. Line numbers below are from that read; re-grep every one before a tier
is planned.

## 0. How to run this

This is the master record the `ui-revamp` skill describes: the inventory, the
tier order, the status table, the retire list and the open app-wide
decisions live here and nowhere else.

- **One tier, one record, one conversation, one owner commit.** A tier's
  record is `docs/<area>-<topic>-roadmap.md` in the `ui-revamp` shape; this
  file gets one row in §7 per tier and nothing else from it.
- **Skills to load** in a tier's session: `anta-context`, `ui-language`,
  `ui-revamp`, `verify`, `l10n`, `qa-emulator`, plus the area skill
  (`markdown-engine` for the editor, `calendar-events` + `calendar-ui` for
  the calendar).
- **Models.** The owner names them when a tier starts. The standing split is
  Fable for plans and records, Opus for exploration and implementation; the
  calendar pass runs on `fable-max` by the owner's choice of 2026-09-27.
- **Slice 0 is the safety net.** Outside the calendar no area has a QA
  fixture or saved flows, and several have no widget suite at all (§4). A
  tier writes them against the old UI, green, before its first visual change.
- **No tier takes a decision of §3 alone.** A tier that needs one stops and
  asks the owner in lettered options.
- **Do not commit.** The owner reviews and commits.

## 1. Why

The language has two layers, and the app is on them unevenly.

- **Tokens** — the palette, `SurfaceRoles`, `RowMetrics`, `AppBarMetrics`, the
  menu anatomy — came from navigation round 2 (2026-09-07,
  `docs/navigation-round-2-roadmap.md`). The browser, search and the editor's
  bars and rows are on them.
- **Widgets** — the `Form*` rows, `FormSheetHandle` / `FormSheetHeader` /
  `FormSheetFrame`, `FormMenuItemRow` — came from the 2026-09-25 event editor
  redesign (`docs/event-editor-redesign-roadmap.md`), which applied round 2's
  grammar to a sheet. **Twenty-one files use them, all calendar.** No file
  outside the calendar imports `form_rows.dart`, `form_menu_item.dart` or
  `form_sheet_frame.dart`, or reads `FormMetrics`.

So four generations of chrome sit side by side: stock Material (`ListTile`,
`Card`, `AlertDialog`, a FAB) on the settings, counter and database pages; a
hand-rolled sheet chrome (a 40 × 4 pill over a 16 / 600 title) on the sheets
the browser opens; round 2's tokens on bars, rows and menus; and the form
language in the calendar. The seams show wherever one opens another: the
browser's rows open the old pill sheets, the editor's 48 dp bar sits over a
toolbar with its own decoration, and every settings page wears a gradient bar
no other page has.

## 2. Where the language already reaches outside the calendar

Tokens and rules, never widgets:

1. **Browser rows.** `ContentRowShell`, `ContentSectionHeader` and
   `RowMetrics` drive the folder and note rows, the smart rows, the search
   rows, All notes, the selection bar and the bottom bar. Section labels
   (11 / 500 / 0.88) and divider indents (52 / 16) already equal
   `FormSectionLabel` and `FormMetrics`.
2. **Bars.** All on `AppBarMetrics` (48 / 22 / 17-500, the numbers of
   `FormSheetHeader`) and `pageGround`. The settings bar takes the geometry
   and keeps its gradient.
3. **Menus.** The folder, note, ancestor and find-option menus use the
   `AppTheme.menu*` anatomy `FormMenuItemRow` was derived from, not the
   widget: a fixed 236 wide, labels that ellipsize, no row ids. The widget
   wraps its labels and grows to 280, which is what fixed German at 200 %.
4. **Reorder chrome.** `settings_reorder.dart` is used by
   `pages/markdown_settings_page.dart:1572, 1956, 1995`.
5. **The bottom-clearance rule.** `bar_switcher_sheet.dart` and
   `pairing_sheet.dart` gained it and a clearance-test case on 2026-10-01
   (`d501f42`); their chrome is still hand-rolled.
6. **The colour picker.** `color_picker_sheet.dart` (calendar Tier 3) is
   shared with `pages/markdown_colors_page.dart:76, 83`, so migrating it
   moves a notes surface too.
7. **The dirty-guard dialog.** `AppDialogs.confirmDiscard` sits in the
   app-wide dialog layer; only the calendar calls it.

## 3. Open app-wide decisions

Each is the owner's, asked as lettered options when the first tier needs it.

| # | Decision | What it touches | State |
| --- | --- | --- | --- |
| 1 | **What the settings kit becomes.** `SettingsSectionList` puts `surfaceContainer` cards on a `surface` ground (`app_theme.dart:161–165`, `settings_section_list.dart:347–351`) — in light the inverted layering round 2's D13 fixed for the browser; every row carries a description line, which the form idiom forbids; its radii are 16 / 12 and its headings 16 / 600; its bar keeps a gradient "until the settings pages are redesigned" (`COPILOT_CONTEXT.md:252`) | 14 settings surfaces, 7.9k lines, plus the calendar's settings and appearance pages; 19 gradient bars (`SettingsAppBar` ×18, `UnifiedAppBar.settings` in `vocabulary_editor_page`) | open — the first decision of the rollout; nothing in settings moves before it |
| 2 | **The confirm dialog's style.** The language's rule and the editor's delete dialog are a `TextButton` cancel and a `FilledButton.tonal` confirm; `AppDialogs.confirm(isDestructive: true)` is error-filled under a 48 dp icon (`app_dialogs.dart:53–61, 74–85`) | one file, about 77 calls in 31 files; `AppDialogs` has no test suite | open — the calendar's Tier 2 does not need it (none of its three sheets shows a destructive confirm); taken when tier A starts |
| 3 | **The generic constants.** `AppSpacing`'s scale (212 uses in 26 files) collides with the role-named metrics (`lg` 16 = `groupInset`, `md` 12 = `rowEndPadding`, `sm` 8 = `bodyTop`); `AppTextStyles` is dead; `AppIconSizes` (10 uses) has no 22; `FontConstants`' UI sizes clash by name (`caption` 12 vs `FormMetrics.captionSize` 13, `body` 14 vs the label's 15) and its `h1` / `h2` are unused | every surface outside the language | direction set in `ui-language` (a migrated surface reads none of the scale; it retires surface by surface); deleting the classes is the last tier's job |
| 4 | **One metrics home for bars, menus and the search sheet.** `AppBarMetrics` equals `FormMetrics` (48 / 22 / 17-500) without aliasing it; `AppTheme.menu*` duplicates `FormMetrics.menuRowHeight` / `menuIconSize` / `menuPadding` / `menuRadius` with a different floor (236 vs 220 wide); `NoteSearchMetrics` is a parallel sheet spec (radius 16 vs 28, height 0.6 vs 0.92, header 56 vs 48) | bars, four menus, the editor's match-list sheet | open |
| 5 | **The drawer.** A stock `Drawer` of `ListTile`s with tinted icon chips, a gradient header with a light-only shadow, labels at 11 / 700 / 0.9 (`app_drawer.dart:88–101, 298–368, 524–552`). Round 2 marked it out of scope ("unstyled in the mock") | 664 lines, one suite | open |
| 6 | **The light surface ramp.** The owner chose a lavender ramp on 2026-09-07 (`surface` `#F9F4FE`, `surfaceContainer` `#E9E1F1`, `surfaceContainerHigh` `#E3DAEC`, `outlineVariant` `#C6BED3`); it exists only in the stash `theme test`, and the tree is on the mock tokens (`#FEF7FF` / `#F3EDF7`) | every light surface; `label_contrast_test` re-measures against `rowGroup` | open — the stash cannot be applied whole (§9) |
| 7 | **The full-screen alarm** (`pages/alarm_page.dart`) — a ring screen is not a form | 298 lines | raise at calendar Tier 4 |

## 4. Inventory outside the calendar (2026-10-02, `d501f42`)

Chrome today: **TOK** on the token layer with no `Form*` widget · **MAT** raw
Material · **HR** hand-rolled chrome · **KIT** the settings kit · **DLG** the
`AppDialogs` helpers. Files are under `lib/widgets/` unless they start with
`pages/`, `handlers/` or `utils/`. "nav-r2" is
`docs/navigation-round-2-roadmap.md`. Line counts are whole files.

### 4.1 Navigation

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| Drawer | `app_drawer.dart` | MAT + HR | 664 | nav-r2 marks it out of scope | `app_drawer_test` |
| Language / theme / about, from the drawer | `app_drawer.dart:587–663` | DLG; stock `showAboutDialog` | in above | none | none |
| Back / menu pair | `leading_nav_pair.dart` | TOK | 152 | nav-r2 D18 | `leading_nav_pair_test` |
| Editor / search / settings bars | `unified_app_bars.dart` | TOK; the settings variant adds a gradient | 510 | nav-r2 | `unified_app_bars_test` |
| Large browser bar + ancestor menu | `folder_sliver_app_bar.dart` | TOK; the menu hand-built | 354 | nav-r2 | `folder_sliver_app_bar_test` |
| In-place search bar | `search_field_app_bar.dart` | TOK | 183 | nav-r2 | through the browser suites |
| Selection bar / action bar | `selection_app_bar.dart`, `selection_action_bar.dart` | TOK | 66 + 136 | nav-r2, colour labels | browser suite, `content_rows_test` |
| Folder ⋮ / note ⋮ | `folder_overflow_menu.dart`, `note_overflow_menu.dart` | MAT on the `AppTheme` menu numbers | 248 + 184 | nav-r2 | `overflow_menu_anatomy_test` |
| All notes ⋮ | `pages/all_notes_page.dart:398–414` | MAT, none of the menu numbers | ~17 | nav-r2 | `all_notes_page_test` |

### 4.2 Folder browser

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| Browser page (smart rows, grouped rows, bottom bar) | `pages/optimized_folder_content_page.dart` | TOK | 2,444 | nav-r2, colour labels | `optimized_folder_content_page_test` |
| All notes / Recent | `pages/all_notes_page.dart` | TOK | 508 | nav-r2 | `all_notes_page_test` |
| Folder and note rows | `folder_row.dart`, `note_row.dart`, `content_rows.dart` | TOK | 337 + 408 + 380 | nav-r2 | `content_rows_test`, `note_row_date_test` |
| Row long-press sheet | `content_rows.dart:272–345` | HR + MAT (40 × 4 pill, 16 / 600 title, `Divider`, `ListTile`) | ~75 | colour labels | `content_rows_test` |
| Sort chooser + two sort sheets | `pages/optimized_folder_content_page.dart:1444–1674` | MAT (`ListTile`, the selection in bold `primary`, no checked semantics) | ~230 | mentioned only | partly, through the browser suite |
| Move history | `move_history_sheet.dart` | HR + MAT (`DraggableScrollableSheet`) | 203 | none | none |
| Move-to folder picker | `folder_picker_dialog.dart` | MAT `AlertDialog` | 743 | none | none |
| New folder / rename / delete / import progress | `app_dialogs.dart` | DLG | — | none | none |

### 4.3 Search

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| Standalone search route | `pages/search_page.dart` | TOK | 175 | nav-r2 | `search_page_test` |
| Search surface (recents, results, scope chips) | `search_surface.dart` | TOK + `AppSpacing` + `ChoiceChip` | 688 | nav-r2, colour labels | `search_surface_header_test` |

### 4.4 Note editor and toolbar

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| Editor page chrome | `pages/optimized_note_editor_page.dart` | TOK bar | 2,643 | nav-r2 | `optimized_note_editor_page_test` |
| Stats strip | `note_editor_chrome.dart` | HR | 101 | nav-r2 | `note_editor_chrome_test` |
| Toolbar, with its reorder mode | `markdown_bar.dart` | HR (`AppTheme.editorBarDecoration`) | 1,074 | nav-r2; live-editor docs | `markdown_bar_chrome_test`, `markdown_bar_share_test` |
| Header-level menus | `markdown_bar.dart:398–415`, `handlers/header_shortcut_handler.dart` | MAT `showMenu`, not anchored to the control | ~20 + 138 | none | none |
| Find / replace bar + options menu | `note_search_bar.dart` | HR + MAT | 1,100 | nav-r2 | `note_search_bar_test` |
| Match-list sheet | `note_match_list_sheet.dart` | HR on its own `NoteSearchMetrics` sheet spec | 575 | none | through `note_search_bar_test` |
| Toolbar profile switcher | `bar_switcher_sheet.dart` | HR + MAT | 299 | none | the clearance test only |
| Vocabulary suggestion bar | `vocabulary_suggestion_bar.dart` | HR | 172 | `vocabulary-autocomplete-feature.md` | none |
| Title edit / delete / share chooser | `app_dialogs.dart`, `note_export_dialog.dart` | DLG | 40 | nav-r2 D6 | none |

### 4.5 Settings

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| The settings kit | `settings_section_list.dart`, `settings_search_field.dart`, `slider_setting_row.dart` | KIT | 464 + 109 + 127 | none | `settings_section_fold_test` |
| App settings | `pages/settings_page.dart` | KIT + `SwitchListTile` + `SegmentedButton` | 830 | none | `settings_page_test` |
| Developer options | `pages/developer_options_page.dart` | KIT | 322 | none | none |
| Markdown shortcuts | `pages/markdown_settings_page.dart` | MAT (`Card`, three menus + `showMenu`, a FAB, `AlertDialog`s) + the shared `ReorderHandle` | 2,527 | none | none |
| Shortcut editor | `pages/shortcut_editor_page.dart` | MAT (dropdowns, `SegmentedButton`, a FAB) | 2,001 | none | a behaviour test only |
| Markdown colours | `pages/markdown_colors_page.dart` | MAT + the calendar's `ColorPickerSheet` | 377 | none | none |
| Per-note bar assignment | `pages/note_bar_assignment_page.dart` | MAT | 285 | none | none |
| Icon picker | `icon_picker_dialog.dart` | MAT `AlertDialog` — duplicates `IconPickerSheet` | 380 | none | none |
| Vocabularies + editor | `pages/vocabularies_page.dart`, `pages/vocabulary_editor_page.dart` | MAT | 208 + 226 | feature doc only | none |

### 4.6 Money ledger, counters, colour labels

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| Ledger detail sheet | `money_detail_sheet.dart` | HR (`DraggableScrollableSheet`) + MAT | 243 | feature docs only | none |
| Per-note currency | `pages/note_money_currency_page.dart` | MAT | 299 | feature docs only | none |
| Counter management | `pages/counter_management_page.dart` | MAT (`ReorderableListView`, `Card`, `ListTile`, a menu, a FAB) | 577 | none | none |
| Per-note counter values | `pages/counter_per_note_page.dart` | MAT | 507 | none | none |
| Counter picker, counter form, note picker | `counter_picker_dialog.dart`, `counter_form_dialog.dart`, `note_picker_dialog.dart` | MAT `AlertDialog` | 398 + 137 + 221 | none | none |
| Label picker sheet | `label_swatch_strip.dart` | HR (the row sheet's pill and title) | 251 | `colour-labels-roadmap.md` | `label_picker_sheet_test` |
| Label dot / stripe | `label_dot.dart`, `ContentRowShell` | TOK | 120 | same | `content_rows_test`, `label_contrast_test` |

### 4.7 Backup, databases, sync, onboarding, permissions

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| Database page (switch, create, rename, delete, import / export) | `pages/database_settings_page.dart` | MAT (`Card` ×4, menus) + 14 `AppDialogs` calls | 1,086 | none | none |
| Export chooser | `note_export_dialog.dart` | DLG | 40 | nav-r2 D6 | none |
| Sharing (sync) settings | `pages/sync_settings_page.dart` | KIT + `ListTile` ×10 | 483 | `cloud-sync-phase-01-pairing.md` | none |
| Pairing sheet | `pairing_sheet.dart` | HR | 378 | same | the clearance test only |
| Onboarding | `pages/onboarding_page.dart` | HR | 228 | none | none |
| Permissions page + tile | `pages/permissions_page.dart`, `permission_tile.dart` | KIT | 327 + 93 | none | `permissions_page_test` |
| Permission prompt | `permission_prompt_dialog.dart` | MAT | 187 | `event-alerts-roadmap.md` | `permission_prompt_dialog_test` |

### 4.8 Cross-cutting

| Surface | File | Chrome | Lines | Record | Widget tests |
| --- | --- | --- | --- | --- | --- |
| The dialog layer | `app_dialogs.dart` | MAT | 450; about 77 calls in 31 files | none | none |
| Snackbars | `utils/custom_snackbar.dart`, `overlay_snackbar.dart` | HR | 223 + 72 | none | `custom_snackbar_keyboard_test` |
| The error tile | `main.dart` | HR | ~80 | none | `app_error_widget_test` |

### 4.9 Roll-up

| Area | Surfaces | Lines | Widget suites | Record | QA flows |
| --- | --- | --- | --- | --- | --- |
| Settings | 14 | 7.9k | 2 | none | none |
| Editor + toolbar | 12 | 6.1k | 5 | nav-r2 parity only | none |
| Folder browser | 11 | 5.1k | 5 | nav-r2 | none |
| Navigation | 16 | 2.5k | 7 | nav-r2 | none |
| Counters | 6 | 1.9k | 0 | none | none |
| Sync / onboarding | 5 | 1.7k | 2 | pairing only | none |
| Backup / databases | 4 | 1.1k | 0 | none | none |
| Search | 3 | 0.9k | 2 | nav-r2 | none |
| Cross-cutting | 3 | 0.8k | 2, none for `AppDialogs` | none | none |
| Money ledger | 2 | 0.5k | 0 | feature docs only | none |
| Colour labels | 3 | 0.4k | 2 | yes | none |
| Calendar, Tiers 2–4 | 15 | 8.4k | mixed | the calendar master | 13 flows |

About 29k lines outside the calendar. `tool/qa/fixtures/` holds `basic.json`
and `calendar.json`; `tool/qa/flows/` holds `calendar/` only.

## 5. Retire list

What exists twice, and which one stays. A tier that removes one strikes it
here.

| Goes | Stays | Where |
| --- | --- | --- |
| `IconPickerDialog` (`icon_picker_dialog.dart`, a Material `AlertDialog`) | `IconPickerSheet` | settings; `AppDialogs.iconPicker` |
| `SettingsSearchField` | `FormSearchRow` | the settings kit (decision 1) |
| The 40 × 4 pill over a 16 / 600 title | `FormSheetHandle` + `FormSheetHeader` | the row long-press sheet, the sort sheets, move history, the label picker |
| `NoteSearchMetrics`' sheet spec | the sub-sheet shape | `note_match_list_sheet.dart` |
| The hand-built menu rows on `AppTheme.menu*` | `FormMenuChoiceItem` / `FormMenuItemRow` | the folder, note, ancestor and find-option menus, the All notes ⋮ |
| `UnifiedAppBar.settings`' gradient and the second `AppBarStyle` member | one bar style | 19 pages (decision 1) |
| `AppSpacing`'s generic scale | `FormMetrics` / `RowMetrics` roles | 212 uses in 26 files — heaviest: `alerts_page` 38, the fasting sheets 24, `note_search_bar` 20, `markdown_colors_page` 16, `note_match_list_sheet` 15, `search_surface` 14 |
| `AppTextStyles` (unused; cited only in `app_dialogs.dart:16`) | — | delete with the dialog decision |
| `FontConstants.h1` / `h2` (unused) and its UI sizes | the editor font-size settings stay | the header menu reads `h3`–`h6` |
| Literals in widget files: the drawer's 11 / 700 / 0.9 labels, the kit's radii, `MenuCountPill` 18 / 11, the selection bar's 11 px label | named metrics | each surface's own tier |

## 6. Proposed tier order — not decided

A proposal of 2026-10-02 for the owner to change. Reasoning: cheapest reach
first, then by how often a surface is met, with settings last because it
waits on decision 1 and is the largest.

| Tier | Scope | Needs first | Size |
| --- | --- | --- | --- |
| A | **The shared layers**: the confirm dialog (decision 2) with a first `AppDialogs` suite; the four hand-built menus and the All notes ⋮ onto the language's menu items; `AppBarMetrics` and the menu numbers aliased into one home (decision 4) | decisions 2 and 4 | 1 conversation |
| B | **The browser's sheets**: the row long-press sheet, the sort chooser and its two sheets, move history, the label picker — onto the sheet chrome, each into the clearance test; the move-to picker from a dialog to a sheet is a design question | a browser fixture and flows (Slice 0) | 1 conversation |
| C | **The editor's satellites**: the toolbar profile switcher, the match-list sheet, the ledger detail sheet, the header-level menus anchored and localized, the find bar's options menu | an editor fixture and flows; `markdown-engine` | 1 conversation |
| D | **Counters and databases**: two counter pages and three dialogs; the database page | suites first — neither area has one | 1–2 conversations |
| E | **Settings**: the kit, then its pages; the markdown shortcut pages are the two largest files in the app outside the editor and the browser | decision 1 | 2–3 conversations |
| F | **The drawer, onboarding, sync, the light ramp** | decisions 5 and 6 | 1 conversation |
| G | **Delete the retired constants** (§5) | every tier above | half a conversation |

## 7. Status

| Tier | Status |
| --- | --- |
| Calendar | its own master, `docs/calendar-language-adoption-roadmap.md` §9: Tier 1 COMMITTED `7e0423b`; Tier 2 IMPLEMENTED and REVIEWED 2026-10-03, uncommitted; Tiers 3–4 not started |
| A – G | PLAN — the order is not decided |

## 8. Defects the audit found, outside any tier

Small, verified in the tree on 2026-10-02, not fixed:

- `markdown_bar.dart:407` — the header menu's label is a hard-coded English
  `'Header $level'`, against the l10n rule.
- `selection_app_bar.dart:56–62` — the select-all `IconButton` has no tooltip.
- `selection_action_bar.dart:113, 129` — `Theme.disabledColor` where the
  language uses 38 % opacity, and a literal 11 px label.
- The sort sheets expose no checked state to a screen reader.
- Six sheets are missing from `test/widgets/sheet_bottom_clearance_test.dart`:
  the row long-press sheet, the sort sheets, move history, the ledger detail
  sheet, the match-list sheet, the label picker.
- Status lines that still say "uncommitted" for committed work:
  `navigation-round-2-roadmap.md` (:3–8, :1432) and the editor, detail,
  header, Filters and Tier 1 records. The `ui-revamp` rule of 2026-10-02 has
  the next session that opens each one correct it.

Found on the device by the calendar's Tier 2 pass (2026-10-03, Pixel
emulator, API 36), app-wide and not fixed there:

- **The system navigation bar stays light in dark theme** — a light grey bar
  with dark icons after a runtime theme switch and after a cold start in
  dark, on every page. Content scrolls under it legibly in light and badly
  in dark. Nothing sets the bar's style for the dark theme; edge-to-edge on
  current Android makes this a theme-level change to decide once (decision
  6's neighbour), with a device check on a gesture-navigation phone.
- **`AppDialogs.confirmDiscard`'s title breaks mid-word in German at 200 %**
  ("Ungespeichert / e Änderungen"): one long word in a dialog's title style.
  It belongs with decision 2.
- **The description sheet** (`EventDescriptionSheet`, shared by the editor
  and the template form): its editing text does not follow the system text
  scale — the editor's own font-size setting drives it — and its markdown
  bar offers the money shortcuts although money is off in descriptions.
  Tier C's surface (the editor's satellites) with the `markdown-engine`
  skill.
- **Engine noise**: scrolling a settings page with semantics on logs
  `E/AccessibilityBridge … transform has not been initialized`. Harmless;
  the QA tool's known-noise list carries it since the same pass.
- **Messages raised from inside a modal sheet through `CustomSnackbar` are
  drawn on the page under the sheet**, where nobody sees them. Fixed in the
  calendar's Tier 2 for the editor's "Template saved", the template form's
  "Save failed", the alert sheet's "no sound picker" and the two filter
  sheets' messages (`OverlaySnackbar`; the rule is in `ui-language`). Still
  so in `category_editor_sheet.dart:180`, `color_palette_sheet.dart:60 / 69 /
  80 / 117`, `color_picker_sheet.dart:232`, `removed_holidays_sheet.dart:58`
  (calendar Tier 3) and `pairing_sheet.dart:299` (sync).

- **Seen once on the device, unreproduced**: after saving a preset from the
  saved-filters sheet (Tier 1's surface), the new row's ⋮ did nothing until
  another menu had opened and closed, and the sheet then moved up. Worth a
  look when that sheet is next opened.

Fixed in that pass although outside the calendar's sheets, because they sat
on the way to them: the Calendar settings page going blank in German at
200 % (a trailing `DropdownButton` consuming its tile) and its default-alert
rows squeezing their titles at large text. Both are instances of one
pattern the settings kit allows — **an unbounded `trailing:`** — which
decision 1 should close for every settings page.

## 9. Facts and traps for planning

- **The stash `theme test` cannot be applied whole.** It is based on
  `6efdfa0` (2026-09-07); the browser page has moved by about 470 lines since
  and its test by about 1,370, and the stash carries an older bottom bar
  (56 / 52 / 26; HEAD is 60 / 54 / 28). Liftable on their own: the
  `ColorScheme` hunk of `app_theme.dart`, the hex maps of
  `app_theme_test.dart`, the `month_dot_matrix.dart` comment, the one-line
  `markdown_color_contrast_test.dart` change and the doc text. Colour labels
  landed after it; `label_contrast_test` reads `rowGroup` live and must be
  re-run (yellow `#A8890E` is estimated to fall from about 3.19:1 to about
  3.10:1 — arithmetic, not a test run).
- **Fixing `AppDialogs.confirm` restyles about seventy dialogs at once**, and
  the class has no suite. Write the suite first.
- **`color_picker_sheet.dart` is shared** with the markdown colours page;
  its chrome moves in calendar Tier 3 and the picker's behaviour is
  must-not-change there.
- **The adoption roadmap of the calendar is the worked example** of a master
  record; its Tier 1 record (`docs/calendar-language-tier-1-roadmap.md`) is
  the worked example of a tier.

## 10. Deferred

- Predictive back, a navigation bar in place of the drawer, `SearchAnchor`:
  rejected or deferred in `navigation-round-2-roadmap.md` §6 and not reopened
  here.
- The search index's performance items B11–B13 of the same record: not UI.
