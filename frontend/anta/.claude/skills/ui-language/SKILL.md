---
name: ui-language
description: ANTA's UI language, app-wide - which idiom a surface takes (grouped form rows, the browser's content rows, the settings kit), the row primitives (lib/widgets/form_rows.dart), sheet chrome (FormSheetHandle / FormSheetHeader / FormSheetFrame, height, bottom clearance, the dirty guard), the metrics constants (FormMetrics, RowMetrics, AppBarMetrics, SurfaceRoles), menus and dialogs, semantics ids, and the widget-test pattern every sheet ships with. USE FOR - building or restyling any sheet, page, row, picker, menu, dialog or tile anywhere in the app; adding a bottom sheet; any change to form_rows.dart, form_sheet_frame.dart, form_menu_item.dart, form_metrics.dart, content_rows.dart or app_dialogs.dart. Load together with anta-context and the area skill (calendar-events + calendar-ui for the calendar, markdown-engine for the editor); ui-revamp when the change is a rework.
---

# UI language

The app speaks one UI language: grouped rows on a layered ground, one sheet chrome, role-named numbers. Navigation round 2 (2026-09-07, `docs/navigation-round-2-roadmap.md`) set its tokens — the palette, `SurfaceRoles`, `RowMetrics`, the bars, the menu anatomy — and the 2026-09-25 event editor redesign built the form rows and the sheet chrome on them. The design record with the owner's decisions D1–D20 and the full token spec is [docs/event-editor-redesign-roadmap.md](../../../docs/event-editor-redesign-roadmap.md) §2–§3. This skill is the working rulebook; the records have the why. The calendar's own widgets and its catalogue of ids are in `calendar-ui`.

**Adoption rule (owner, 2026-09-26).** New surfaces use the primitives below. An older surface that still hand-rolls its chrome (a 4 px pill, its own header row, its own height factor) moves to the primitives **when a change opens it and touches that chrome** — never as a drive-by from an unrelated task — unless a roadmap schedules it. Two do: `docs/calendar-language-adoption-roadmap.md` for the calendar (the drive-by rule is suspended there while its tiers run) and `docs/ui-language-adoption-roadmap.md` for the rest of the app. **Which surfaces speak the language today is the status table of those two records, never a list in a skill.**

## Which idiom a surface takes

Decide this before any layout. The three are siblings and are never mixed inside one surface.

| The surface is | It speaks | Built from |
| --- | --- | --- |
| a form, a picker, a filter or a detail view — anything in a bottom sheet, a list inside one included | **grouped form rows** | `FormRowGroup` and the row primitives on the sheet chrome, both below |
| a list of the user's own things on a page — folders, notes, search results, any list page (a list page is the browser's language, not a form's) | **the browser's content rows** | `ContentRowShell` and `ContentSectionHeader` (`lib/widgets/content_rows.dart`) on `RowMetrics` |
| a settings page | **the settings kit** | `SettingsSectionList` / `SettingsSectionData` / `SettingsEntry` under `SettingsAppBar` — every settings page in the app speaks it, so restyling it is one app-wide decision (open in `docs/ui-language-adoption-roadmap.md`), never a change to one page |

Around them: a bar reads `AppBarMetrics` (48 dp toolbar, 22 px glyphs, a 17 / 500 title); a menu is a popup route of `FormMenuChoiceItem`s (below); a confirmation or a prompt comes from `AppDialogs` (below). The calendar's panel cards (`rowGroup` cards on the `pageGround` panel) are the calendar's own idiom and stay — `calendar-events`.

## Files

