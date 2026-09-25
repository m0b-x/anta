# Event Editor Redesign — Roadmap & Slice Prompts (2026-09-25)

**Status: SHIPPED 2026-09-25** (uncommitted on top of `f189e0d`; the owner
reviews and commits). Slices 1–4 are done: the grouped-row sheet, the Repeat
and Icon & color sheets, the menus, the discard guard with the sheet-owned
drag, the tests, the device pass (iOS simulator, light + dark, en + de), the
independent review with its fixes, and the docs (`calendar-events-feature.md`
§6.3 + the 2026-09-25 addendum, `COPILOT_CONTEXT.md`, the `calendar-events`
skill). Line numbers below are as of `f189e0d` and have drifted.

**Deviations from this document, and why:**
- **The title counter has its own key**, `eventTitleCount` ("{count}/{limit}"),
  rendered under the field by a `ListenableBuilder` while `buildCounter`
  suppresses the field's default counter: the collapsed decoration has no
  counter slot to style, and the description counter under it is already a
  localized key.
- **The scope strip's Reset day button takes the strip's remaining width and
  ellipsizes** rather than sitting after a `Spacer`: with the chips at text
  scale 2.0 (or the test font) the three do not fit in 360 dp, and a row that
  overflows is worse than a clipped label.
- **The re_editor fork gained two things** the description cell needs:
  `CodeScrollController.contentHeight` (the last layout's document height,
  soft wraps counted — the measurement §3.5 recommends over the line count)
  and a `forceRepaint()` that defers its recompute to the next layout pass.
  The old synchronous recompute could flip the scrollable's drag state
  outside layout (`replaceGestureRecognizers` assert) once the box was one
  line tall; the note editor's use is unaffected. `ModernEditorWrapper` gained
  `editorPadding`, `editorLineHeight` and `paintGround` so the cell can draw
  its own margins.
- **The description height is resolved inside layout, not after the frame**:
  a `_DescriptionBox` render object lays the editor out, reads
  `contentHeight`, and relays out at the new height (up to three passes), so
  a line added or removed never shows a one-frame jump — the post-frame poll
  the first cut used did (found in the second review).
- **The discard fingerprint covers the alert list and the effective skipped
  days unconditionally** and is re-baselined once the settings seed the
  default alert into a still-clean form; gating alerts on `_alertsTouched`
  made removing the only alert clean and re-saving one unchanged dirty (found
  in the second review).
- **The assume-absent tests** that asserted the old hint sentences now assert
  the chip selection instead — the hints are gone by design (§4.2).
- **Device pass scope**: the iOS simulator (iPhone 17 Pro Max, 440 × 956 dp)
  in light and dark, English and German. No Android emulator was attached to
  this machine, so the Android half did not run. Text scale 2.0 and the
  360 × 780 phone are pinned by widget tests (`layout stress` group) instead
  of screenshots; the five-alert cap is pinned by a widget test (the alert
  sheet refuses the harness's duplicate default drafts, so it could not be
  reached by tapping on the device). The sheet's own drag measured 0 janky
  frames over 131, so the §3.8 fallback was not needed.
- **D9 is amended for scale (owner, 2026-09-25, after the first review).** Per-date
  rows with a ✕ stay for two and three dates; from **four dates on** the WHEN
  group shows one bundled row, `Dates · 10 dates · Sep 25 – Oct 16, 2026 ›`
  (`eventDatesLabel` + `eventDatesSummary` over `recurrenceSpecificDates`;
  both years named when the span crosses one), that opens the multi picker's
  month grid — the editor that scales to 300 dates — with Add date still under
  it. The group's height is the same at four dates and at three hundred, the
  shape flips only on a picker return, and removing a date past three is a
  deselect in the grid. Five candidates were boarded on the canvas page
  "Many dates" (a windowed list with a Dates sheet, disclosure in place, a
  bounded inner scroller, month rows); the sheet list was dropped because a
  300-row list is not a better editor than the grid.
- **The form drops focus before it opens any picker, menu or sub-sheet**
  (`_blur()`): with the title autofocused (D4), a modal's return re-focused
  the title, re-raised the keyboard and scrolled the sheet back to the top —
  the "adding an alert resets the form" report. Focus now stays where the
  user's tap left it; a widget test pins the scroll position.
- **A chip's 48 dp target is a hit-padding render object** (the shape of
  Flutter's own `_InputPadding`), so the ink stays inside the 32 dp chip
  instead of lighting the whole target — the first fix put the ink well on
  the padded box and the ripple showed around the chip.
- **Two harness observations, not app defects**: the QA agent's accessibility
  dump places `MenuAnchor` items below the screen (Flutter's own semantics
  rects are correct, checked in a scratch widget test), and a label tap on the
  `Add description` placeholder does not focus the editor because the
  placeholder is a separate static node — a real touch passes through it.

Design source: the canvas **"Event editor layout"**, page **Redesign**, the
rows labelled **B** — https://claude.ai/artifact/398RMNqUHLc2TtCTKhoCow.
The A rows are the alternative the owner did not pick; the "First pass"
page is history. The B boards were reviewed and reworked on 2026-09-25
(decisions D9–D19 in §2); these are the boards to match. Every board is
412 dp wide except the last; the height is the board's, not the phone's —
a dashed line marks where a 915 dp screen ends.

| Board | File · height | Shows |
| --- | --- | --- |
| B · New event | `BNew` · 955 | new one-time event, empty, Save disabled. 825 dp of content on the 842 dp sheet: nothing scrolls |
| B · Typing the title | `BTyping` · 915 | the title focused, the keyboard up, Save enabled; everything through Repeat stays visible above a 300 dp keyboard |
| B · New weekly event | `BWeekly` · 1033 | "Leg day", Weekly · Mon, Thu, all day; OCCURRENCES appears under WHEN |
| B · Editing an event | `BEdit` · 1418 | the filled event: description, custom colour, 18:00–19:15 with the end's ✕, presence on, one reminder, High, a linked note, Delete event |
| B · Several one-off dates | `BDates` · 1327 | one-time "Physio" on four dates, timed 10:00–10:45: one row per date with an ✕, then Add date |
| B · Every option switched on | `BAllOn` · 1811 | scope strip, no end time, a two-line Repeat value ("also before", "until"), counting with the live example, absent from a date, Day rail, per-day on, skipped days, five alerts (Add alert hidden), a missing note |
| B · Editing, dark theme | `BEditDark` · 1418 | the editing board in dark |
| B · Writing the description | `BDescribe` · 915 | the description focused at two lines, the markdown bar docked above the keyboard |
| B · Repeat sheet | `BRepeat` · 915 | Weekly · Mon, Thu; the caption under the weekday circles reads "Mon, Thu" |
| B · Repeat sheet, no weekday picked | `BRepeatInvalid` · 915 | the same sheet, same height: Done disabled, the caption is the error; an end date set with its ✕; "Also before the start date" on |
| B · Icon & color sheet | `BLook` · 915 | a custom icon (reset button), a custom colour selected, the whole palette in three runs, tint on |
| B · Priority menu | `BPriority` · 915 | the menu open above the Priority row |
| B · One-time event with an alarm | `BAlarm` · 1094 | "Dentist", 07:30, no end time, an alarm at start, "Remove after it rings" |
| B · Over the limits | `BLimit` · 915 | a 120-character title wrapping to four lines with its counter, a description over the limit with its counter and error line, Save disabled |
| B · Editing, German | `BGerman` · 1418 | the editing board in German, the longest strings |
| B · Text scale 2.0 | `BScale` · 1419 | a new event with a long title at text scale 2.0: labels wrap, values drop under their labels, nothing clips |
| B · Small phone, 360 × 780 | `BSmall` · 360 × 780 | the new event on a 718 dp sheet: everything through Priority is above the fold |

**Scope: UI only.** `lib/widgets/event_editor_sheet.dart`, two new
sub-sheets, ARB strings, tests and docs. No Drift table, model, service,
repository, backup or `.ics` change. For the same user choices, the
`EventEditorResult` the sheet pops must be exactly what it pops today.

---

## 0. How to run this

Hand this to the implementing session (Fable), from `frontend/anta`:

