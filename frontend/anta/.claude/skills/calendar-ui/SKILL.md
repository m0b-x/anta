---
name: calendar-ui
description: The calendar's UI language in ANTA - grouped form rows (lib/widgets/form_rows.dart), sheet chrome (FormSheetHandle/FormSheetHeader, height, bottom clearance, the dirty guard), the metrics constants (FormMetrics, RowMetrics, SurfaceRoles), the shared pieces (EventAvatar, AgendaPeriodNav, YearMonthTile, MonthDotMatrix, ValueChangeHighlight), semantics ids, and the widget-test pattern every sheet ships with. USE FOR - building or restyling any calendar sheet, page, row, picker, menu or tile; adding a bottom sheet anywhere in the app; any change to form_rows.dart or form_metrics.dart. Load together with anta-context and calendar-events.
---

# Calendar UI language

The grouped-row form the 2026-09-25 event editor redesign introduced is the look every calendar surface speaks from now on. The design record with the owner's decisions D1–D20 and the full token spec is [docs/event-editor-redesign-roadmap.md](../../../docs/event-editor-redesign-roadmap.md) §2–§3. This skill is the working rulebook; the record has the why.

**Adoption rule (owner, 2026-09-26).** New surfaces use the primitives below. An older sheet that still hand-rolls its chrome (a 4 px pill, its own header row, its own height factor) moves to the primitives **when a change opens it and touches that chrome** — never as a drive-by from an unrelated task. Today three sheets speak the language in full (the editor, Repeat, Icon & color); the Dates sheet uses the rows but hand-rolls its header; the day-list sheet, the overview page and every pre-redesign sheet use none of it.

## Files

| File | Holds |
| --- | --- |
| `lib/widgets/form_rows.dart` | every row primitive below; re-exports `form_metrics.dart` |
| `lib/constants/form_metrics.dart` | `FormMetrics` — every number a form uses |
| `lib/constants/row_metrics.dart` | `RowMetrics` — the browser rows' geometry the form metrics build on (group inset 16, radius 14, gap 18, divider indents 52 / 16) |
| `lib/constants/app_colors.dart` | `SurfaceRoles` on `ColorScheme`: `pageGround`, `rowGroup`, `rowDivider`, `menuSurface` |
| `lib/widgets/content_rows.dart` | `ContentRowShell` — the **browser's** row shell (folders, notes, search). A sibling, not a base: a form group is a `FormRowGroup`, never a mix |
| `lib/widgets/event_avatar.dart` | `EventAvatar` — the one preview of an event's look |
| `lib/widgets/agenda_period_nav.dart` | `AgendaPeriodNav` — ◄ title (+ count) [today] ► |
| `lib/widgets/year_month_tile.dart`, `lib/widgets/month_dot_matrix.dart` | year-overview tiles and their dot matrix |
| `lib/widgets/value_change_highlight.dart` | `ValueChangeHighlight` — flashes the row a picker just wrote to |
| `lib/constants/semantics_ids.dart` | `SemanticsIds` — the QA driver's stable ids |

## Surfaces and numbers

- Ground `colorScheme.pageGround`, groups `rowGroup`, hairlines `rowDivider`, menus `menuSurface` at `FormMetrics.menuRadius`. **No `Card`, no elevation, no shadow anywhere in a form or a sheet.** Light puts `surface` groups on a `surfaceContainer` ground and dark the reverse — read the roles, never the tokens.
- Every number comes from `FormMetrics` or `RowMetrics`. A new number gets a name there first; a literal in a widget file is a defect to fix, not a precedent to copy.
- Text roles: label 15 / 400 `onSurface`; value 15 / 400 `onSurfaceVariant`, tabular figures; action 15 / 500 `primary` (`error` when destructive); caption 13 / 400 `onSurfaceVariant` (`error` when it is one); counter 12; section label 11 / 500 uppercase, letter-spacing 0.88; glyph 22 `primary`; chevron 18 `outline`; trailing icon button 48 × 48 with a 20 px `outline` glyph. **Placeholders, hints and counters are `onSurfaceVariant`, never `outline`** — `outline` on `surface` is 4.3:1, under AA for text; glyphs may use it at 3:1.
- Rows are 48 dp minimum (`rowMinHeight`), two-line rows 62 (`twoLineRowMinHeight`), the title row 56. Disabled is 38 % opacity (`disabledOpacity`) with no ink — disabled, never hidden.

## Row primitives

