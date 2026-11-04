# S3 design spec: the category editor's profile sections, the kind picker, the goal sheet

Designer, 2026-11-04. Rendered with real fonts (Roboto + MaterialIcons) in `AppTheme.light()` / `dark()` at 360 wide, 1.0 / 1.3 / 2.0, en and de. The current sheet came from its own `show` path (the robot's pump with the theme added); the proposal was composed from the real `form_rows.dart` primitives. Renders and the measurement log: `C:\Users\mobx3\AppData\Local\Temp\claude\1f7fcfde3754e771\dc8c4538-7be2-4be0-a72f-cd75703733f0\scratchpad\s3_renders\`. No HTML mock: every structure below is the existing primitives.

## 1. Diagnosis of the current sheet and the brief

Renders: `current_light_1.0_en_true.png`, `current_dark_1.0_en_true.png`, `current_light_2.0_de_true.png`.

- The sheet today: ✕ · title · Save, one group (name/read row, Icon, the swatch strip), the ALERTS label, the alert group, the alerts caption. It is content-tall: 538 dp (create) and 639 dp (edit, one alert) at 1.0; 571 / 702 at 1.3; 751 / 1017 at 2.0 de. The clamp is 717.6 on 360 × 780 and 841.8 on 412 × 915, so at 2.0 it already scrolls.
- What reads first is the name row, then the swatch strip (the largest mass), then the alerts. The new rows must not compete with that. They are setup rows, used once per category.
- Weaknesses the brief would cause if it were built literally, each found in the first proposal render:
  1. **The Goal read-back as a row value is clipped at 2.0.** `FormPickerRow.value` is clamped at `FormMetrics.valueMaxLines` (2): "Höchstens 180 Tage dazwischen" and "Erst eine Messgröße wählen" both rendered with `didExceedMaxLines`. The read-back must be the row's **caption**, which wraps freely. This is also what the lead's reading asked for.
  2. **The kind examples from §6.2 are too long for `FormCheckRow`'s two-line caption.** At 2.0 de, 8 of 21 were cut ("Fitnessstudio, Laufen, Schwimmen, Kurs", …), and at 2.0 en one was ("Stretching, journaling, cold shower"). Rule: every example is **≤ 28 characters in every locale**, at most three items. With the shortened set below, nothing clips at 2.0 de.
  3. **A caption that comes and goes changes the row's height at runtime.** A caption costs 28 dp (48 becomes 76 at 1.0). Every row below that carries a caption carries it in **every** state, with a different text per state.
  4. **A labelled period chip row ("Per" + four chips) never fits on one line.** It rendered 96 dp at 1.0 en, with Year wrapping alone onto a second run. The unlabelled chip row (`indented: false`) fits on one 48 dp run at 1.0 and takes two runs (96 dp) at 1.3 and 2.0.
  5. **The goal sheet grew at runtime** when the type switched to Days between at 2.0 de (591 → 627 dp, the read-back taking a second line). The value-and-read-back block needs the alert offset sheet's sizer (`FormCaptionSlot` over every state).
  6. **The stepper's layout follows its label.** "Amount" with a 7-digit `widestValue` dropped the stepper under its label at 2.0 (100 dp against 52). Switching Budget ↔ Days between changes the label, so the sizer must cover each type's group.
  7. **`FormMenuRow` has no caption**, and the Measure and Counts-as rows need one. That is a pass-through extension, not a new primitive (section 2.4).
  8. **`FormRadioRow` has no disabled state or id.** The goal type rows use `FormCheckRow(exclusive: true)`, which has both.

## 2. The spec

### 2.1 Placement in the editor (decision A)

After the existing `FormCaption(categoryAlertsHint)`, in the same `SingleChildScrollView` column:

```
… ALERTS group · "Every event in this category gets these alerts."
REPORT                                   FormSectionLabel(categoryReportSection)
[ ⧉  Kind ………………… Workout › / Gym, run, swim, class ]   FormRowGroup (trailingGap: true)
[ ✓  Mark ………………… Attended › ]
[ ◌  Area ………………… Health › ]
MEASURE & GOAL                           FormSectionLabel(categoryMeasureGoalSection)
[ ⌁  Measure ……………… Auto › / Auto is Attendance ]          FormRowGroup (trailingGap: false)
[ ◔  Counts as ……………… Off › / Suggested: 1 h ]
[ ⚑  Goal ………………………… › / At least 3 a week ]
```

Body padding is unchanged (`RowMetrics.groupInset`, `FormMetrics.bodyTop`, `FormMetrics.bodyBottom + clearance`). The alerts group loses nothing. Its caption stays the last child before the new label, because a `FormSectionLabel` carries its own top air. The last new group takes `trailingGap: false`, as the alerts group does today.

### 2.2 The editor's six rows

All rows sit inside `FormRowGroup`s, use glyph rows (`FormMetrics.glyphSize`, divider indent `FormMetrics.dividerIndentGlyph` 52), and draw their glyphs in `primary` (the primitive's default). Colours are the primitives' roles only.

| Row | Primitive | Glyph | Label key (en) | Value per state | Caption per state (always present unless "none") | Disabled | Id |
|---|---|---|---|---|---|---|---|
| Kind | `FormPickerRow` → `CategoryKindSheet.show` | `Icons.category_outlined` | `categoryKindLabel` "Kind" | the effective kind's name (`categoryKind<Name>`); unprofiled "Custom" | the kind's example (`categoryKindExample<Name>`); unprofiled "Anything else" | never | `category-editor-kind` |
| Mark | `FormMenuRow<_MarkChoice>` | `Icons.task_alt_rounded` | `categoryMarkLabel` "Mark" | the kind's verb (`markVerbLabel`), the owner's word, or `categoryMarkOff` "Off"; unprofiled "Off" | none | never | `category-editor-mark` |
| Area | `FormMenuRow<LifeArea>` | `Icons.donut_large_rounded` | `categoryAreaLabel` "Area" | effective area (`lifeArea<Name>`); unprofiled "Other" | none | never | `category-editor-area` |
| Measure | `FormMenuRow<ReportMeasure?>` + `caption:` (2.4) | `Icons.insights_rounded` | `categoryMeasureLabel` "Measure" | `categoryMeasureAuto` "Auto" while `measure == null`, else the measure's name | `categoryMeasureAutoIs(measure)` "Auto is Attendance" in both states (what Auto resolves to for this kind); a kind with null primary (Custom) `categoryMeasureAutoPerPeriod` "Auto picks per period" | never | `category-editor-measure` |
| Counts as | `FormMenuRow<int?>` + `caption:` | `Icons.timelapse_rounded` | `categoryCountsAsLabel` "Counts as" | `nominalMinutes` via `EventTimeFormatter.formatDuration`, else "Off" | enabled + the kind suggests S: `categoryCountsAsSuggested(S)` "Suggested: 1 h"; enabled, no suggestion: `categoryCountsAsScope` "For untimed events"; disabled: its reason (next column) | `onSelected: null` (38 %, in place, the stored value still shown) when the effective kind is Sleep (caption `categoryCountsAsSleep` "Sleep keeps its own hours") or the category has ≥ 1 live event and every one is the report's *repeat* shape (caption `categoryCountsAsRepeats` "Repeats earn no counted hours"), decided once at open | `category-editor-counts-as` |
| Goal | `FormPickerRow` → `CategoryGoalSheet.show`, `value: null` | `Icons.flag_outlined` | `categoryGoalLabel` "Goal" | none (label only) | the read-back (2.5): "At least 3 a week", "At most 40 h a week", "At most 180 days between", "Budget 1,200 a month"; no target: `categoryGoalNone` "No goal"; disabled: `categoryGoalNeedsMeasure` "Pick a measure first" (Custom on Auto) or `categoryGoalNotFor(measure)` "No goal for Days until" | `enabled: false` when the effective primary is null or Days until **and** no target is stored (a stored one stays reachable so it can be removed) | `category-editor-goal` |

**Menus** (`showFormMenu` through `FormMenuRow`, width `FormMetrics.menuWidth`, growing to `menuMaxWidth`; focus dropped first, as the row already does):

- **Mark** items, in order: the kind's verb if the kind has one (id `category-mark-kind`; stores `markVerb: null`), then the owner's word if one is set, otherwise `categoryMarkOwn` "Own word…" (id `category-mark-own`; always opens the dialog), then "Off" (id `category-mark-off`; stores `''` when the kind marks, `null` when it does not). The dialog is `AppDialogs.textInput(title: categoryMarkOwnTitle "Mark word", hintText: categoryMarkOwnHint "e.g. Walked", initialValue: the owner's word or the kind's verb word, maxLength: kCategoryMarkWordMaxLength (20, new in `category_name.dart`), selectAll: true, allowEmpty: false, fieldIdentifier: category-mark-word-field, confirmIdentifier: category-mark-word-save)`. The text is trimmed, and a word equal to the kind's own localised verb stores `null`. The checked item is the one in effect.
- **Area** items: the seven `LifeArea.values` in enum order (ids `category-area-<name>`). Picking the kind's own area stores `null`.
- **Measure** items: first "Auto · Attendance" (`categoryMeasureAutoWith(measure)`), or plain "Auto" for a kind with null primary (id `category-measure-auto`, stores `null`). Then the **headline measures** in enum order (count, events, hours, attendance, tasks, money, lastSeen, daysUntil), leaving out the one Auto already resolves to (ids `category-measure-<name>`). Cancelled, lead time and timing are never a primary here (decision D).
- **Counts as** items: "Off" (`category-counts-as-off`, stores `null`), then `CategoryKinds.countsAsChoices` = [15, 30, 45, 60, 90, 120, 240, 480] minutes (new const list in `category_kinds.dart`; ids `category-counts-as-<minutes>`), each labelled by `formatDuration`. The kind's suggestion is labelled `categoryCountsAsSuggestedItem(d)` "1 h · suggested". Picking an item **is** the confirmation (I): it stores `nominalMinutes`.

**Draft rules** (the editor holds a `CategoryProfile?` draft beside its other fields):

- **Kind pick** clears the `area`, `measure` and `markVerb` overrides. It keeps `nominalMinutes`, and keeps the target only if the new effective primary has the same goal unit (2.5) and the target's type is still allowed. Otherwise the target is cleared (decision F).
- **Measure pick** clears the target when the goal unit changes or the type becomes invalid (for example Budget off a Money primary).
- Every row a sub-sheet or menu writes to is wrapped in `ValueChangeHighlight`, inside a `FormIndentedRow(dividerIndent: FormMetrics.dividerIndentGlyph)` so the hairline keeps 52. A cleared Goal flashes too.
- `_isDirty` gains `draft != opened`. Save writes the profile through `CategoryProfileService.save` after the category row, and before the alerts' write, only when the draft changed. It writes nothing while there is no stored profile and the draft is still Custom with nothing overridden. Sandbox writes nothing. A profile-write failure takes the alerts' failure path (the sheet stays open, `_written` holds the row).
- `marksNew`, `assumeAbsentNew` and `countsHours` get **no row** in S3 (decision G).

### 2.3 The kind picker: `CategoryKindSheet` (new, `lib/widgets/category_kind_sheet.dart`)

- **Shape:** a sub-sheet, `CategoryPickerSheet.pickSingle`'s route flags exactly (`isScrollControlled`, `useSafeArea`, `showDragHandle: false`, `backgroundColor: pageGround`, top radius `FormMetrics.sheetRadius`, `ConstrainedBox(maxHeight: height × FormMetrics.sheetHeightFactor)`). It is content-tall and in practice always at the clamp: 717.6 dp on 360 × 780 at every scale (measured). It is unguarded and picks on tap.
- **Header:** `FormSheetHandle`, then `FormSheetHeader(close_rounded, tooltip cancel, id category-kind-close, title categoryKindLabel "Kind", trailing: SizedBox.shrink(), trailingInset: FormMetrics.headerActionInset)`. The trailing slot is empty because single mode has nothing to confirm (the category picker's precedent).
- **Body:** `SingleChildScrollView` with the standard padding (clearance included). For each `CategoryKinds.areas` (enum order) there is one `FormSectionLabel(lifeArea<Name>)` and one `FormRowGroup` of `FormCheckRow(exclusive: true, label: kind name, caption: kind example, checked: kind == selected, identifier: category-kind-<name>, onChanged: pop(kind))` over `CategoryKinds.inArea(area)` in catalogue order. The last group (OTHER: Custom) takes `trailingGap: false`. No glyph and no avatar, so the plain indent is 16. **No search row** (decision E).
- **Opens at the top** and does not scroll to the checked row (decision H).
- **Returns** `CategoryKind?`. Null on ✕, barrier, back and drag.
- **Measured:** row 62 dp at 1.0 (two-line `FormCheckRow`), ±1. The 2.0 de examples render whole on two lines.

**The 21 examples (en; ≤ 28 characters in every locale is the rule for de / ro too):**

| Kind | Example | Kind | Example |
|---|---|---|---|
| Routine | Stretching, journaling | Bill | Rent, bills, subscriptions |
| Workout | Gym, run, swim, class | Income | Salary, paid invoices |
| Medication | Pills, supplements | Social | Dinners, visits, dates |
| Sleep | The night and its length | Anniversary | Birthdays, name days |
| Episode | Illness, migraine, cycle | Chore | Cleaning, laundry, groceries |
| Appointment | Doctor, dentist, vet | Maintenance | Car service, boiler |
| Work | Shifts, working days | Expiry | Passport, ID, warranty |
| Meeting | Calls, stand-ups, reviews | Trip | Travel, weekends away |
| Task | To-dos, errands | Leave | Vacation, days off |
| Deadline | Submissions, filings | Custom | Anything else |
| Study | Courses, practice, reading | | |

Leave sits under WORK, where its catalogue area puts it, after Study.

### 2.4 Two pass-through extensions in `form_rows.dart` (no new primitive)

1. **`FormMenuRow.caption` (+ `captionMaxLines`)** passes straight to the `FormPickerRow` it builds. A disabled row (`onSelected: null`) dims its caption with it. Pin it in `form_rows_test.dart`: one node carries label, value and caption, and the caption is dimmed while disabled.
2. **`FormStepperRow` editable value:** optional `controller` (`TextEditingController`), `focusNode`, `maxDigits` and `fieldIdentifier`. With a controller, the value box holds a collapsed `TextField` in place of the `Text`, in the same `valueStyle` (15 / 500 tabular, `onSurface`, centred), in the same box sized by `widestValue`, so nothing moves.
   - Field settings: `keyboardType: TextInputType.number`, `FilteringTextInputFormatter.digitsOnly` + `LengthLimitingTextInputFormatter(maxDigits)`, `textInputAction: done`, `onTapOutside` unfocus. The node's accessible name is the row label (`Semantics(label: label, textField: true)`, the `FormTitleRow` precedent), and `fieldIdentifier` goes on the field node.
   - − and + rewrite the controller text with the selection at the end.
   - Pin it in `form_rows_test.dart`: the box width is the same with the field and with the `Text`, and the row is the same height in both.

### 2.5 The goal sheet: `CategoryGoalSheet` (new, `lib/widgets/category_goal_sheet.dart`)

- **Shape:** a sub-sheet with the alert offset sheet's flags (pageGround, `sheetRadius`, clamp `sheetHeightFactor`), content-tall, unguarded, `FormHeaderHairline` on the scroll view.
- **Header:** ✕ (cancel, `category-goal-close`), title `categoryGoalTitle` "Goal", trailing `FormHeaderTextButton(eventDescriptionDone "Done", category-goal-done)` with `trailingInset: FormMetrics.headerActionInset`. Done is disabled while the value field is empty or 0. **Done, not Save** (decision I).
- **Returns** sealed `CategoryGoalResult`: `CategoryGoalSaved(ReportTarget)` or `CategoryGoalRemoved()`. Null on ✕, barrier, back and drag.

```
✕  Goal                               Done
TYPE                                        FormSectionLabel(categoryGoalTypeSection)
[ At least                      ✓ ]         FormCheckRow(exclusive) ×3, 48 dp each
[ At most            (Budget on Money) ]
[ Days between                    ]
TARGET                                      FormSectionLabel(categoryGoalTargetSection)
[ Count          [−]   3   [+]   ]          FormStepperRow (editable, 2.4)
[ (Day) (Week) (Month) (Year)    ]          FormChipRow(indented: false)
At least 3 a week                           FormCaption(groupCaptionPadding) in the sizer
                                            SizedBox(RowMetrics.groupGap)
[ 🗑 Remove goal                  ]          FormActionRow(destructive), own group, trailingGap false
```

- **Type rows** (`category-goal-type-<atLeast|atMost|budget|maxGap>`) are always three:
  - On a Money primary they read At least · Budget · Days between (Budget stores `TargetKind.budget`).
  - Otherwise they read At least · At most · Days between.
  - They are ordered with the kind's presets' types first, in preset order, then the rest in that canonical order.
  - Rows the primary cannot take are drawn disabled (`onChanged: null`, 38 %, in place): on Last seen, At least and At most are disabled and Days between is preselected.
- **Opening draft:** the stored target, or the first preset (kind + period) with the seed value (decision J). Two values are held separately: the amount (the primary's unit) and the days (for Days between). Switching type keeps each.
- **Value row label** follows the unit:

  | Primary | Label | Stored as | Read-back amount |
  |---|---|---|---|
  | count / events / attendance | `categoryGoalUnitCount` "Count" | the number | `NumberFormat.decimalPattern` |
  | hours | `categoryGoalUnitHours` "Hours", whole hours | minutes = h × 60 | `categoryGoalHours(h)` "40 h" |
  | tasks | `categoryGoalUnitTasks` "Tasks" | the number | `categoryGoalTasks(n)` "5 tasks" |
  | money | `categoryGoalUnitAmount` "Amount", whole units | cents = n × 100 | decimal pattern, no symbol |
  | Days between (any primary) | `categoryGoalUnitDays` "Days" | the number of days | — |

  Bounds and steps come from a new `CategoryGoalLimits` in `category_kinds.dart`: min 1; max digits 3 for count / tasks, 4 for hours / days, 7 for money; step 1 everywhere. − is disabled at 1, + at the maximum. `widestValue` is fixed per open: "9999999" on a Money primary, else "9999". Steppers: tooltips `categoryGoalLess` "Less" / `categoryGoalMore` "More", ids `category-goal-less` / `category-goal-more`, field id `category-goal-value`.
- **Period chips** Day · Week · Month · Year (`categoryGoalPeriod<Name>`, ids `category-goal-period-<name>`): all `onTap: null` (38 %, in place) while Days between is chosen. Budget allows all four, preselecting Month (decision K).
- **Read-back** (the same function the editor's Goal caption uses), ICU:
  - `categoryGoalAtLeast(amount, period)` "At least {amount} {period, select, day{a day} week{a week} month{a month} year{a year} other{}}"
  - `categoryGoalAtMost` "At most …" and `categoryGoalBudget` "Budget …", built the same way
  - `categoryGoalGap(days)` "{days, plural, =1{At most 1 day between} other{At most {days} days between}}"
- **Sizer:** the TARGET group plus the read-back sit in one `FormCaptionSlot` whose candidates are that group built for **every type the sheet offers**, laid over one another (`Stack`), and under them every read-back at the widest value. This is `AlertOffsetSheet._buildSizer`'s shape, so the sheet's height never changes while the owner works in it.
- **Remove goal** (`categoryGoalRemove`, `Icons.delete_outline_rounded`, `category-goal-remove`) is present only when the sheet opened on a stored target, the alert sheet's `canRemove` precedent (decision L). Its group is preceded by `RowMetrics.groupGap`.
- **Focus:** the field is never autofocused. Done and ✕ call `_blur()` first.

## 3. What stays, and why

- Everything above the new REPORT label stays: the header, the name / read row, Icon, the swatch strip, the alerts rows, their caption and their ids. The new sections append below the existing column, so nothing they do can move those rows.
- `FormSheetFrame(mainAxisSize: min)`, `FormSheetSemanticsRefresh`, the leave guard and the save order (category, then profile, then alerts) stay. The only change is that the profile write joins the chain and `_isDirty`.
- No new idiom and no new primitive: two pass-through extensions, two new sub-sheets on existing shapes, and the `AppDialogs.textInput` prompt.

## 4. Risks

- **Height budget:** the editor becomes clamp-tall on every phone at every scale. The new tail adds about 486 dp at 1.0 (the two sections, measured), so edit is about 1,125 dp and create about 1,024 dp, against a 717.6 / 841.8 clamp. The sheet now opens 717.6 tall where it opened 538 / 639, so the existing rows sit higher on screen than today; at runtime nothing moves. The first screen still shows the name, Icon, strip and alerts; REPORT starts below the fold at 1.0. If the owner wants the sheet short, decision C is the lever.
- **A kind pick at ≥ 1.3 in de / ro may reflow the rows below Kind once.** The Mark row "Markierung … Teilgenommen" is 66 dp against 48 for "Aus" at 1.3 de (measured), and the caption lines vary by kind. This happens on the return from the kind sheet (the finger is not on the editor), in the language's "a value the user set" exception, and the Goal caption is last in the sheet. Accepted, not fixable without fixed-height captions.
- **Text scale:** measured, with no clipping in the final set.
  - Editor rows at 1.0: 76 (captioned) and 48 (Mark, Area).
  - At 1.3: 81 / 48 in en; at 1.3 de, Mark reaches 66 with a long verb.
  - At 2.0 de: Kind 134, Measure 176 (label, value and a two-line caption all wrap), Counts 98 to 134, Goal 134.
  - Goal sheet totals: 477 (1.0), 538 (1.3), 591 to 639 (2.0), all under the clamp.
- **German / Romanian:** the ≤ 28-character example rule must hold in de and ro. The implementer's German 2.0 case should assert `textWhole` on every example and every read-back. Romanian read-backs ("Cel puțin 3 pe săptămână") run about 10 % longer than de and are inside the caption's free wrap.
- **Dark:** only role colours are used. In `tail_dark_1.0_en_workout.png` the glyphs are in primary and the captions in onSurfaceVariant on rowGroup. No new colour.
- **Keyboard:** only the goal sheet raises it, and the sheet stays under the 0.92 clamp. With a 330 dp IME at 1.3 de the value row stays visible in a scrolling body; I could not render the real sheet's IME behaviour because it is not built. That is a device check: `qa screenshot` with the field focused in de at 1.3 and 2.0.
- **Menus at 2.0:** Counts as has 9 items and Measure up to 9. Whether `showFormMenu` scrolls a menu taller than the space below the row at 2.0 is unverified. Device check.
- **Semantics:** every new control has an id (section 2). The Goal row's node reads "Goal, At least 3 a week". The editable stepper's field node is named by its label.
- **Guide demos:** the sandboxed editor in the guide grows by these rows. Any guide test that pins the demo editor's height or scroll extent will move.

## 5. Decisions taken by default (all reversible)

- **A — The new sections go after Alerts.** Today's first screen is unchanged, the alerts stay the editor's daily job, and the Goal caption (the one value that wraps) sits last in the sheet, where its growth moves nothing. *Alt:* before Alerts.
- **B — The section labels are "Report" (Kind, Mark, Area) and "Measure & goal" (Measure, Counts as, Goal).** A "KIND" label over a row named Kind would be redundant, and Mark and Area belong with the kind's identity rather than with the numbers. *Alt:* the record's literal Kind / Measure & goal split.
- **C — The rows go inline, as the record's §7 has them.** *Alt:* one row "Report · Workout ›" opening a profile sub-sheet. The language's "advanced controls go one level down" favours that, and it keeps the editor content-tall (about 614 dp), at the cost of one more tap to every profile field.
- **D — The Measure menu is Auto plus the eight headline measures** (no Cancelled, Lead time or Timing as a primary), leaving out the one Auto resolves to. *Alt:* Auto + the kind's secondary only.
- **E — The kind picker has no search.** It is 21 rows in seven labelled groups, and search would raise the keyboard. *Alt:* `FormSearchRow` as the category picker has past its threshold.
- **F — A kind pick resets the area, measure and mark overrides**, keeping the counts-as and a still-valid target. *Alt:* keep every override.
- **G — No rows for marksNew, assumeAbsentNew or countsHours in S3.** They follow the kind. *Alt:* switches under Mark.
- **H — The kind picker opens at the top.** *Alt:* scroll the checked row into view.
- **I — The goal sheet confirms with Done**, the sub-sheet rule. The editor's Save persists. *Alt:* the brief's "Save".
- **J — Seeds:** 3 times, 3 tasks, 8 h, 30 days, 100 money; whole hours (no 7.5 h); step 1. *Alt:* half-hour steps with a decimal field.
- **K — Budget allows any period**, Month preselected. *Alt:* J's month only (the other chips disabled).
- **L — Remove goal appears only when a goal was stored**, the alert sheet's `canRemove` precedent. *Alt:* always present, disabled on a fresh draft.
- **M — Counts as is a menu of eight durations**; the pick is the confirmation, and there is no duration sheet. `TimePadSheet` reads clock times and would show "1:00 AM" for 60 minutes on a 12-hour device. *Alt:* a stepper sub-sheet in the alert offset sheet's shape.
- **N — The own mark word is set in `AppDialogs.textInput`**; stock verbs other than the kind's are not offered. *Alt:* list all seven stock verbs.
- **O — Custom's Auto is not resolved in the editor.** The caption reads "Auto picks per period", because the report resolves Auto per span and an all-time resolution could contradict the page. *Alt:* resolve over the last 366 days.
- **P — The goal value is the editable stepper (2.4).** *Alt:* a `FormPickerRow` opening `AppDialogs.textInput` (numeric), with no primitive change.

## 6. Renders, measurements, and what the design-reviewer re-renders

Renders in `C:\Users\mobx3\AppData\Local\Temp\claude\1f7fcfde3754e771\dc8c4538-7be2-4be0-a72f-cd75703733f0\scratchpad\s3_renders\`:
- current: `current_light_1.0_en_false.png`, `current_light_1.0_en_true.png`, `current_dark_1.0_en_true.png`, `current_light_2.0_de_true.png`
- tail: `tail_light_1.0_en_workout.png`, `tail_dark_1.0_en_workout.png`, `tail_light_1.0_en_custom.png`, `tail_light_2.0_de_workout.png`, `tail_light_2.0_de_sleep.png`
- kind sheet: `kind_light_1.0_en.png`, `kind_dark_1.0_en.png`, `kind_light_2.0_de.png`
- goal sheet: `goal_light_1.0_en_count.png`, `goal_dark_1.0_en_money.png`, `goal_light_1.3_de_gap.png`, `goal_light_2.0_de_gap.png`, `goal_dark_2.0_en_money.png`
- the full measurement log: `proposal_measure.txt`

Caveats on the composed proposal renders:
- The Goal value in the `tail_*` PNGs predates the switch to a caption. The final measurements in `proposal_measure.txt` carry the caption form.
- The goal-sheet PNGs have no sizer around TARGET, only around the read-back; the 2.0 de 591 → 627 growth is the reason the sizer is specified.

Key measurements (±1 dp):

| Element | 1.0 en | 1.3 en | 1.3 de | 2.0 de |
|---|---|---|---|---|
| Kind (captioned) | 76 | 81 | 81 | 134 |
| Mark / Area | 48 / 48 | 48 / 48 | 66 / 48 | 94 / 94 |
| Measure (captioned) | 76 | 81 | 81 | 176 |
| Counts as (captioned) | 76 | 81 | 81 | 98 to 134 |
| Goal (caption read-back) | 76 | 81 | 81 | 134 |
| Tail total | 520 | 553 | 553 / 571 | 854 to 896 |
| Kind sheet | clamp 717.6, rows 62 | | | |
| Goal sheet | 477 | 538 | 538 | 591 to 627, to be one value with the sizer |

Sheet clamps: 717.6 on 360 × 780, 841.8 on 412 × 915.

The design-reviewer re-renders after the build:
1. The editor unprofiled (Custom / Off / Other / Auto / "For untimed events" / "Pick a measure first").
2. The editor as Workout with a goal, as Sleep (Counts as disabled), and with a repeat-only category.
3. All of these in light and dark at 1.0 / 1.3 / 2.0 in en and de, plus ro at 2.0, at 360 × 780 and 412 × 915.
4. The kind sheet at 2.0 de and ro (every example whole).
5. The goal sheet's three type states on a count primary, Budget on Money, and Last seen (two types disabled): first that the height is one value across the type switches at 2.0 de, then the same at 1.3 with the IME faked through `tester.view.viewInsets`.
6. The Mark word dialog at 2.0 de.
7. From the device (`qa screenshot`): the Counts-as and Measure menus open at 2.0, and the goal field focused with the real IME.