> Implement the event editor redesign described in
> `docs/event-editor-redesign-roadmap.md`.
>
> 1. Read that document end to end before touching code.
> 2. Load the skills it names: `anta-context`, `calendar-events`, `l10n`,
>    `qa-emulator`, `verify`.
> 3. Run Slices 1–4 in order, in this session.
> 4. Run the gate after every slice (§6.0). Never start the next slice with
>    anything red.
> 5. Every behaviour in §4.1 and the checklist in §7 must survive. The data
>    the sheet saves must not change.
> 6. Follow CLAUDE.md: no code comments; every string in all three ARBs plus
>    `flutter gen-l10n`; tests are welcome.
> 7. Do not commit. The owner reviews and commits.
>
> Slice 4 is not optional. It has three parts:
> - a device pass whose screenshots are matched against the canvas boards;
> - an independent review by a fresh subagent that has not seen your
>   reasoning;
> - fixes for everything that review confirms, then every gate re-run.
>
> End with a short report covering:
> - what shipped;
> - each deviation from this doc, and why;
> - every review finding, and how it was resolved;
> - anything you could not verify.

---

## 1. Why

The sheet is the last large surface still in the style from before navigation
round 2. It uses:
- a separately elevated, shadowed card for every row;
- a 40 dp tinted circle on every row;
- a label line above every control, plus two levels of headings;
- one centred segmented control that breaks the left edge;
- grey helper paragraphs under most controls;
- priority as five chips wrapping onto two rows;
- an empty description box that fills its 260 dp maximum instead of its
  intended 120. `_descriptionMinHeight` is never reached, because the
  `CodeEditor` expands to the constraint.

The rest of the app now uses the grouped-row grammar the owner approved in
round 2 (`RowMetrics`, `SurfaceRoles`, `ContentRowShell`). The redesign
applies that grammar to this sheet. It moves nothing out of reach and
changes no saved data.

## 2. Decisions (owner, 2026-09-25)