| Widget | Reads as | Notes |
| --- | --- | --- |
| `FormRowGroup(children:)` | the rounded group | draws the hairline between rows itself, indented by each child's `FormDividedRow.dividerIndent` (52 with a glyph, 16 without, 70 under the title row); `trailingGap: false` on the last group of a sub-sheet |
| `FormSectionLabel(text:)` | WHEN / OCCURRENCES / … | uppercases for you; none above a capture group, an actions group, or inside a sub-sheet |
| `FormPickerRow` | `label … value ›` | the whole row is one `InkWell`; `value: null` = label only; `subRow: true` for a row another row reveals (indent 52, no glyph); `trailingButton:` makes a **two-target row** (the chevron drops, the button is a *sibling* of the ink well, never inside it); `semanticsLabel:` folds the row into one button node |
| `FormSwitchRow` | `label ⟷` | one semantics node, the whole row toggles; `subtitle:` gives the 62 dp two-line shape; `onChanged: null` disables |
| `FormActionRow` | `+ Add alert` / `Delete event` | `primary`; `destructive: true` = `error`; `onTap: null` disables |
| `FormRadioRow` | `label ✓` | `inMutuallyExclusiveGroup`, plain indent; the Repeat sheet's kind list |
| `FormChip` / `FormChipRow` | `[Count from 1] [Count from 0]` | 32 high, radius 8, no check icon; the tap target is padded to 48 by a render object, so never add your own padding; `caption:` is the line that reads the choice back |
| `FormCaption` | the small line under a row | `error: true` changes colour, never geometry |
| `FormMenuRow<T>` | `label … value ›` opening a menu | `MenuAnchor` right-aligned with the group, flips above when there is no room; `menuWidth` required; unfocuses before opening |
| `FormLabelValue` | the label · value pair | a `Wrap`: one line while both fit, else the value drops under the label; the label never ellipsizes, the value clamps at two lines |
| `FormGlyph`, `FormChevron`, `FormTrailingButton` | the parts | use these, never a raw `Icon` with a size |
| `FormSheetHandle`, `FormSheetHeader` | the chrome | below |

Rules the rows encode — keep them when you extend one:

- **A row's glyph names the field, never the value.** Only `EventAvatar` on the title row previews the event.
- **A row's height changes with locale and text scale, never at runtime.** The one exception is a value the user set that wraps to two lines (the Repeat row), and it sits below nothing that moves.
- **Sub-sheets never move under the finger**: constant height in every state (size the dependent area with an invisible template), a caption slot that always exists, controls disabled rather than hidden.
- No per-field label lines, no hint paragraphs, no helper text under a field. If a field needs explaining, the label is wrong.
- Save is a stock `FilledButton`; a sub-sheet confirms with a `TextButton` Done and returns its draft, `null` on cancel. A destructive confirmation is an `AlertDialog` with a `TextButton` cancel and a `FilledButton.tonal` confirm.

## Sheet chrome

Two shapes. Copy the one that fits; do not invent a third.

**A form sheet** (`EventEditorSheet.show`): `showModalBottomSheet(isScrollControlled: true, showDragHandle: false, enableDrag: false, backgroundColor: Colors.transparent, elevation: 0)` → `FractionallySizedBox(heightFactor: 0.92)` → `Material(color: pageGround, shape: top radius FormMetrics.sheetRadius)` → a `Column` of a `GestureDetector` holding `FormSheetHandle` + `FormSheetHeader`, then `Expanded(SingleChildScrollView(padding: groupInset, bodyTop, groupInset, bodyBottom + clearance))`. The sheet owns its drag because the route's own drag pops without consulting `PopScope`; `PopScope(canPop: false)` routes ✕, back, the system back gesture and the barrier through one `_leave()`, which asks only when a fingerprint of the form differs from the one captured at the end of `initState`. The header's hairline is a `ValueNotifier<bool>` fed by the body's scroll controller, never `setState`.

**A sub-sheet** (`EventLookSheet.show`, `EventRepeatSheet.show`): `showModalBottomSheet(isScrollControlled: true, useSafeArea: true, showDragHandle: false, backgroundColor: pageGround, shape: top radius sheetRadius)` → `ConstrainedBox(maxHeight: screen height × factor)` → `Column(mainAxisSize: min)` of `FormSheetHandle`, `FormSheetHeader(close · title · TextButton Done)`, `Flexible(SingleChildScrollView(…))`. Unguarded: a draft costs one tap to redo.

Both:

- **Bottom clearance is the larger of `viewInsets.bottom` and `viewPadding.bottom`**, added to the scroll view's bottom padding, or to the fixed footer (a docked markdown bar, an action row) when one sits below the scroll view. Never to the whole body of a fixed-fraction sheet, and never a `const EdgeInsets`. The header is the first `Column` child so it stays tappable whatever the inset. **Add every new sheet to `test/widgets/sheet_bottom_clearance_test.dart`** — this defect has shipped four times and that test is the only thing that has caught it.
- Leading icon `close_rounded` (tooltip `cancel`), **replaced**, never joined, by `arrow_back_rounded` (`back`) when the sheet is re-entered from another sheet's loop. One leading icon, a left-aligned title, one trailing action. Never a bottom action bar.
- Height: the editor is 0.92; sub-sheets clamp to a fraction of the screen. Eighteen older sheets carry eight different factors (0.6–0.92); when one migrates, take the shape above and the constant that shape uses. The day a second full-height form appears, its factor goes into `FormMetrics` and both read it.
- Every picker, menu and sub-sheet a form opens **drops focus first** (`_blur()`), or the modal's return re-raises the keyboard and scrolls the sheet back to the top.