| File | Holds |
| --- | --- |
| `lib/widgets/form_rows.dart` | every row primitive below; re-exports `form_metrics.dart` and `form_sheet_frame.dart` |
| `lib/widgets/form_sheet_frame.dart` | `FormSheetFrame` — the form sheet's shell (2026-09-27): `PopScope(canPop: false)` → `onLeave`, the finger-following drag over `chrome`, the snap-back, the dismiss threshold (`FormMetrics.sheetDismissVelocity` / a quarter of the height), `onDismiss` for a clean fling; the editor and the description sheet ride on it |
| `lib/widgets/form_menu_item.dart` | `FormMenuChoiceItem` (the radio-announced `PopupMenuItem` every menu of the language is built from), `FormMenuItemRow` (glyph · label · check, `color:` for a destructive item), and the one anchor rule `formMenuPosition` / `formMenuHeight` — right edge on the anchor's, under it while the menu fits above the bottom inset, else above |
| `lib/constants/form_metrics.dart` | `FormMetrics` — every number a form uses |
| `lib/constants/row_metrics.dart` | `RowMetrics` — the browser rows' geometry the form metrics build on (group inset 16, radius 14, gap 18, divider indents 52 / 16) |
| `lib/constants/app_colors.dart` | `SurfaceRoles` on `ColorScheme`: `pageGround`, `rowGroup`, `rowDivider`, `menuSurface` |
| `lib/widgets/content_rows.dart` | `ContentRowShell` — the **browser's** row shell (folders, notes, search). A sibling, not a base: a form group is a `FormRowGroup`, never a mix |
| `lib/widgets/settings_reorder.dart` | `ReorderHandle`, `ReorderLockedHint`, `reorderDragProxy` and `reorderProxyRadius` — the reorder chrome every draggable list shares; `FormDragHandle` wraps the handle, and a form list's `proxyDecorator` is the proxy over a `ClipRRect(reorderProxyRadius)` |
| `lib/widgets/value_change_highlight.dart` | `ValueChangeHighlight` — flashes the row a picker just wrote to |
| `lib/constants/app_bar_metrics.dart` | `AppBarMetrics` — the bars' geometry: toolbar 48, glyphs 22, title 17 / 500, the browser's large title |
| `lib/widgets/app_dialogs.dart` | `AppDialogs` — the one dialog layer: `confirm`, `confirmDiscard` (a form sheet's leave guard), `textInput` and the choosers |
| `lib/widgets/settings_section_list.dart` | the settings kit: `SettingsSectionList`, `SettingsSectionData`, `SettingsEntry` |
| `lib/constants/semantics_ids.dart` | `SemanticsIds` — the QA driver's stable ids |

## Surfaces and numbers

- Ground `colorScheme.pageGround`, groups `rowGroup`, hairlines `rowDivider`, menus `menuSurface` at `FormMetrics.menuRadius`. **No `Card`, no elevation, no shadow anywhere in a form or a sheet.** Light puts `surface` groups on a `surfaceContainer` ground and dark the reverse — read the roles, never the tokens.
- Every number comes from `FormMetrics` or `RowMetrics`. A new number gets a name there first; a literal in a widget file is a defect to fix, not a precedent to copy.
- Text roles: label 15 / 400 `onSurface`; value 15 / 400 `onSurfaceVariant`, tabular figures; action 15 / 500 `primary` (`error` when destructive); caption 13 / 400 `onSurfaceVariant` (`error` when it is one); counter 12; section label 11 / 500 uppercase, letter-spacing 0.88; glyph 22 `primary`; chevron 18 `outline`; trailing icon button 48 × 48 with a 20 px `outline` glyph. **Placeholders, hints and counters are `onSurfaceVariant`, never `outline`** — `outline` on `surface` is 4.3:1, under AA for text; glyphs may use it at 3:1.
- Rows are 48 dp minimum (`rowMinHeight`), two-line rows 62 (`twoLineRowMinHeight`), the title row 56. Disabled is 38 % opacity (`disabledOpacity`) with no ink — disabled, never hidden.
- The generic `AppSpacing` scale (`xs` … `xxl` and the `EdgeInsets` built from it) is the older surfaces' vocabulary: a surface on the language reads none of it. It retires surface by surface — a rework's record names what it retires (`ui-revamp`). `AppSpacing.fabClearance` is a role, not the scale, and stays.

## Row primitives

| Widget | Reads as | Notes |
| --- | --- | --- |
| `FormRowGroup(children:)` | the rounded group | draws the hairline between rows itself, indented by each child's `FormDividedRow.dividerIndent` (52 with a glyph, 16 without, 70 under the title row); `trailingGap: false` on the last group of a sub-sheet |
| `FormSectionLabel(text:)` | WHEN / OCCURRENCES / … | uppercases for you, ß as SS (`toUpperCase` leaves ß alone); none above a capture group, an actions group, or inside a sub-sheet |
| `FormPickerRow` | `label … value ›` | the whole row is one `InkWell`; `value: null` = label only; `subRow: true` for a row another row reveals (indent 52, no glyph); `trailingButton:` makes a **two-target row** (the chevron drops, the button is a *sibling* of the ink well, never inside it); `semanticsLabel:` folds the row into one button node; `caption:` a line of the row's own data under the pair, inside the same node (the next occurrences) — never help text; an id-less row is one `MergeSemantics` node; `leading:` a 40 dp widget (`EventAvatar`) in the glyph's place — the 56 dp title-row shape, indent 70, and with a `caption:` the check row's 62 dp two-line shape (the template picker); `enabled: false` = 38 % and inert with the node's flag inside the row's own merge — `onTap: null` alone draws a *read* row, never a dimmed one |
| `FormSwitchRow` | `label ⟷` | one semantics node, the whole row toggles; `subtitle:` gives the 62 dp two-line shape; `onChanged: null` disables |
| `FormActionRow` | `+ Add alert` / `Delete event` | `primary`; `destructive: true` = `error`; `onTap: null` disables |
| `FormRadioRow` | `label ✓` | `inMutuallyExclusiveGroup`, plain indent; the Repeat sheet's kind list |
| `FormCheckRow` | `label ☐` / `[avatar] label ☑` | the multi-select twin of `FormRadioRow`: a padded M3 `Checkbox` in a 48 dp slot flush with the row's end, or with `exclusive: true` the radio shape (check glyph, `inMutuallyExclusiveGroup`) that can carry a `leading` avatar (56 dp, indent 70); `caption:` the row's own second line (62 dp, clamped at two lines); `trailingButton:` a second target beside the row (a preset's ⋮); `handle:` a `FormDragHandle` in a 48 dp slot flush with the row's start (`FormMetrics.dragHandleSlot`), the text and the hairline at 52 — a third node beside the row's and the ⋮'s (a reorderable list's rows, 2026-09-29); `onChanged: null` = 38 % and inert; `identifier` on the row's one node |
| `FormDragHandle` | `≡` at a row's start | the shared `ReorderHandle` of `settings_reorder.dart` (so every reorderable list reads as one system) in a `dragHandleSlot` target, one node with its accessible `label:` (a label, never a `Tooltip` — its long-press recogniser would kill the drag) and `identifier:`; `index:` wires it to the enclosing reorderable list; `enabled: false` greys it **in place** and drags nothing (a live search) |
| `FormRowShell` | one row of a group, drawn alone | the row-at-a-time twin of `FormRowGroup` for a list a `Column` cannot hold (a `ReorderableListView`, a sliver): same tokens, corners on `first` / `last` only, the hairline under every row but the last at the child's own indent, `trailingGap` below the last; the ends are a clipped `Material`, a middle row a `ColoredBox` hosting a transparent `Material` for its ink |
| `FormSearchRow` | `🔍 Search … ✕` | a collapsed field padded to the row's 48 dp (`FormMetrics.searchFieldPadding`), never autofocused, `clearTooltip:` required; the clear button is a sibling node in a slot that always exists, so the field never changes width; `onTapOutside` drops the keyboard; `identifier` lands on the text-field node |
| `FormChip` / `FormChipRow` | `[Count from 1] [Count from 0]` | 32 high, radius 8, no check icon; the tap target is padded to 48 by a render object, so never add your own padding; `caption:` is the line that reads the choice back; `glyph:` + `label:` make a **labelled** chip row — `[glyph] label … chips`, the chips dropping under the label when they do not fit (the detail sheet's presence pair); `FormChip(identifier:)` for a chip a script hits; `FormChip(onTap: null)` = 38 %, inert, announced disabled, in place; the 32 dp is a **minimum** — above 160 % text the chip grows with its label inside the 48 dp target, never cuts it; `FormChipRow(indented: false)` is a chip row that stands alone (the quick alarm's presets, the custom offset's units): the group's inset, a 48 dp row, plain divider indent — the default is the sub-row a switch reveals, inset 52 |
| `FormCaption` | the small line under a row | `error: true` changes colour, never geometry; `maxLines:` clamps with an ellipsis; `padding: FormMetrics.groupCaptionPadding` under a whole group (a no-match line) |
| `FormMenuRow<T>` | `label … value ›` opening a menu | a popup route of `FormMenuChoiceItem`s, never a `MenuAnchor`: each item a `menuItemRadio` node carrying its `FormMenuItem.identifier` and checked state on both platforms; at least `menuWidth` wide (`FormMetrics.menuWidth` for a short choice list), growing to `FormMetrics.menuMaxWidth` when a label needs it, right edge on the group's, under the row while it fits above the bottom inset else above it; focus dropped before it opens; `onSelected: null` = 38 %, inert, `enabled: false`, no menu (the agenda's Fasting rows while no tradition is configured) |
| `FormLabelValue` | the label · value pair | a `Wrap`: one line while both fit, else the value drops under the label; the label never ellipsizes, the value clamps at two lines |
| `FormTitleRow` | `[avatar] title field` + counter | the 56 dp title row of the editor, the quick alarm and the template form: a 40 dp `leading` box, a collapsed multi-line field that refuses a newline (20 / 500 typed, 20 / 400 hint), the counter line from `counterFrom`, `error` at `maxLength`; indent 70; the field is as tall as what it shows (`maintainHintSize: false`), so a hint that wraps at large text leaves no blank line under a typed value; **the whole row is the field's tap target** (the row owns a focus node when none is passed) and **the hint is the field's accessible name while it holds text** — a collapsed field is otherwise nameless to a screen reader once typed |
| `FormHeroRow` | `[glyph] value / caption ›` | a sheet's one large value (the quick alarm's time): one button node "value, caption" with `tooltip:` as its hint — it draws no `Tooltip`, so a test finds it by id; the value at `heroValueSize` fitted onto a line that is held open at full size, so the row's height follows the text scale and never the string; plain indent |
| `FormStepperRow` | `label … [−] value [+]` | the Repeat sheet's interval, the alert's custom offset: `onDecrement` / `onIncrement` null disables that button in place; the value 15 / 500 tabular in a box as wide as `widestValue` (the widest text the caller will show, laid out unseen; never under `stepperValueMinWidth`), so the buttons never move while the value changes; when the label's longest word cannot sit beside the stepper, the stepper drops under the label, end-aligned — by locale, scale and width, never by the value; plain indent. A stepper's tooltip names what the button does to the *result* — a smaller interval is "More frequent" |
| `FormCaptionSlot` | a caption that never changes the height | `candidates:` are laid out unseen under the shown `child`, so the slot is as tall as its tallest text: a caption that reads a choice back, a warning that arrives late |
| `FormIndentedRow` | a wrapper carrying a divider indent | `FormRowGroup` reads the indent only off a `FormDividedRow`, so a row wrapped in a `ValueChangeHighlight` falls back to 52; wrap the pair when the row's own indent is another (a plain-indent row, the editor's description cell) |
| `FormValueDot` | the colour dot before a value | a `valueLeading:` at `FormMetrics.valueDotSize` (the Icon & color row) |
| `FormGlyph`, `FormChevron`, `FormTrailingButton` | the parts | use these, never a raw `Icon` with a size |
| `FormSheetHandle`, `FormSheetHeader`, `FormHeaderTextButton` | the chrome | below; the text button is the header's trailing action (a sub-sheet's Done, the detail sheet's Edit), and the header caps its trailing slot at `FormMetrics.headerActionMaxShare` with the label ellipsizing past it |

Rules the rows encode — keep them when you extend one:

- **A row's glyph names the field, never the value.** Only `EventAvatar` on the title row previews the event.
- **A row's height changes with locale and text scale, never at runtime.** The one exception is a value the user set that wraps to two lines (the Repeat row), and it sits below nothing that moves.
- **Sub-sheets never move under the finger**: constant height in every state (size the dependent area with an invisible template), a caption slot that always exists, controls disabled rather than hidden.
- No per-field label lines, no hint paragraphs, no helper text under a field. If a field needs explaining, the label is wrong.
- Save is a stock `FilledButton`; a sub-sheet confirms with a `TextButton` Done and returns its draft, `null` on cancel. A destructive confirmation is an `AlertDialog` with a `TextButton` cancel and a `FilledButton.tonal` confirm.

## Sheet chrome

Two shapes, and one box they share. Copy the one that fits; do not invent a third.

**A form sheet** (`EventEditorSheet.show`, `EventDescriptionSheet.show`, `EventTemplateEditorSheet.show`) — for a sheet with typed text or a docked bar: `showModalBottomSheet(isScrollControlled: true, showDragHandle: false, enableDrag: false, backgroundColor: Colors.transparent, elevation: 0)` → `FractionallySizedBox(heightFactor: FormMetrics.sheetHeightFactor)` → **`FormSheetFrame(chrome: Column[FormSheetHandle, FormSheetHeader], body: [Expanded(SingleChildScrollView(padding: groupInset, bodyTop, groupInset, bodyBottom + clearance)), …a fixed footer], onLeave: _leave, isClean: () => !_isDirty, onDismiss: _popDiscarding)`** (2026-09-27, Tier 1 — never a copy of its drag code inside a sheet). The frame owns the drag because the route's own drag pops without consulting `PopScope`; its `PopScope(canPop: false)` routes ✕, back, the system back gesture and the barrier through the sheet's one `_leave()`, which asks (`AppDialogs.confirmDiscard`) only when the form is dirty — a fingerprint of every field in the editor, the text against what `loadText` left in the description sheet; a clean fling pops through `onDismiss`, a dirty one snaps back and asks. The header's hairline is a `ValueNotifier<bool>`, never `setState`; a new sheet takes it from `FormHeaderHairline` (`scrolled` to the header, `watch(child:)` around the scroll view, `dispose`), which hears the scroll metrics change as well as the scroll — a body that gets shorter (the keyboard closing) corrects its offset without telling a controller's listener, and the hairline would stay on over a body that no longer scrolls.

**A sub-sheet** (`EventLookSheet.show`, `EventRepeatSheet.show`, the read-only `EventDetailSheet.show`, the four filter surfaces, the agenda filters sheet, the time pad, the month/year picker, the template picker, the sound sheet, the alert sheet and its Custom sub-sheet, the quick alarm): `showModalBottomSheet(isScrollControlled: true, useSafeArea: true, showDragHandle: false, backgroundColor: pageGround, shape: top radius sheetRadius)` → `ConstrainedBox(maxHeight: screen height × factor)` → `Column(mainAxisSize: min)` of `FormSheetHandle`, `FormSheetHeader(close · title · FormHeaderTextButton Done)`, `Flexible(SingleChildScrollView(…))`. Unguarded: a draft costs one tap to redo.

**The form sheet's box without its guard** (`CalendarDatePickerSheet`, `IconPickerSheet` — Tier 1 D10) is for a *filler*: a body that is a grid, a matrix or a list under a live search. The sub-sheet's route flags with `FractionallySizedBox(heightFactor: FormMetrics.sheetHeightFactor)` and `Column(stretch)` of handle, header, the body in an `Expanded` and an optional fixed footer; route drag, no `PopScope`. A content-tall filler would change height between Month / Year / List or jump on every keystroke, and "nothing moves under the finger" outranks content-tall. The Dates sheet's Today is a fixed 48 dp slot after the title in the month grid's own header row and in the year row (`AgendaPeriodNav`'s grammar), never a second header icon; the icon picker's search group is pinned between the header and the grid.

Both:

- **Bottom clearance is the larger of `viewInsets.bottom` and `viewPadding.bottom`**, added to the scroll view's bottom padding, or to the fixed footer (a docked markdown bar, an action row) when one sits below the scroll view. Never to the whole body of a fixed-fraction sheet, and never a `const EdgeInsets`. The header is the first `Column` child so it stays tappable whatever the inset. **Add every new sheet to `test/widgets/sheet_bottom_clearance_test.dart`** — this defect has shipped five times and that test is the only thing that has caught it. Read both insets through `MediaQuery`, never from `View.of(context)`: the app-root `KeyboardInsetGuard` is what keeps Android's stale keyboard inset out of every sheet, and a sheet needs no stale-inset guard of its own.
- Leading icon `close_rounded` (tooltip `cancel`), **replaced**, never joined, by `arrow_back_rounded` (`back`) when the sheet is re-entered from another sheet's loop. One leading icon, a left-aligned title, one trailing action. Never a bottom action bar.
- Height: `FormMetrics.sheetHeightFactor` (0.92) is the editor's fixed height, the two fillers' box and every sub-sheet's clamp. A sheet that still carries its own factor takes a shape above and that constant when it migrates.
- Every picker, menu and sub-sheet a form opens **drops focus first** (`_blur()`), or the modal's return re-raises the keyboard and scrolls the sheet back to the top.
- **A message raised from inside a sheet goes through `OverlaySnackbar`**, never `CustomSnackbar`: a Scaffold's snackbar is drawn on the page *under* the modal route, where nobody sees it ("Template saved" was invisible until 2026-10-03). The overlay bar is a live region and cancels its own timer.

## Shared pieces

- **`ValueChangeHighlight(value:, child:)`** — wraps the row a pad or picker writes to, so an auto-closed entry is read back visibly.

## Dialogs

`AppDialogs` (`lib/widgets/app_dialogs.dart`) is the one dialog layer, and a form sheet's leave guard is `AppDialogs.confirmDiscard`. **Two confirm styles exist and they disagree**: the rule above (a `TextButton` cancel and a `FilledButton.tonal` confirm — the editor's delete dialog and `confirmDiscard`) and `AppDialogs.confirm(isDestructive: true)`, which predates the language and draws an error-filled confirm under a 48 dp icon at every other delete in the app. Which of the two is the language's is an open app-wide decision (`docs/ui-language-adoption-roadmap.md`); until it is taken, a migrated surface keeps the dialog its old version showed and never adds a third style.

## Semantics and automation

- `SemanticsIds` (`lib/constants/semantics_ids.dart`) are the QA driver's contract: add one (kebab-case, never renamed) for any control a device script must hit whose label is not unique text — bar buttons, the halves of a paired control, a field. The row primitives take `identifier:` and the header `leadingIdentifier:`; a sheet's close and its trailing action each carry one. A form sheet's drag surface is `excludeFromSemantics: true` (`FormSheetFrame` — its drag callbacks otherwise read as a scrollable) and a sheet whose root is a `Focus` (the time pad) sets `includeSemantics: false` so the header's title stays its own node. **A new row gets an id in the same change**, and the flow that walks its screen (`tool/qa/flows/<area>/`) is updated in the same slice. The calendar's catalogue of ids is in `calendar-ui`.
- **Every menu is a popup route of `FormMenuChoiceItem`s, never a `MenuAnchor`** (whose items expose no semantics nodes on iOS — the gap of 2026-09-26, closed 2026-09-27 by D12 of the filters record): a `FormMenuRow`'s items are `menuItemRadio` nodes carrying their ids on Android and iOS, so a flow picks one by id (`09_filters.txt`) and a screen reader hears which is checked.
- Every icon-only button has a `tooltip`; a `MergeSemantics` row exposes one node; `ExcludeSemantics` wraps decorative content (the avatar, the matrix).
- **An app-bar title that is a button of its own carries `header` and `namesRoute` itself, and its `AppBar` sets `excludeHeaderSemantics`** (`CalendarViewMenu`, 2026-09-26). `AppBar`'s own header annotation would have no label over a separate node, and Android announces a route by the first named node's label — the page would open to silence.
- **A tooltip beside a label is never spoken on focus on Android 9+** (the bridge hands it to `setTooltipText`); where its words matter, put them in the node's `hint` on Android only — iOS already folds the tooltip into the label.

## Tests every new surface ships with

Pattern: [test/widgets/event_look_sheet_test.dart](../../../test/widgets/event_look_sheet_test.dart) for a sub-sheet, `event_repeat_sheet_test.dart`, and `event_editor_redesign_test.dart` for a form. Open through the static `show`, capture the result in an outcome object, tap by label, assert the draft or `null`.

Cover at least:

1. Done returns the draft; cancel, the barrier and system back return `null`.
2. The clearance test gains the sheet.
3. `de` at `TextScaler.linear(2.0)` with no overflow and no clipped label (the editor suite's German block is the shape), plus a 360 × 780 surface.
4. Disabled states are disabled, not absent.
5. `form_rows.dart` has its own suite, `test/widgets/form_rows_test.dart` (ids on each row kind, the two-target row's two nodes, the chip's 48 dp target, disabled opacity, the header text button, the picker caption inside the row's node, the labelled chip row on one line and wrapping under a long label at 360; the check row's node, heights and clamped caption, the search row's two nodes, edge taps and outside tap, the menu's radio items with ids, its alignment, widening and flip). A change to a primitive extends it in the same slice.

Device pass through the `qa-emulator` skill: the area's fixture and saved flows first (`qa relaunch --fresh --seed tool/qa/fixtures/<area>.json`, then `qa flows <area>`), then `qa set theme=dark locale=de text-scale=2.0` for the matrix and the boards' screenshots side by side; `qa errors` clean. A new surface adds a flow file; a changed one updates its flow in the same slice. Only the calendar has a fixture and flows today (`calendar-ui`) — another area gets both in its rework's first slice (`ui-revamp`).
