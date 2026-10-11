---
name: ui-language
description: ANTA's app-wide UI language - which idiom a surface takes, the row primitives, the sheet chrome, the role-named metrics, menus and dialogs, semantics ids, and the widget-test pattern every surface ships with. USE FOR - building or restyling any sheet, page, row, picker, menu, dialog or tile anywhere in the app; adding a bottom sheet; any change to form_rows.dart, form_sheet_frame.dart, form_menu_item.dart, form_metrics.dart, content_rows.dart or app_dialogs.dart. Load with anta-context and the area skill; ui-mock for a mock, ui-revamp for a rework.
---

# UI language

The calendar's own pieces are in `calendar-ui`.

**Adoption rule (owner, 2026-09-26).** New surfaces use the primitives below. An older surface that still hand-rolls its chrome (a 4 px pill, its own header row, its own height factor) moves to the primitives **when a change opens it and touches that chrome** — never as a drive-by from an unrelated task — unless a roadmap schedules it. Two do: `docs/calendar-language-adoption-roadmap.md` for the calendar (the drive-by rule is suspended there while its tiers run) and `docs/ui-language-adoption-roadmap.md` for the rest of the app. **Which surfaces speak the language today is the status table of those two records, never a list in a skill.**

## Which idiom a surface takes

Decide this before any layout. The four are siblings and are never mixed inside one surface.

| The surface is | It speaks | Built from |
| --- | --- | --- |
| a form, a picker, a filter or a detail view — anything in a bottom sheet, a list inside one included | **grouped form rows** | `FormRowGroup` and the row primitives on the sheet chrome, both below |
| a list of the user's own things on a page — folders, notes, search results, any list page (a list page is the browser's language, not a form's) | **the browser's content rows** | `ContentRowShell` and `ContentSectionHeader` (`lib/widgets/content_rows.dart`) on `RowMetrics` |
| a settings page | **the settings kit** | `SettingsSectionList` / `SettingsSectionData` / `SettingsEntry` under `SettingsAppBar` — every settings page in the app speaks it, so restyling it is one app-wide decision (open in `docs/ui-language-adoption-roadmap.md`), never a change to one page |
| a screen that takes the phone over until it is answered — the ring screen | **a takeover page** | read rows of the kit (`FormRowGroup`, `FormReadTitleRow`, `FormActionRow`) on `pageGround`, bottom-anchored in a reversed scroll over a pinned pair of buttons, the one that costs least on the bottom edge; no sheet chrome, no app bar, no chevrons, no form controls, no perpetual animation; its own numbers in `AlarmMetrics`, its ground and system bars from `AlarmGround`. One member today, `lib/pages/alarm_page.dart` (`docs/alert-surfaces-redesign-roadmap.md`) |

Around them: a bar reads `AppBarMetrics` (48 dp toolbar, 22 px glyphs, a 17 / 500 title); a menu is a popup route of `FormMenuChoiceItem`s (below); a confirmation or a prompt comes from `AppDialogs` (below). The calendar's panel cards (`rowGroup` cards on the `pageGround` panel) are the calendar's own idiom and stay — `calendar-events`.

## Files