## Shared pieces

- **`EventAvatar(icon:, color:)`** — radius 20, icon 24, background at α 0.16. The colour follows `EventSummaryProvider.colorFor` (the custom colour only while `tintIcon`, else the category colour). The **bar** rule (`colorValue ?? category`) is a different thing and belongs to grid bars, rails and stripes.
- **`AgendaPeriodNav`** — chevron | title + count | a fixed 48 dp today slot | chevron. `onTitleTap` makes the title the jump control (drop-down glyph, opens `MonthYearPickerSheet`). Null callbacks disable; the fixed slot is what keeps the title from shifting.
- **`YearMonthTile` + `MonthDotMatrix`** — the year overview's tiles, shared by the drill-down and the Dates sheet's year view. `YearMonthTile.gridDelegate` is the grid; `dayColors` paints per-day colours, `missedMask` / `dayMissedAlpha` fade missed days. One `Semantics` node per tile, the matrix excluded.
- **`ValueChangeHighlight(value:, child:)`** — wraps the row a pad or picker writes to, so an auto-closed entry is read back visibly.
- **Day grids** render `CalendarDayCell` + `CalendarDayBars`, never table_calendar's own decorations. Dates go through `CalendarDatePickerSheet`, times through `TimePadSheet`, categories through `CategoryPickerSheet`, month/year through `MonthYearPickerSheet` — never `showDatePicker` or `showTimePicker`.

## Semantics and automation

- `SemanticsIds` are the QA driver's contract: add one (kebab-case, never renamed) for any control a device script must hit whose label is not unique text — bar buttons, the halves of a paired control, a field. Since 2026-09-26 every editor row takes `identifier:` (`FormPickerRow`, `FormSwitchRow`, `FormActionRow`, `FormMenuRow`), the header takes `leadingIdentifier:`, the editor's body scroll view is `event-form`, the sub-sheets' Done are `repeat-done` / `look-done`, the Dates sheet's Save / Cancel are `date-picker-save` / `date-picker-cancel`, the detail sheet's Edit / Close are `event-detail-edit` / `event-detail-close`, and a day-panel row is `SemanticsIds.eventRow(event.id)`. **A new row in the editor gets an id in the same change**, and the flow that walks its screen (`tool/qa/flows/calendar/`) is updated in the same slice.
- **Titles are not targets on the calendar page**: every marked day cell's marker label carries its events' titles, so a row is addressed by `id:event-row-<eventId>`. Day cells themselves can carry no id (`table_calendar` wraps them with excluded semantics); a flow taps a day by its label, `{{longdate+N}}`.
- **`MenuAnchor` items expose no semantics nodes on iOS** (`FormMenuRow`: the priority and day-rail menus) — the menu draws, the tree shows only the scrim. Neither the QA agent nor a screen reader can pick an item. Known gap since 2026-09-26; fix it on the app side before adding a third menu.
- Every icon-only button has a `tooltip`; a `MergeSemantics` row exposes one node; `ExcludeSemantics` wraps decorative content (the avatar, the matrix).

## Tests every new surface ships with

Pattern: [test/widgets/event_look_sheet_test.dart](../../../test/widgets/event_look_sheet_test.dart) for a sub-sheet, `event_repeat_sheet_test.dart`, and `event_editor_redesign_test.dart` for a form. Open through the static `show`, capture the result in an outcome object, tap by label, assert the draft or `null`.

Cover at least:

1. Done returns the draft; cancel, the barrier and system back return `null`.
2. The clearance test gains the sheet.
3. `de` at `TextScaler.linear(2.0)` with no overflow and no clipped label (the editor suite's German block is the shape), plus a 360 × 780 surface.
4. Disabled states are disabled, not absent.
5. `form_rows.dart` has **no suite of its own**. The first change that touches it adds one: tap target 48, divider indents, disabled opacity, the two-target row's two nodes, the pair wrapping under a long value.

Device pass through the `qa-emulator` skill: `qa relaunch --fresh --seed tool/qa/fixtures/calendar.json` then `qa flows calendar` (seven saved flows, ~35 s), plus `qa set theme=dark locale=de text-scale=2.0` for the matrix and the boards' screenshots side by side; `qa errors` clean. A new surface adds a flow file; a changed one updates its flow in the same slice.