| # | Decision |
| --- | --- |
| D1 | **Direction B** (the Fable design), amended by D2–D4. Grouped rows; label … value "sentence" rows; the recurrence set in a Repeat sub-sheet; OCCURRENCES as its own group under WHEN. |
| D2 | **The title row's icon is the calendar's own event avatar**: `CircleAvatar` radius 20, background = the effective colour at α 0.16, the icon (24) in the effective colour. This is exactly what `agenda_list_view.dart:1132` and `day_summary_panel.dart:261` draw, so the editor previews the event the way the calendar will show it. |
| D3 | **Several one-off dates stay first-class.** An explicit **Add date** row sits under the date. With two or more dates they show as chips with an ✕ each, so removing one stays one tap, as today. |
| D4 | **A new event opens with the title focused** (keyboard up). Editing never autofocuses. *(Recommended option; the owner delegated it with Q1–Q4 on 2026-09-25 — it stands.)* |
| D5 | **Priority** and **Day rail** become menus. **Icon & color** becomes a sub-sheet. |
| D6 | **Header: leading icon · left-aligned title · Save.** This supersedes the "centred title" wording in the `calendar-events` skill; update it. |
| D7 | **Drag handle: a 22 dp strip drawn by the sheet** (`showDragHandle: false`), replacing Flutter's 48 dp band. Drag-to-dismiss must keep working and keep popping `null`. |
| D8 | **Surfaces:** the sheet ground is `colorScheme.pageGround`, groups are `colorScheme.rowGroup`, and hairlines are `colorScheme.rowDivider`. No `Card`, no elevation, no shadow anywhere in the form. |
| D9 | **Several dates are rows, not chips.** Each date is a 48 dp row (calendar glyph, the date, a 48 dp ✕); tapping a row opens the multi picker, the ✕ removes that date, and Add date follows the rows. A chip's delete icon is a ~24 dp target, a full localized date does not fit a chip, and rows are the grammar the ALERTS group already uses. Supersedes the chips in D3; removal stays one tap. |
| D10 | **Label · value pairs wrap instead of ellipsizing.** The pair is a `Wrap` with `spaceBetween`: one line while both fit, otherwise the value drops under the label, left-aligned, up to two lines, then ellipsis. A label never ellipsizes (it may wrap). German, Romanian and text scale 2.0 keep every value readable, and a row's height differs only per locale or scale — never at runtime, except the Repeat row, which only the Repeat sheet changes and which sits below nothing that moves. |
| D11 | **The description cell starts at one line, 48 dp, not 90.** Height = 26 + lines × 22, clamped 48–246 (ten lines), then it scrolls inside. Empty it reads `Add description` with the expand button as its trailing element. That is what makes the new-event form 825 dp on an 842 dp sheet — honestly one screen — and it is the shape every calendar's notes row has. |
| D12 | **A row's glyph names the field, never the value.** Only the title avatar (D2) previews the event. Priority's glyph is `flag_outlined`; `EventPriorities.iconFor` stays for the menu items and the agenda. As a row glyph, `drag_handle` ("=") for Normal read as a drag affordance. |
| D13 | **Alert kinds reuse the alert editor's words**: `eventAlertModeNotify` ("Reminder") and `eventAlertModeRing` ("Alarm"). No "Notification" string: the row opens a sheet that calls the same thing Reminder. |
| D14 | **Sub-sheets never move under the finger.** The Repeat sheet's height is the same for every kind (its dependent area is sized by an invisible weekly template), and the weekday row always carries a caption line — the picked days in words, or the error — so deselecting the last weekday changes text, not geometry. The Icon & color sheet shows the whole palette (no collapse) and always shows the Tint row, disabled without a colour, so nothing inside it appears above or grows under a control. |
| D15 | **Placeholders, hints and counters are `onSurfaceVariant`**, not `outline`: `#79747E` on `#FEF7FF` is 4.3:1, under AA for text. Chevrons and icon-button glyphs stay `outline` (graphics, 3:1 and over). |
| D16 | **The title wraps.** `maxLines: null`, `keyboardType: text`, newlines denied, Done on the keyboard: a long title is read, not scrolled. The counter sits under the field from 100 characters (`buildCounter`), below the control that grows it. |
| D17 | **The Repeat value** is `Does not repeat` for both one-time shapes — with several dates the date rows already say how many — and, when recurring, `RecurrenceFormatter.format(…, retroactive)` plus ` · until {date}` when an end date is set, on up to two lines. |
| D18 | **Save is a stock `FilledButton`** (40 dp, M3 defaults, the theme's disabled colours); sub-sheets confirm with a `TextButton` Done. No custom 36 dp button. |
| D19 | **Linked note states.** While the title loads the value is empty (never a flash of "Untitled Note"); a missing note reads `Not found` in `error` with the full `eventLinkedNoteMissing` sentence as its semantics label; the ✕-style trailing button is `link_off_rounded` whenever a note is linked. |
| D20 | **Leaving a dirty form asks first.** ✕, back, the system back gesture, the barrier tap and drag-to-dismiss all run one guard (§3.8): a clean form leaves exactly as today; a dirty one gets an `AlertDialog` — `unsavedChanges` · `keepEditing` / `discardChanges` — between the gesture and the pop. ANTA's bar is "no lost text", and a sheet that can silently drop a description typed one-handed on a gym floor fails it. The sub-sheets stay unguarded: a Repeat or Icon & color draft costs one tap to redo. Because the route's own drag pops without consulting `PopScope`, the sheet owns its handle drag (§3.8). |

**Delegated (2026-09-25).** The review's four open questions were handed to
the lead ("take the decisions from me"), who took the recommended option on
each: Q1 the `Add description` placeholder (D11), Q2 the discard guard
(D20), Q3 the constant-height Repeat sheet (D14), Q4 Add date directly under
the date rows (§3.3). D4 stands on the same delegation. Q1, Q3 and Q4 were
already drawn; only Q2 changes the spec and §4.1.

## 3. The spec

### 3.1 Geometry and tokens

- **Sheet.** Height 0.92 of the available height, top radius 28, ground
  `pageGround` (light `#F3EDF7`, dark `#141218`).
- **Handle strip.** 22 dp; handle 32 × 4, radius 2, `onSurfaceVariant` at
  40 %, centred.
- **Header.** 48 dp.
  - Leading `IconButton` 48 × 48 at x 4: `close_rounded`, or
    `arrow_back_rounded` when `showBack`. 24 px, `onSurfaceVariant`,
    tooltip `cancel` / `back`.
  - Title (`addEvent` / `editEvent`): 17 / 500 `onSurface`, starting at
    x 56, one line, ellipsis.
  - Save: a stock `FilledButton` (D18) — 40 high, padding 0 24, radius 20,
    14 / 500 — right margin 12. Disabled uses the theme's disabled colours.
  - A 1 px `rowDivider` hairline appears under the header once the body has
    scrolled at least 1 dp. Drive it with a `ValueNotifier` from the scroll
    controller, never `setState`.
- **Body.** `SingleChildScrollView`, padding `8, 16, 24 + clearance, 16`;
  the bottom pad is 0 while the description is focused, because the docked
  bar owns that strip. The clearance rules are unchanged (§4.1).
- **Group.** `rowGroup` fill, radius `RowMetrics.groupRadius` (14),
  anti-alias clip, no shadow, `RowMetrics.groupGap` (18) below it.
- **Hairline between rows.** 1 px `rowDivider`, starting at:
  - 52 on glyph rows and sub-rows;
  - 16 on glyph-less rows (the description cell, the radio rows and the
    Icon row of the sub-sheets);
  - 70 under the title row.
  Reuse `ContentRowShell` / `RowGroupPosition` (`lib/widgets/content_rows.dart:30`)
  if it fits, or build one small shared primitive in its image. Never copy
  its code a second time.
- **Section label.** Round-2 metrics: 11 / 500, letter-spacing 0.88,
  uppercase, `onSurfaceVariant`, padding 0 4 6 (a 20 dp block). Labels:
  **WHEN**, **OCCURRENCES**, **ALERTS**, **DETAILS**. The capture group and
  the actions group have no label; the sub-sheets have none.
- **Text roles.**

  | Role | Style |
  | --- | --- |
  | Row label | 15 / 400 `onSurface` |
  | Row value | 15 / 400 `onSurfaceVariant`, tabular figures |
  | Action row | 15 / 500 `primary`; destructive `error` |
  | Placeholder (title, description) | 20 / 400 and 15 / 400 `onSurfaceVariant` (D15) |
  | Caption (count example, weekday caption, two-line second line) | 13 / 400 `onSurfaceVariant`; `error` when it is an error |
  | Counter | 12 / 400 `onSurfaceVariant`, tabular; `error` at the limit |
  | Glyph | 22 `primary` |
  | Chevron | `chevron_right` 18 `outline` |
  | Trailing icon button | 48 × 48, icon 20 `outline` |

- **The label · value pair (D10).** `Wrap(alignment: spaceBetween,
  crossAxisAlignment: center, spacing: 14, runSpacing: 2)` holding the label
  `Text` (soft-wrapping, no `maxLines`) and the value `Text(maxLines: 2,
  overflow: ellipsis)`. One line while both fit; the value drops to its own
  line otherwise. The pair has 6 dp vertical padding inside the row's 48 dp
  minimum, so a row only grows when a line wraps.

### 3.2 Row types

| Type | Metrics |
| --- | --- |
| **Title row** | Min 56, padding 8 16, `CrossAxisAlignment.start`. Event avatar (D2), gap 14, then a `TextField` at 20 / 500 `onSurface`, `height: 1.3`, `InputDecoration.collapsed`, 7 dp above it so the first line centres on the avatar. Hint `eventTitle` at 20 / 400 `onSurfaceVariant`. `maxLines: null`, `keyboardType: TextInputType.text`, `FilteringTextInputFormatter.deny('\n')`, `textInputAction: done` (D16). `maxLength` 120; the counter (`buildCounter`) is hidden below 100 characters, then 12 / 400 `onSurfaceVariant` right-aligned under the field, `error` at 120. `autofocus` only when new (D4). Hairline from 70. |
| **Picker row** | Reads `label … value ›`. Min 48; padding 0 12 0 16; glyph 22 `primary`; gap 14; the pair (D10); then `chevron_right` 18 `outline`. The whole row is one `InkWell`. |
| **Switch row** | As a picker row, with an M3 `Switch` at the trailing edge. One semantics node (`MergeSemantics`), the whole row toggles. A disabled switch row is drawn at 38 % and does not toggle. |
| **Two-line switch row** | 62 high, padding 9 16: title 15 / 500, second line 13 / 400 `onSurfaceVariant`, the switch vertically centred. Repeat sheet only. |
| **Sub-row** | A row that another row reveals. Min 48, padding 0 12 0 52, no glyph, hairline from 52. Holds a picker (`Starts 18:00 ›`) or a chip pair. |
| **Two-target row** | A picker row whose trailing element is a 48 × 48 `IconButton` (icon 20 `outline`) instead of the chevron; the row's right padding is 0, so the icon centres 24 dp from the edge. Two sibling targets — the row's `InkWell` and the button — never one inside the other. Used by the date rows (✕), alert rows (✕), Ends with an end time (✕), Absent from with a date (✕), a linked note (`link_off_rounded`), the Icon row of the Icon & color sheet (`refresh_rounded`) and Ends in the Repeat sheet with a date (✕). |
| **Action row** | 48 high. Glyph 22 + text 15 / 500, both `primary`. Destructive uses `error`. Disabled is 38 % opacity with no ink. |
| **Chip** | 32 high, radius 8, 1 px `outlineVariant`, padding 0 14, 14 / 500 `onSurfaceVariant`. Selected: `secondaryContainer` fill, transparent border, `onSurface` text, **no check icon**. Tap target padded to 48. A chip sub-row is padded 8 12 12 52, gap 8, and wraps. |
| **Description cell** | See §3.5. |

### 3.3 Screens, top to bottom

Copy is given in English; take every string from an ARB key (§3.7).

**Capture group** (no label, every state):
1. **Title row.**
2. **Category** (glyph `label_outlined`). Value: the category name
   (`CalendarCategories.labelOf`). Tap opens `CategoryPickerSheet.pickSingle`
   through the existing `_pickCategory`, so the birthday pre-fill still runs.
3. **Icon & color** (glyph `palette_outlined`). Value: a 10 px dot in the
   effective colour, gap 8, then `eventLookDefault` or `eventLookCustom`.
   Custom means an icon override or a colour override is set. Tap opens the
   Icon & color sheet (§3.6).
4. **Description cell** (hairline from 16).

**WHEN** group:
1. **Date rows**, glyph `calendar_today_outlined`:
   - One time with one date: label `eventDateLabel` ("Date"), value
     `yMMMEd` (for example "Fri, Sep 25, 2026"). Tap calls **`_pickDate`**
     (single picker).
   - One time with several dates (D9): one two-target row per date, sorted,
     label `yMMMEd` of the date, no value, ✕ calling `_removeOneTimeDate`
     (tooltip `eventRemoveDate`). Tapping a row calls `_pickOneTimeDates`.
   - Recurring: label `eventDate` ("Start date"), value `yMMMEd` of `_date`.
     Tap calls `_pickDate`, which keeps its weekday re-anchoring and its
     end-date guard.
2. **Add date** (one time only): an action row, glyph `add_rounded`, calling
   `_pickOneTimeDates`. It follows the date row(s), as Add alert follows the
   alerts.
3. **All day**: switch row, glyph `schedule_outlined`, `_setAllDay`.
4. **Timed only**, as sub-rows:
   - `Starts … 18:00 ›` (`eventStarts`) calls `_pickStartTime`.
   - With no end: `Ends … No end time ›` (`eventEnds`, `eventEndTimeNone`)
     calls `_pickEndTime`.
   - With an end: a two-target row, value `19:15 · 1 h 15 min` (the end
     time plus `EventTimeFormatter.formatDuration`), the ✕ calling
     `_clearEndTime` (tooltip `eventEndTimeRemove`); the row still calls
     `_pickEndTime`.
   - When the end crosses midnight the label becomes `eventCrossesMidnight`
     ("Ends next day").
   - Both values keep `ValueChangeHighlight`.
5. **Repeat**, glyph `repeat_rounded`, label `eventRepeat`, opens the Repeat
   sheet (§3.6). Value (D17):
   - one time, one date or several: `recurrenceDoesNotRepeat`;
   - recurring: `RecurrenceFormatter.format(_buildRule(), l10n, localeName,
     retroactive: _retroactive)`, wrapped in `recurrenceUntilSuffix` with
     `yMMMd` of `_endDate` when it is set. Up to two lines.

**OCCURRENCES** group, only while `_ruleHasManyOccurrences`. Gates as today:
1. **Count occurrences** switch (glyph `numbers_rounded`). Present only when
   recurring and `_kindSupportsInterval(_kind)`. When on, a chip sub-row
   holds `Count from 1` / `Count from 0` with the live `_countStyleExample`
   under them as a caption (13 / 400 `onSurfaceVariant`, 8 dp below the
   chips). Keep the `_countStyleTouched` logic.
2. **Track presence** switch (glyph `how_to_reg_outlined`). When on, a chip
   sub-row: `Assume present` / `Assume absent`, through
   `_selectAssumeAbsent`. When absent and editing, a sub-row `Absent from …
   Start of event ›` calls `_pickAssumeAbsentFrom`; with a date set it is a
   two-target row `Absent from … {yMMMEd} ✕`, the ✕ resetting the date and
   setting `_assumeAbsentFromTouched` exactly as today (tooltip
   `resetToDefault`).
3. **Day rail** picker (glyph `vertical_split_outlined` — the rail is a bar
   of marks on the day cell's edge), only while `_dayRailEnabled`, keeping
   today's gate. Value `Auto` / `Always` / `Never`. Tap opens a menu.
4. **Separate description per day** switch (glyph `event_note_outlined`).
   - Switching it off calls `_syncScopeToRule`, as today.
   - Switching it on while editing a specific day reveals the scope strip in
     the capture group, which is **above**. After the frame, call
     `Scrollable.ensureVisible` on the description (250 ms), so the effect is
     seen rather than landing off screen.
5. **Skipped days** picker (glyph `event_busy_outlined`), editing only,
   calling `_pickSkippedDays`. Value `eventSkippedDaysCount(n)` or
   `eventNoSkippedDays`.

**ALERTS** group:
- One two-target row per alert:
  - glyph `notifications_outlined`, or `alarm_outlined` for an alarm;
  - label `alert.describe(l10n, _alertPreviewEvent)`;
  - value `eventAlertModeNotify` ("Reminder") or `eventAlertModeRing`
    ("Alarm") (D13);
  - the ✕ calls `_removeAlert` (tooltip `eventAlertRemove`); tapping the row
    calls `_editAlert`.
- **Add alert** action row (`add_rounded`). It is hidden at
  `kMaxAlertsPerEvent`, and it keeps `AutomationId(SemanticsIds.eventAlertAdd)`.
- **Remove after it rings** switch row (glyph `auto_delete_outlined`), only
  when `_isOneTimeEvent && _hasAlarmAlert`. It keeps
  `AutomationId(SemanticsIds.eventAlertRemoveAfter)`.

**DETAILS** group:
- **Priority**, glyph `flag_outlined` (D12), value `EventPriorities.labelOf`.
  Tap opens the Priority menu (§3.6).
- **Linked note**, glyph `sticky_note_2_outlined` (D19):
  - none: value `eventLinkedNoteNone`, chevron, `_pickNote`;
  - loading: a two-target row with an empty value and `link_off_rounded`;
  - linked: the note title (or `untitledNote`), `link_off_rounded` calling
    `_clearNote` (tooltip `eventRemoveNoteLink`); tapping the row calls
    `_pickNote`;
  - missing: glyph `warning_amber_rounded` and value
    `eventLinkedNoteNotFound`, both in `error`; the row's semantics label is
    `eventLinkedNoteMissing`; `link_off_rounded` still clears it.

**Actions** group (no label):
- **Save as template**: action row (`bookmark_add_outlined`),
  `_onSaveAsTemplate`, disabled while the title is empty.
- **Delete event**: action row (`delete_outline_rounded`, `error`),
  `_onDelete`, editing only. The confirmation dialog is unchanged.

### 3.4 Row lists per board

Heights are the measured sheet content (strip, header and body padding
included) on a 412 × 915 phone, against the 842 dp sheet.

- **New event (825):** capture (title, Category, Icon & color, an empty
  description) · WHEN (Date, Add date, All day on, Repeat "Does not repeat")
  · ALERTS (Add alert — the out-of-the-box default alert is none; a seeded
  default adds one row) · DETAILS (Priority Normal, Linked note None) ·
  actions (Save as template, disabled). Nothing scrolls.
- **Weekly (960):** WHEN is Start date, All day, Repeat "Weekly · Mon, Thu".
  OCCURRENCES appears below WHEN: Count occurrences, Track presence,
  Separate description per day.
- **Editing (1345):** a back arrow when `showBack`. All day off with Starts
  and Ends (the end's ✕). OCCURRENCES gains Skipped days, ALERTS has one
  reminder, DETAILS a linked note, and the actions group gains Delete event.
- **Several one-off dates (1254):** four date rows with an ✕ each, then Add
  date, then All day off with Starts and Ends, Repeat "Does not repeat".
  OCCURRENCES holds Track presence and Separate description per day. There
  is no Count row, because `_kindSupportsInterval` is false for specific
  dates.
- **Every option on (1738):** the scope strip above the description; Ends
  "No end time"; the Repeat value on two lines; every OCCURRENCES row with
  its sub-rows; five alerts and no Add alert; a missing note.
- **Alarm (1021):** a timed one-off with an alarm at start, so Remove after
  it rings shows under Add alert.
- **Small phone (360 × 780):** the sheet is 718 dp; everything through
  Priority is above the fold, the actions group scrolls. Save is in the
  header, so nothing a capture needs is out of reach.
- **Text scale 2.0:** rows grow, labels wrap, values drop under their labels
  (D10), icons and switches keep their size. No label clips.

### 3.5 Description cell

- **Layout.** Padding `LTRB(16, 13, 48, 13)`, so one line is exactly 48. The
  re_editor surface is 15 px with line height 22; a heading line renders at
  17 / 500.
- **Height.** `clamp(26 + lines × 22, 48, 246)` — one to ten lines — past
  that it scrolls internally (D11). This is the fix for the stuck-at-maximum
  bug in §1.
  - Drive the height from the controller through `_descriptionRevision`,
    the existing post-frame relay, never a `ListenableBuilder` directly on
    the re_editor controller (§4.1).
  - Use a `ValueNotifier<double>` so a keystroke rebuilds the box, not the
    form.
  - Soft-wrapped lines can be measured from the editor's scroll metrics. If
    you take the line count instead, say so in the report.
- **Placeholder.** When empty, an overlay shows `eventDescriptionAdd`
  ("Add description"), 15 / 400 `onSurfaceVariant`, one line, ellipsis. It
  is not a hint field inside the editor.
- **Expand button.** An overlay `IconButton` 48 × 48 at the top right
  (`open_in_full_rounded` 20 `outline`, tooltip `eventDescriptionExpand`)
  calls `_openDescriptionSheet`. While live rendering is off, the preview
  toggle (`visibility_outlined` / `edit_outlined`) sits to its left as a
  second overlay button and the cell's right padding becomes 96.
- **Counter.** `eventDescriptionCount` ("2012 / 2000"), 12 / 400
  `onSurfaceVariant`, right-aligned under the text, from 90 % of the limit.
  It turns `error` when over. Over the limit, the `eventDescriptionTooLong`
  line (13, `error`, padding 0 16 12) sits inside the group under the cell,
  and Save is disabled.
- **Scope strip.** When `_scopeControlVisible`, a 44 dp strip above the
  editor (padding 0 4 0 16) holds:
  - chips `eventDescriptionScopeAllDays` / `eventDescriptionScopeThisDay`,
    through `_setScope`;
  - on the right, when today's reset condition holds, a `TextButton`
    `eventDescriptionResetDayShort` ("Reset day", 13 / 500 `primary`, 44
    tall) whose semantics label is `eventDescriptionResetDay`, calling
    `_resetDayToTemplate`.
- **Markdown bar.** Docks at the sheet bottom on focus, exactly as today
  (`_buildDescriptionBar` plus the `AnimatedSize`).

### 3.6 Sub-surfaces

Both sheets share the chrome of §3.1 — the 22 dp handle strip, a 48 dp
header, the `pageGround` ground, the 16 dp body inset with 8 above and 24
below — and both hold a **draft**: Done returns it, ✕ and drag-dismiss
return `null` and change nothing.

**Repeat sheet** (new file, for example `lib/widgets/event_repeat_sheet.dart`).
- **Header.** `close_rounded` (cancel) · `eventRepeat` · a `TextButton`
  `eventDescriptionDone` ("Done"), 48 tall, 14 / 500 `primary`, padding
  0 12, right margin 8. Done is disabled (38 %) while the draft is weekly
  with no weekday.
- **Radio group.** Rows 48, padding 0 14 0 16, text 15 / 400; the selected
  row 15 / 500 with a trailing `check_rounded` 20 `primary`; hairlines from
  16. Options in this order: `recurrenceDoesNotRepeat`, `recurrenceDaily`,
  `recurrenceWeekly`, `recurrenceMonthly`, `recurrenceYearly`,
  `recurrenceWorkdays`, `recurrenceWeekends`, `recurrenceHolidaysOnly`.
- **Dependent group** 18 below it, only for recurring kinds:
  - **Repeat every** stepper (label `recurrenceIntervalLabel`), for daily,
    weekly, monthly and yearly: `remove_rounded` and `add_rounded` as 48 dp
    `IconButton`s, 20 `primary`, 38 % at 1 and at 99; the value `1 week`
    (`recurrenceUnit*`) 15 / 500, tabular, centred in a minimum width of 96;
    row padding 0 0 0 16. Tooltips are `recurrenceIntervalDecrement` /
    `recurrenceIntervalIncrement`.
  - **Weekday row**, weekly only, no label. Seven `Expanded` cells over the
    row (padding 0 8), each a ≥ 48 × 64 tap target with a 40 dp circle:
    - letters from `DateFormat.EEEEE(locale)`, Monday first;
    - off: 1 px `outlineVariant` border, `onSurfaceVariant` text;
    - on: `primary` fill, `onPrimary` text;
    - semantics carry the full weekday name and the selected state.
    Under the circles, always, a caption (13 / 400, padding 0 16 12): the
    picked days in words through `RecurrenceFormatter.formatWeekdays` in
    `onSurfaceVariant`, or `weeklyDaysHint` in `error` when none is picked
    (D14). It disambiguates T/T and S/S, and it keeps the row's height.
  - **Ends** (`recurrenceEnds`): a picker row with text at 16. Value
    `never` ("Never") with a chevron; with a date, a two-target row `yMMMd`
    plus ✕ (tooltip `recurrenceEndDateRemove`). The row opens the date
    picker with the start date as its lower bound, the existing
    `_pickEndDate` rules.
  - **Also before the start date** (`recurrenceBeforeStart`): a two-line
    switch row, 62 dp, text at 16. The second line is
    `recurrenceBeforeStartHint(date)` ("Shows on matching days before
    {yMMMd of the start}"); for yearly it is
    `recurrenceBeforeStartYearlyHint` ("Also in earlier years").
- **Height (D14).** Constant for every kind: the dependent area is a
  `Stack` whose size comes from an invisible weekly template (`Opacity(0)`,
  `IgnorePointer`, `ExcludeSemantics`) with the real dependent group laid
  over it, top-aligned. So the sheet is as tall as its weekly state — 762 dp
  at text scale 1 (391 for the radio group, 255 for the dependent group) —
  and never taller than 0.92; past that the body scrolls.
  Picking a kind, toggling a weekday or clearing the end date moves nothing.
- **What it returns.** The sheet edits a **plain draft**: recurring or not,
  kind, interval, weekdays, end date, retroactive. It never builds a
  `RecurrenceRule`. The editor applies the draft to its fields.
  `_buildRule()` stays the only encoder and `_initRecurrenceFrom` the only
  decoder.
- **Applying the draft.** Everything today's handlers did on a kind or mode
  change must still happen:
  - `_countStyle` re-resolves while `!_countStyleTouched`;
  - `_syncScopeToRule()` runs after a mode change;
  - one-off extra dates are kept across mode flips.

**Icon & color sheet** (new file).
- **Header.** `close_rounded` · `eventAppearance` · Done, as above.
- **One group:**
  - An **Icon** row, 56 dp: the event avatar (D2) previewing the draft, gap
    14, label `iconLabel`. With an icon override: value `eventLookCustom`
    and a trailing 48 dp `refresh_rounded` (tooltip `resetToDefault`)
    clearing it — a two-target row. Otherwise value `eventLookDefault` and
    a chevron. Tapping the row calls `IconPickerSheet.show`, with today's
    `tint` and `initialKey`.
  - A hairline from 16, then the existing **`ColorSwatchPicker`** with
    `spacing: 2` (seven 48 dp targets per run across the 348 dp) and a new
    `collapsible: false`, so the whole palette shows — 21 dots in three runs
    with the 18 built-ins: the category default first (`defaultOption`,
    today's call at `event_editor_sheet.dart:2717`), then the palette, then
    the add and manage dots. Padding 8 16 12.
  - A hairline from 16, then **Tint icon with color** (`eventTintIcon`), a
    switch row with text at 16, **always present**: disabled at 38 % while
    no colour is set, showing the stored `_tintIcon` (D14).
- **Height.** Content height — 376 dp at text scale 1 with the 18 built-in
  colours. Nothing in it grows or appears above a control; the one growth
  is a run added after a custom colour is created through its own dialog.
- **What it returns.** Done returns `(iconKey, colorValue, tintIcon)`.
  Cancel or drag-dismiss returns `null` and changes nothing. On save, keep
  `copyWith(clearIconKey: _iconKey == null)`.

**Menus** (Priority, Day rail): `MenuAnchor` on the app's `popupMenuTheme`
(`menuSurface`, radius 12, padding 6 0, the theme's shadow). Rows are 44
with padding 0 16, an icon 20 `onSurfaceVariant`, the label 15, and a
trailing `check_rounded` 20 `primary` on the current item. The menu's right
edge aligns with the group's right edge; it opens under the row when there
is room and above it otherwise.
- **Priority:** width 220; five items, `EventPriorities.iconFor` +
  `labelOf`, highest first.
- **Day rail:** width 180; `Auto` / `Always` / `Never`, no icons.

### 3.7 Copy and l10n

Load the `l10n` skill. Add or change keys in `app_en.arb`, `app_de.arb` and
`app_ro.arb` together, run `flutter gen-l10n`, then check `untranslated.txt`.

- **Reuse:** `eventTitle`, `eventAppearance`, `eventDescriptionAdd` (the
  placeholder), `eventDescriptionExpand`, `eventDescriptionPreviewOn` /
  `eventDescriptionPreviewOff`, `eventAddDate`, `eventRemoveDate`,
  `eventAllDay`, `eventStartTime` / `eventEndTime` (time-pad titles),
  `eventEndTimeNone`, `eventCrossesMidnight`, `eventSectionWhen`,
  `recurrenceScopeLabel` ("Occurrences", as the group label),
  `eventCountOccurrences`, `eventCountStyleNumbered/Elapsed`,
  `eventTrackPresence`, `eventAssumePresent/Absent`, `eventAssumeAbsentFrom`,
  `eventAssumeAbsentFromStart`, `eventShowInDayRail` and its three values,
  `eventPerOccurrenceDescriptions`, `eventSkippedDays(Count)`,
  `eventNoSkippedDays`, `eventAlerts`, `eventAlertAdd`, `eventAlertRemove`,
  `eventAlertModeNotify` / `eventAlertModeRing` (the alert kind values),
  `eventAlertRemoveAfter`, `eventSectionDetails`, `eventPriority` and its
  levels, `eventLinkedNote`, `eventLinkedNoteMissing` (semantics only),
  `eventRemoveNoteLink`, `untitledNote`, `saveAsTemplate`, `deleteEvent`,
  the scope strings, `eventDescriptionCount/TooLong/ResetDay`,
  `eventDescriptionDone` ("Done" on both sub-sheets), `weeklyDaysHint`,
  `recurrenceIntervalLabel` ("Repeat every") and its increment/decrement
  tooltips, the `recurrence*` kind and unit strings, `iconLabel`,
  `eventTintIcon`, `eventColorCategoryDefault`, `addColor`, `manageColors`,
  `resetToDefault`, `addEvent`, `editEvent`, `save`, `cancel`, `back`, and
  `eventDate` retitled in English to "Start date" (German `Startdatum` and
  Romanian `Data de început` already say that).
- **New** (check first; reuse any that already exist):

  | Key | en | de | ro |
  | --- | --- | --- | --- |
  | `eventCategory` | Category | Kategorie | Categorie |
  | `eventDateLabel` | Date | Datum | Dată |
  | `eventStarts` | Starts | Beginn | Început |
  | `eventEnds` | Ends | Ende | Sfârșit |
  | `eventEndTimeRemove` | Remove end time | Endzeit entfernen | Elimină ora de sfârșit |
  | `eventRepeat` | Repeat | Wiederholung | Repetare |
  | `recurrenceDoesNotRepeat` | Does not repeat | Wiederholt sich nicht | Nu se repetă |
  | `recurrenceEnds` | Ends | Endet | Se termină |
  | `never` | Never | Nie | Niciodată |
  | `recurrenceEndDateRemove` | Remove end date | Enddatum entfernen | Elimină data de final |
  | `recurrenceBeforeStart` | Also before the start date | Auch vor dem Startdatum | Și înainte de data de început |
  | `recurrenceBeforeStartHint` | Shows on matching days before {date} | Erscheint an passenden Tagen vor dem {date} | Apare în zilele potrivite dinainte de {date} |
  | `recurrenceBeforeStartYearlyHint` | Also in earlier years | Auch in früheren Jahren | Și în anii anteriori |
  | `recurrenceUntilSuffix` | {rule} · until {date} | {rule} · bis {date} | {rule} · până la {date} |
  | `eventLookDefault` | Default | Standard | Implicit |
  | `eventLookCustom` | Custom | Angepasst | Personalizat |
  | `eventLinkedNoteNone` | None | Keine | Niciuna |
  | `eventLinkedNoteNotFound` | Not found | Nicht gefunden | Nu a fost găsită |
  | `eventDescriptionResetDayShort` | Reset day | Tag zurücksetzen | Resetează ziua |

  Labels are never ellipsized, so a long one wraps and the row grows (D10):
  Romanian "Descriere separată pentru fiecare zi" takes two lines beside
  its switch, and that is fine.
- **Remove**, only after grepping each one repo-wide, keys the sheet no
  longer uses. Candidates:
  - headings and labels: `eventSectionWhat`, `repeatMode`, `repeatOnce`,
    `repeatRecurring`, `eventDatesLabel`, `frequency`, `eventUntilLabel`,
    `eventUntilNone`;
  - hints: `eventDescriptionHint`, `eventDatesHint`, `eventUntilHint`,
    `eventAllDayHint`, `eventEndTimeHint`, `eventAlertHint`,
    `eventCountOccurrencesHint`, `eventTrackPresenceDesc`,
    `eventPerOccurrenceDescriptionsDesc`, `eventPriorityHint`,
    `eventLinkNoteHint`, `eventTintIconHint`, `eventShowInDayRailHint`;
  - others: `recurrenceScopeFromStart`, `recurrenceScopeHint`,
    `pickCategory`, `eventColor`, `iconDefault`, `iconCustom`, `selectNote`.

  **Shared keys stay.** The scope hints still feed `EventDescriptionSheet`'s
  `scopeCaption`, `recurrenceScopeAlways` / `recurrenceScopeEveryYear` still
  serve the agenda's formatter, and several alert and presence strings serve
  other surfaces.
- **For D20, reuse** `unsavedChanges` ("Unsaved changes"), `discardChanges`
  ("Discard changes") and `keepEditing` ("Keep editing"): all three exist in
  en, de and ro and no Dart code uses them today. No new string.

### 3.8 Leaving with unsaved changes (D20)

- **Dirty** means the form's fingerprint differs from the one captured at the
  end of `initState`. The fingerprint is one `String` (or record) over every
  field the result carries: the raw title text; the template and day
  description texts (`_templateText`, `_dayText`) and `_dayResetRequested`;
  `_categoryId`, `_iconKey`, `_colorValue`, `_tintIcon`; `_date`,
  `_additionalDates`, `_mode`, `_kind`, `_interval`, `_weekdays`, `_endDate`,
  `_retroactive`; `_isAllDay`, `_startMinute`, `_durationMinutes`;
  `_alertsTouched ? <the alerts> : ''` — so the default alert
  `_seedDefaultAlert` plants on a new event never counts, however late the
  settings load; `_removeAfterAlert`; `_countOccurrences`, `_countStyle`,
  `_tracksPresence`, `_assumeAbsent`, `_assumeAbsentFrom`, `_showInDayRail`,
  `_perOccurrenceDescriptions`, `_skippedDays`; `_noteId`, `_priority`. Not
  in it: `_descriptionPreview`, `_descriptionFocused`, `_scope`, and every
  settings-loaded value (`_liveMarkdownRendering`, `_descriptionLimit`,
  `_dayRailEnabled`, the alert defaults, the palette). It is computed **only
  when leaving** — no listener, no keystroke work.
- **The guard** is one `Future<bool> _confirmLeave()`: `true` at once when
  clean; otherwise it shows an `AlertDialog` in the exact shape of
  `_onDelete`'s confirmation — title `unsavedChanges`, no body, a
  `TextButton` `keepEditing` (pops `false`) and a `FilledButton.tonal`
  `discardChanges` (pops `true`) — and returns what the dialog popped
  (`false` on a barrier tap). `_leave` becomes: await the guard, `!mounted`
  check, then pop `EventEditorBack` when `showBack`, else `null`. Save never
  goes through the guard.
- **Every way out goes through `_leave`.** The ✕ / back button calls it. The
  `PopScope` now has `canPop: false` in every case (not only while
  `showBack`) and its `onPopInvokedWithResult` calls `_leave` when
  `didPop` is false — that covers the system back gesture and the barrier
  tap, both of which reach the route through `Navigator.maybePop`.
- **Drag-to-dismiss.** The route's drag does not: the modal sheet's
  `onClosing` calls `Navigator.pop` directly (Flutter 3.47.4,
  `material/bottom_sheet.dart:769–771`), so `showModalBottomSheet` gets
  `enableDrag: false` and the sheet owns the gesture on the surface that was
  ever draggable — the handle strip and the header row; the body is a scroll
  view and already won every vertical drag inside it, so nothing is lost.
  Mechanics: a `GestureDetector` with the vertical-drag callbacks on that
  70 dp band; during the drag the sheet's content follows the finger through
  a `Transform.translate` (offset clamped ≥ 0, driven by one
  `ValueNotifier<double>`, never `setState`); on release, a downward fling
  (velocity above 700 px/s) or an offset past a quarter of the sheet height
  counts as a dismiss: a clean form pops as the ✕ would, a dirty one snaps
  back (150 ms) and then shows the dialog, and Discard pops; anything else
  snaps back. `isDismissible` stays `true`. **Fallback, decided on the
  device pass:** if the custom drag does not feel as smooth as the native
  one, keep `enableDrag: false`, drop the handle glyph (keep the 22 dp strip
  as breathing room, since a handle on a sheet that cannot be dragged is a
  lie) and record the deviation from D7 in the report; the system back
  gesture stays the one-handed cancel.
- **Not guarded:** the Repeat and Icon & color sheets, the description
  sheet, the pickers. Each holds a draft that is one tap to redo.

## 4. Behaviour

### 4.1 Must not change

Every item below comes from the current code or the `calendar-events`
skill; each one is a past bug.

- **Data.** For the same choices, the popped `EventEditorResult` is
  identical, occurrence description reporting and skipped days included.
- **Rule building.** `_buildRule()` wraps weekdays in `Set.unmodifiable`.
  `_initRecurrenceFrom` is the sealed rehydration.
  - The interval is clamped 1–99, and exists only for daily, weekly,
    monthly and yearly.
  - `retroactive` is written as `recurring && _retroactive`.
  - `_setOneTimeDates` stays the one funnel that re-derives the anchor.
    `pickMulti` never returns empty.
- **`_canSave`**:
  - the title is non-empty;
  - a weekly rule has weekdays (keep this check even though the Repeat sheet
    cannot return an invalid rule);
  - both description scopes are within limits, with the grandfather rule.
- **Pickers.**
  - `_pickDate` keeps its weekday re-anchoring, drops the new date from
    `_additionalDates`, and drops an end date that falls before the start.
  - Birthday pre-fill on a still-one-time event: Yearly, counting on,
    count style from `_defaultCountStyleFor`.
  - Every await is followed by `!mounted` early returns.
  - Times are only ever entered through `TimePadSheet.pick`; dates only
    through `CalendarDatePickerSheet` (`CalendarBounds`, `dayLoad`, and
    `appearance` passed in from the page); categories through
    `CategoryPickerSheet.pickSingle`.
- **Description.**
  - It is a re_editor surface through `ModernEditorWrapper`, with a
    sheet-owned `MarkdownEditorSpanBuilder`. Money stays disabled **by
    omission**: never call `configureMoney`.
  - A late setting applies through `configureColors` + `forceRepaint()`,
    never by remounting the editor.
  - Scope swaps use one controller, `loadText` and `clearHistory()`.
  - **Never put a `ListenableBuilder` directly on the re_editor
    controller.** Relay through `_descriptionRevision`.
  - Counter-bound shortcuts stay filtered out of the bar. Keep
    `MarkdownShortcutInserter`.
  - **No keystroke-wide `setState`** anywhere in the sheet.
- **Clearance.** The keyboard inset pads the scroll view, or the bar while
  it is up, and never the whole body. The header stays the first child.
  `test/widgets/sheet_bottom_clearance_test.dart` must gain the **Repeat
  sheet** and the **Icon & color sheet**.
- **Back and dismiss.**
  - `PopScope` still maps system back to `EventEditorBack` while
    `showBack` — through the guard of §3.8 now.
  - Back and close still land where they did (`EventEditorBack` / `null`)
    and still discard the same things; the only new behaviour is the
    question in between when the form is dirty (D20). A clean form never
    sees the dialog, so every existing back/close test stays valid as
    written.
  - Drag-dismiss still exists and still pops `null` (or `EventEditorBack`
    while `showBack`), through the guard. It is the sheet's own gesture now
    (§3.8), because the route's bypasses `PopScope`.
  - `calendar_page.dart`'s detail/edit loop sees exactly the results it saw
    before.
- **Alerts.**
  - The default alert is seeded for new events (`_seedDefaultAlert`).
  - The cap of 5 hides Add alert.
  - The `AutomationId`s stay on the same controls.
- **Linked note.** Resolved through `NoteRepository.getNotesByIds`, which is
  what gives the missing state.
- **Template.** `_onSaveAsTemplate` and its rules are unchanged.

### 4.2 Deliberately changes

| Today | After the redesign |
| --- | --- |
| One time / Recurring segmented control and frequency chips | Repeat row plus Repeat sheet |
| "From this date on / Always" chips | "Also before the start date" two-line switch in the Repeat sheet |
| Five priority chips | Priority menu; the row's glyph is a fixed flag |
| Day rail segmented control | Day rail menu |
| Inline Icon & color expansion tile | Icon & color sheet; the Tint row is disabled, not hidden, without a colour |
| Start and end tiles | `Starts` / `Ends` sub-rows; the end's ✕ replaces its chevron |
| One-time dates as chips with an Add date chip | A single date re-picks through the single picker; several dates are rows with an ✕ each, then an Add date row that opens the multi picker |
| Alert subtitle sentences ("Notification you can snooze") | The kind as a value: Reminder / Alarm |
| Hint paragraphs, and every per-field label line | Gone |
| The title counter always showing, the title on one line | The counter from 100 characters, under a title that wraps |
| No autofocus | The title autofocuses on a new event |
| Centred header title | Left-aligned header title |
| 48 dp drag-handle band | 22 dp handle strip |
| Description box stuck at 258 dp | One line (48) to ten lines (246), then it scrolls inside |
| Values ellipsized when a row is tight | The value drops under the label (German, Romanian, text scale 2.0) |
| Weekday chips with T/T and S/S | Circles with a caption that reads the picked days back in words |
| Linked note showing "Untitled Note" while it loads | An empty value until the title arrives |
| Close, back, system back, barrier tap and drag discard silently | They ask "Unsaved changes" first when anything changed (D20); a clean form leaves as before. Drag is the sheet's own gesture on the handle and header (§3.8) |

## 5. Facts from the tree (re-grep before editing)

- `lib/widgets/event_editor_sheet.dart`:
  - Entry and state: `show` :218 (`showDragHandle: true`,
    `FractionallySizedBox(0.92)`); `_descriptionMinHeight` :266;
    `_DayRailChoice` :136; `_RecurrenceKind` :154.
  - Getters: `_canSave` :906; `_ruleHasManyOccurrences` :950;
    `_scopeControlVisible` :966; `_syncScopeToRule` :1012.
  - Date handlers: `_pickDate` :1041; `_pickSkippedDays` :1083;
    `_selectAssumeAbsent` :1107; `_pickAssumeAbsentFrom` :1124;
    `_pickEndDate` :1144; `_pickOneTimeDates` :1161; `_removeOneTimeDate`
    :1175; `_setOneTimeDates` :1184.
  - Time and icon handlers: `_pickStartTime` :1195; `_pickEndTime` :1216;
    `_clearEndTime` :1244; `_setAllDay` :1248; `_pickIcon` :1257.
  - Alerts, category, notes, weekdays, template: `_seedDefaultAlert` :1273;
    `_editAlert` :1321; `_removeAlert` :1345; `_pickCategory` :1379 (the
    birthday pre-fill); `_pickNote` :1431; `_toggleWeekday` :1449;
    `_onSaveAsTemplate` :1468.
  - Build: `_buildDescriptionField` :1720; `_buildDescriptionBar` :1912;
    `_openDescriptionSheet` :1984; `build` :2016. The old widgets to delete
    once unused: `_GroupHeader` :2869, `_SectionLabel` :2899,
    `_IntervalStepper` :2921, `_PickerTile` :2978.
  - Leaving (D20): `_leave` :1972; the `PopScope` :2034 with
    `canPop: !widget.showBack`; `_alertsTouched` :546, set at :1314, :1331
    and :1347; `_onDelete`'s `AlertDialog` :1690 (`TextButton` cancel,
    `FilledButton.tonal` confirm — the shape to copy). `show` :228 passes
    `isScrollControlled: true, showDragHandle: true` and leaves `enableDrag`
    and `isDismissible` at their defaults (`true`).
- SDK facts (Flutter 3.47.4, verified 2026-09-25): the modal sheet's
  `onClosing` calls `Navigator.pop` directly
  (`material/bottom_sheet.dart:769–771`), so the route's drag-dismiss never
  consults `PopScope`; the barrier's `handleDismiss` calls
  `Navigator.maybePop` (`widgets/modal_barrier.dart`), so a barrier tap does.
- ARB: `unsavedChanges`, `discardChanges` and `keepEditing` exist in all
  three languages and nothing in `lib/` reads them.
- Grammar:
  - `lib/constants/row_metrics.dart` (`RowMetrics`);
  - `lib/constants/app_colors.dart:81` (`SurfaceRoles`: `pageGround`,
    `rowGroup`, `rowDivider`, `menuSurface`);
  - `lib/widgets/content_rows.dart:30` (`ContentRowShell`,
    `RowGroupPosition`).
- The avatar to copy: `lib/widgets/agenda_list_view.dart:1132`.
- Pickers:
  - `CalendarDatePickerSheet.pickSingle` :72 and `pickMulti` :100;
  - `TimePadSheet.pick` :62;
  - `CategoryPickerSheet.pickSingle` :44;
  - `IconPickerSheet.show` :42;
  - `AlertEditorSheet.show` :109;
  - `EventDescriptionSheet.show` :96;
  - `ColorSwatchPicker`;
  - `ValueChangeHighlight`.
- `RecurrenceFormatter.format(rule, l10n, localeName, {retroactive})` :12;
  `kMaxAlertsPerEvent` (`lib/constants/event_alerts.dart:21`);
  `SemanticsIds.eventAlertAdd` / `eventAlertRemoveAfter`.
- There is one caller, `lib/pages/calendar_page.dart`. Its detail/edit loop
  (`_openDetailSheet`) depends on `EventEditorBack`, `EventEditorDeleted` and
  the result's occurrence fields. None of them change.
- **Tests that exercise this sheet** (41 tests):
  `test/widgets/event_editor_alerts_test.dart`,
  `event_editor_assume_absent_test.dart`, `event_editor_back_test.dart`,
  `event_editor_day_rail_test.dart`, `event_editor_sheet_description_test.dart`,
  `event_editor_title_test.dart`, plus `sheet_bottom_clearance_test.dart`.
  They find controls by the old copy and widget types. Update the finders,
  keep every behaviour each test asserts, and **never delete or weaken an
  assertion to make it pass**.

## 6. Slices

### 6.0 The gate, after every slice

- `dart analyze lib` is clean. Add `test` to the analyze set if tests
  changed.
- `flutter test` is green: the whole suite, not only the files you touched.
- `flutter gen-l10n` has run if an ARB changed, and `untranslated.txt` holds
  nothing new.
- Re-read §4.1 against your diff.

### Slice 1 — Row primitives, chrome, capture group, Icon & color sheet

1. Build the shared row primitives from §3.1–3.2: group, section label,
   picker/switch/sub/action rows, and chip. Base them on `RowMetrics`,
   `SurfaceRoles` and `ContentRowShell`. Put them where later sheets can use
   them.
2. Chrome: the handle strip (D7), the header (D6) with its scroll hairline,
   and the `pageGround` ground (D8).
3. The capture group, including the description cell (§3.5) with its
   height, placeholder, overlays, counter and scope strip.
4. The Icon & color sheet (§3.6).
5. Autofocus (D4).
6. The old WHEN/Details widgets may stay temporarily below the new capture
   group so the sheet keeps working. Delete them in Slice 3.
7. Tests:
   - title autofocus only when new;
   - description height clamps, and the placeholder shows only while empty;
   - the Icon & color sheet: Done returns the draft, cancel returns `null`,
     the tint row is disabled without a colour and enabled with one;
   - the look row's value and dot;
   - the clearance test gains the new sheet.

### Slice 2 — WHEN group, one-off dates, Repeat sheet

1. The WHEN group exactly as in §3.3, including the per-date rows with
   their ✕ (D9), Add date, Starts/Ends (with `ValueChangeHighlight`,
   clear-end and the next-day label) and the Repeat row summary.
2. The Repeat sheet (§3.6) and draft application (the rules in §3.6 and
   §4.1).
3. The OCCURRENCES group placement: its visibility changes happen below
   WHEN.
4. Tests:
   - each Repeat option round-trips into the saved rule;
   - weekly with no weekday disables Done;
   - cancel changes nothing;
   - interval bounds;
   - a kind change re-resolves the count style until it is touched;
   - one-off dates: add through the picker, remove through a row's ✕, keep
     the earliest anchor, and never produce an empty set;
   - the single-date re-pick keeps weekday re-anchoring;
   - the Repeat row strings for once and several dates (both "Does not
     repeat"), weekly, "also before" and "until";
   - the weekday caption reads the picked days back, or the error with none;
   - the Repeat sheet's height is the same for every kind and weekday count;
   - the clearance test gains the Repeat sheet.

### Slice 3 — OCCURRENCES, ALERTS, DETAILS, actions, menus; delete the old UI

1. The rest of §3.3 and the menus.
2. Delete the old widgets and every unused ARB key (§3.7, grep first).
3. Update the six editor test files to the new UI, preserving every
   assertion's intent.
4. New tests:
   - priority and day rail menus set the value;
   - the Skipped days value;
   - linked note in its none, linked and missing states;
   - the scope strip appears, and `ensureVisible` runs when per-day is
     switched on while editing a specific day;
   - Remove after it rings shows only for one time plus an alarm.
5. The discard guard (§3.8): the fingerprint, `_confirmLeave`, `_leave`
   through it, the `PopScope` intercepting in every case, the route's
   `enableDrag: false` with the sheet-owned handle drag. Tests:
   - an untouched form: ✕ pops `null` at once, no dialog (the existing
     back tests keep passing unchanged);
   - a typed title: ✕ shows the dialog; Keep editing keeps the sheet and
     the text; Discard pops `null`;
   - `showBack` and dirty: Discard pops `EventEditorBack`;
   - the seeded default alert alone is not dirty;
   - system back on a dirty form shows the dialog;
   - a downward fling on the handle strip pops `null` when clean and shows
     the dialog when dirty (`tester.fling` on the strip);
   - a drag that ends short of the threshold snaps back and pops nothing.

### Slice 4 — Device pass, independent review, docs

1. **Device pass.** Load `qa-emulator`, use `./tool/qa/qa`, and never
   `adb`/`simctl` by hand.
   - **Devices:** the iOS simulator and the Android emulator (Android is the
     primary target).
   - **Boards:** capture the states of every B board listed at the top, in
     light, plus Editing in dark. Compare each against its board and list
     every visible mismatch. Fix it, or justify it in the report.
   - **German:** repeat New event, Weekly and Editing in German, where the
     strings are longest.
   - **Logs:** the run logs must show no `RenderFlex overflowed` or other
     framework errors.
   - **Behaviour:** check each of these on the device:
     - the keyboard comes up on a new event;
     - the description focus docks the bar and nothing jumps;
     - the Repeat and Icon & color sheets stack correctly and drag-dismiss;
     - back from the detail-sheet loop works;
     - five alerts hide Add alert;
     - birthday pre-fill;
     - several dates: add, remove and save;
     - the per-day scope strip opened from a day;
     - the over-limit description disables Save;
     - at text scale 2.0 no label clips, and values drop under their labels;
     - a dirty form asks on ✕, back, system back, the barrier tap and a
       downward fling on the handle; a clean one leaves silently;
     - the sheet's own handle drag feels as smooth as the native one — if
       not, apply the §3.8 fallback and record it.
2. **Independent review.** Spawn a fresh subagent that has none of your
   context.
   - **Brief it with:** the `git diff`, §3 and §4 of this doc, and the list
     of tests. Ask it to find, by reading the code:
     - behaviour regressions against §4.1 and §7;
     - layout shift: anything that appears or disappears above the control
       that caused it, other than the one `ensureVisible` case;
     - l10n misses;
     - accessibility gaps: semantics, 48 dp targets, labels on icon buttons;
     - performance: a keystroke-wide rebuild, or a listener on the re_editor
       controller;
     - lifecycle: missing `!mounted`, undisposed notifiers or controllers;
     - weak or missing tests.
   - **What it returns:** findings ranked by severity, each with the file and
     line, and each verified in the code rather than guessed.
   - **Then:** fix every confirmed finding, and re-run the gate and the
     affected device checks.
   - **Second pass:** if the `code-review` skill is available, run it at
     high effort.
3. **Docs**, in the same change:
   - rewrite `docs/calendar-events-feature.md` §6.3 for the new layout, and
     add a dated addendum;
   - update the event-editor passages in `COPILOT_CONTEXT.md`;
   - update the "Event editor sheet" section of
     `.claude/skills/calendar-events/SKILL.md`. Header alignment, the handle,
     frequency no longer as `ChoiceChip`s, the Repeat and Icon & color
     sheets, and the priority menu all change;
   - set this doc's status header to what shipped, with its deviations.

## 7. Definition of done — regression checklist

All of these must still work, checked in a widget test or on a device:
1. Create an event with only a title (a new-event default alert, if the
   settings say so). On a 412 × 915 phone the new-event form does not
   scroll.
2. Change the category. Birthday on a one-time event pre-fills Yearly and
   counting.
3. Set a custom icon, a custom colour and the tint. Reset them to the
   category defaults. The title avatar always shows the effective look; the
   Tint row is disabled, never hidden, without a colour.
4. Several one-off dates: add, remove with a row's ✕, re-pick by tapping a
   row. Presence and per-day descriptions become available.
5. Every repeat kind, the interval, weekly weekdays (at least one — the
   caption reads them back, and reads the error with none), the start date,
   the end date (set and clear with its ✕), and before the start date. The
   Repeat sheet's height does not change with the kind or the weekdays.
6. All day on and off. Start, end, no end (the ✕ clears it), an end past
   midnight.
7. Alerts: add up to 5, edit, remove. Reminder versus alarm as the value.
   "Remove after it rings" only for one time plus an alarm.
8. Count occurrences and its style with the live example.
9. Track presence, Assume present/absent, Absent from (and its ✕), Day rail
   (with the setting on).
10. Separate description per day, the scope strip from a day, Reset day,
    and the description limit with the grandfather rule: the counter and the
    error line, Save disabled.
11. Description: live markdown, checkbox toggling, the markdown bar,
    expanding to the full editor and back, the preview toggle with live
    rendering off, and the cell growing from one line to ten.
12. Skipped days when editing.
13. Priority through the menu. Linked note: none, loading (empty value),
    linked, unlinked, missing ("Not found").
14. Save as template. Delete with confirmation. Back from the detail loop,
    drag-dismiss, the barrier tap and system back — each asks "Unsaved
    changes" first when the form is dirty and leaves silently when it is
    not (D20).
15. A 120-character title wraps and its counter appears from 100.
16. Light and dark themes; en, de and ro; text scale 1.3 and 2.0 with no
    clipped label; a 360 × 780 phone; no overflow; 48 dp targets, the
    weekday cells and swatch dots included.

## 8. Deferred

- Bring `EventTemplateEditorSheet`, `AlertEditorSheet`, `QuickAlarmSheet`
  and `CategoryEditorSheet` to the same grammar. They are the next most
  visible forms and would now look older than this one.
- Reorderable alerts, and a live preview row mimicking the agenda card:
  both were considered and are not needed for this pass.