| File | Holds |
| --- | --- |
| `lib/widgets/form_rows.dart` | every row primitive below; re-exports `form_metrics.dart` and `form_sheet_frame.dart` |
| `lib/widgets/form_sheet_frame.dart` | `FormSheetFrame`, the form sheet's shell (`references/sheet-chrome.md`) |
| `lib/widgets/form_menu_item.dart` | `FormMenuChoiceItem`, `FormMenuItemRow`, `formMenuPosition` (`references/row-primitives.md`) |
| `lib/constants/form_metrics.dart` | `FormMetrics` — every number a form uses |
| `lib/constants/row_metrics.dart` | `RowMetrics`, the browser rows' geometry (`references/metrics.md`) |
| `lib/constants/app_colors.dart` | `SurfaceRoles` on `ColorScheme`: `pageGround`, `rowGroup`, `rowDivider`, `menuSurface` |
| `lib/widgets/content_rows.dart` | `ContentRowShell`, the browser's rows — never mixed into a form group (`references/row-primitives.md`) |
| `lib/widgets/settings_reorder.dart` | `ReorderHandle`, the shared reorder chrome (`references/row-primitives.md`) |
| `lib/widgets/value_change_highlight.dart` | `ValueChangeHighlight` — flashes the row a picker just wrote to |
| `lib/constants/app_bar_metrics.dart` | `AppBarMetrics`, the bars' geometry (`references/metrics.md`) |
| `lib/constants/alarm_metrics.dart` | `AlarmMetrics`, the takeover page's numbers (`references/metrics.md`) |
| `lib/widgets/alarm_ground.dart` | `AlarmGround`, the takeover page's ground (`references/metrics.md`) |
| `lib/widgets/app_dialogs.dart` | `AppDialogs` — the one dialog layer: `confirm`, `confirmDiscard` (a form sheet's leave guard), `textInput` and the choosers |
| `lib/widgets/settings_section_list.dart` | the settings kit: `SettingsSectionList`, `SettingsSectionData`, `SettingsEntry` |
| `lib/constants/semantics_ids.dart` | `SemanticsIds` — the QA driver's stable ids |

## Surfaces and numbers

- Every number comes from `FormMetrics` or `RowMetrics` — and, for what only a takeover page has, `AlarmMetrics`. A new number gets a name there first; a literal in a widget file is a defect to fix, not a precedent to copy.
- Colours are roles, never tokens; **no `Card`, no elevation, no shadow in a form or a sheet**; placeholders, hints and counters are `onSurfaceVariant`, never `outline`; disabled is 38 %, never hidden; no `AppSpacing` scale on a language surface, `fabClearance` aside (`references/metrics.md`).

## Row primitives

All in `form_rows.dart`; read a primitive's row in `references/row-primitives.md` before you use or extend it.

- Groups: `FormRowGroup`; `FormRowShell`, one row drawn alone (a sliver, a reorderable list); `FormSectionLabel`; `FormIndentedRow`, a wrapper's divider indent.
- Rows: `FormPickerRow` `label … value ›`; `FormMenuRow<T>`, opening a menu; `FormSwitchRow` `label ⟷`; `FormActionRow` `+ Add alert`; `FormRadioRow` `label ✓`; `FormCheckRow` `label ☐`; `FormStepperRow` `[−] value [+]`; `FormSearchRow`; `FormSwatchRow`, the colour strip; `FormChip` / `FormChipRow`.
- Titles: `FormTitleRow`, the title field; `FormReadTitleRow`, its read-only twin; `FormHeroRow`, a sheet's one large value.
- Text: `FormLabelValue`; `FormCaption`; `FormCaptionSlot`, a caption that never changes the height; `FormValueDot`.
- Parts: `FormGlyph`, `FormChevron`, `FormTrailingButton` — never a raw `Icon` with a size; `FormDragHandle` `≡`.
- Chrome: `FormSheetHandle`, `FormSheetHeader`, `FormHeaderTextButton`.

Rules the rows encode — keep them when you extend one:

- **A row's glyph names the field, never the value.** Only `EventAvatar` on the title row previews the event.
- **A row's height changes with locale and text scale, never at runtime.** The one exception is a value the user set that wraps to two lines (the Repeat row), and it sits below nothing that moves.
- **Sub-sheets never move under the finger**: constant height in every state (size the dependent area with an invisible template), a caption slot that always exists, controls disabled rather than hidden.
- No per-field label lines, no hint paragraphs, no helper text under a field. If a field needs explaining, the label is wrong.
- Save is a stock `FilledButton`; a sub-sheet confirms with a `TextButton` Done and returns its draft, `null` on cancel. A destructive confirmation is an `AlertDialog` with a `TextButton` cancel and a `FilledButton.tonal` confirm.

## Sheet chrome

Two shapes, and one box they share. Copy the one that fits; do not invent a third.

- **Form sheet** (typed text, a docked bar): `FormSheetFrame`, never a copy of its drag code; ✕, back and the barrier reach one `_leave()`, which asks `AppDialogs.confirmDiscard` only when the form is dirty.
- **Sub-sheet** (the rest): content-tall under the `sheetHeightFactor` clamp, unguarded.
- **Filler** (a grid, a matrix, a live-search list, a body that switches views): the form sheet's box, route drag, no `PopScope`, no `FormSheetFrame`, no header hairline.

Both:

- **Bottom clearance = max(`viewInsets.bottom`, `viewPadding.bottom`) read through `MediaQuery`**, on the scroll view's bottom padding or the fixed footer, never a fixed-fraction sheet's whole body; **every new sheet joins `sheet_bottom_clearance_test.dart`**.
- Leading icon `close_rounded` (tooltip `cancel`), **replaced**, never joined, by `arrow_back_rounded` (`back`) when the sheet is re-entered from another sheet's loop. One leading icon, a left-aligned title, one trailing action. Never a bottom action bar.
- **A live-apply sheet** (every control writes at once): ✕ with the `close` tooltip, an empty trailing slot.
- Height: `FormMetrics.sheetHeightFactor` (0.92) is the editor's fixed height, every filler's box and every sub-sheet's clamp. A sheet that still carries its own factor takes a shape above and that constant when it migrates.
- Every picker, menu and sub-sheet a form opens **drops focus first** (`_blur()`), or the modal's return re-raises the keyboard and scrolls the sheet back to the top.
- **A message from inside a sheet goes through `OverlaySnackbar`**, never `CustomSnackbar`.
- Each shape's flags and anatomy, and these rules in full: `references/sheet-chrome.md`.

## Dialogs

`AppDialogs` is the one dialog layer. Its two confirm styles disagree and the choice is open: a migrated surface keeps its old dialog and adds no third (`references/sheet-chrome.md`).

## Semantics and automation

- **A new row gets an id in the same change** (`SemanticsIds`, kebab-case, never renamed), and its flow in `tool/qa/flows/<area>/` changes in the same slice.
- **Every menu is a popup route of `FormMenuChoiceItem`s, never a `MenuAnchor`.**
- Every icon-only button has a `tooltip`; a `MergeSemantics` row exposes one node; `ExcludeSemantics` wraps decorative content (the avatar, the matrix).
- An app-bar title that is a button names the route itself; a page pushed only by `rootPushInstant` scopes its own.
- A tooltip beside a label is not spoken on Android 9+: words that matter go in the node's `hint`, Android only.
- These rules in full: `references/row-primitives.md`.

## Tests every new surface ships with

Pattern: [test/widgets/event_look_sheet_test.dart](../../../test/widgets/event_look_sheet_test.dart) for a sub-sheet, `event_repeat_sheet_test.dart`, and `event_editor_redesign_test.dart` for a form. Open through the static `show`, capture the result in an outcome object, tap by label, assert the draft or `null`.

Cover at least:

1. Done returns the draft; cancel, the barrier and system back return `null`.
2. The clearance test gains the sheet.
3. `de` at `TextScaler.linear(2.0)` with no overflow and no clipped label (the editor suite's German block is the shape), plus a 360 × 780 surface.
4. Disabled states are disabled, not absent.
5. `form_rows.dart` has its own suite, `test/widgets/form_rows_test.dart`; a change to a primitive extends it in the same slice.

Device pass through `qa-emulator`: the area's fixture and flows, then dark, `de`, 2.0 text; `qa errors` clean; a new surface adds a flow file. In full: `references/row-primitives.md`.

## References

|File|Holds|Read it when|
|---|---|---|
| `references/row-primitives.md` | each primitive's anatomy; menus, reorder, the browser's rows; the long semantics and test rules | you use, extend or test a primitive |
| `references/sheet-chrome.md` | the three shapes, `FormSheetFrame`, the chrome rules in full, `ValueChangeHighlight`, the confirm styles | you build a sheet or a dialog |
| `references/metrics.md` | the language's origin and records; colour and text roles, heights, `AppSpacing`; the metrics files | you need a number or a colour |
| `references/ux-direction.md` | the app-wide UX direction: palette, keyboard insets, time entry | you touch the theme or the keyboard |
