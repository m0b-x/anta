# Calendar UI Language — Tier 2 record: the alert sheet, the quick alarm and the template editor (2026-10-02)

**Status: COMMITTED `daf361a` (2026-10-03).** Slices 0–6, a fix
round and a device re-check are in the tree: `dart analyze lib test tool
test_driver` clean, `flutter test` 6669 passed / 7 skipped / the known
Windows-only `host_devices_test` case (6251 before the tier),
`untranslated.txt` `{}`, `qa flows calendar` 17 / 17 on the Pixel emulator,
`qa errors` clean, every id of §3.9 seen on its control, the independent
review's three defects and the device pass's findings fixed (§9). Tier 2
of `docs/calendar-language-adoption-roadmap.md`,
the owner's max-effort plan for every calendar surface still outside the
2026-09-25 language. The owner answered the four open decisions on
2026-10-02 from the Design canvas **"Editor Satellites Mocks"** —
https://claude.ai/artifact/X4dZF5d2DsmLrK5GvadzuW — (twenty-three boards:
today's six device shots, the alert sheet in five states, the quick alarm in
three, the template form in three, dark, two German 200 % stress boards, the
ids); every answer was the recommended option. Where a board and this record
disagree, **this record wins** (the known places: the boards draw a disabled
header action in the colour §3.5 corrects; the When-menu board draws the
menu above its row because eight items do not fit under it, which is the
shipped `formMenuPosition` rule and not a new one). Line numbers in §5 are
from a read of the tree at `d501f42` on 2026-10-02; re-grep every one before
editing.

## 0. How to run this

Load `anta-context`, `calendar-events`, `ui-language`, `calendar-ui`,
`ui-revamp`, `verify`, `l10n`, and `qa-emulator` for slice 6. Read this
record whole, then §5 against the tree. Work the slices of §6 in order, one
implementer writing at a time; never start a slice with anything red. After
**every** slice the gate:

- `dart analyze lib test` clean;
- the **whole** `flutter test` green in one run. The baseline after slice 0
  is **6326 passed, 7 skipped, 1 failed**, the one failure being the known
  Windows-only `test/qa/host_devices_test.dart` "MacosDevice locate reads
  the product name from AppInfo.xcconfig" — note it, never touch it. A
  `sqlite3.dll` lock crash is transient: rerun;
- `flutter gen-l10n` run and `frontend/anta/untranslated.txt` equal to `{}`
  whenever an ARB changed;
- §4.1 (must not change) re-read against `git diff`.

**Never run `flutter test` while a QA `flutter run` is up** (two Flutter
processes race on `build/native_assets`): `tool\qa\qa.cmd kill-run` first —
the app stays installed, `qa relaunch` brings the agent back in seconds.

Models, by the owner's choice of 2026-09-27 for this whole pass: design,
implementation and the independent review on `fable-max`; exploration may go
to Opus. Do not commit — the owner reviews the tree and commits; Tier 3
starts on a clean tree.

**The robots are the regression proof.** Slice 0 put a driver per sheet
between the suites and the widgets (`test/widgets/support/`). A slice that
rebuilds a sheet rewrites that sheet's robot for the new UI and leaves the
test bodies alone. A test body changes only where §4.2 says the behaviour
changes on purpose, and each such change is named in the slice's report.

## 1. Why

The migrated event editor opens three sheets that still speak the older
chrome — the stock 48 dp drag band, a centred title, a filled Save in the
header, `Card`s, `ChoiceChip`s, `SegmentedButton`s and `SwitchListTile`s —
so the seam sits in the app's most-used flow: Add alert, the day's
long-press, Save as template.

The device walk of 2026-10-02 (Pixel emulator, QA seed) found, beyond the
chrome:

- **Three clocks.** The quick alarm and the template editor follow the
  phone's 12-hour setting; the alert editor's Time of day row is 24-hour
  only (`EventTimeFormatter.formatRange`), and so is every row that
  describes an all-day alert (`EventAlert.describe`).
- **Two tier orders.** Reminder | Alarm in the alert editor, Alarm |
  Reminder in the quick alarm.
- **Rows that come and go.** Alarm sound and Remove after it rings exist
  only on the Alarm tier; the full-screen warning arrives after the sheet
  has opened and pushes everything under it down; the template editor's
  repeat-only block appears and disappears with the kind.
- **The template editor's seventh weekday chip wraps** onto its own line.
- **A custom offset is a stepper that moves one step per tap**, and opening
  Custom on "At start" rewrites the offset to one minute before the user
  has confirmed anything.
- **No sheet drops focus before it opens a picker.** The quick alarm loses
  a typed title silently, and the template editor had no test suite.

Slice 0 added what it found while pinning (§9): the template editor's time
rows raise a framework error in debug builds, a close during an in-flight
save still writes the template, and a template made in its own editor can
store things the event editor would refuse.

## 2. Decisions (owner, 2026-10-02)

D1–D4 were asked as lettered options and answered; D5–D13 were put on the
canvas as "taken as recommended unless you object" and stand.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | **The template editor is its own form sheet** — the editor's twin, built from the editor's groups and the editor's own sub-sheets — **not a mode of the event editor.** (A; B was the mode.) | A template is not an event: no date, no alerts, no note, no skips, so a mode hides about fifteen rows and shares the rest. The mode would also add a second result type and a second save path to the app's most-used form and change what a template stores in six places. Every regression of a twin lands in the twin |
| D2 | **An alert's When is one menu row** over the presets, ending in "Custom…", which opens a small sub-sheet. (A; B kept the chips inline.) | The sheet never changes height. Inline, eight chips take three lines and Custom reveals two more rows, about 150 dp under the finger. The cost is one more tap per preset, which the owner accepted |
| D3 | **The quick alarm leads with the time** as a hero row at 40 px with the day under it, the presets in the same group, then the title, then Type and Remove after it rings. (A; B was the editor's order with a plain Time row.) | The time is the one value the user verifies at a glance, usually in the middle of something else |
| D4 | **The template form reaches parity with the editor**: the count-style chips, a markdown description through the description sheet with the editor's length limit, weekly needs a weekday. (A; B kept today's behaviour.) | A template stamps an event; what the editor would refuse should not be storable in a template made by hand |
| D5 | **Disabled, never hidden.** On the Reminder tier the Alarm sound row and the Remove after it rings switch stay in place at 38 % in both sheets. They are absent only where the caller never offers them (`showSound: false` in settings, `showRemoveAfter: false` on a repeating event) | The language's rule for sub-sheets. The suites that assert their absence change on purpose (§4.2) |
| D6 | **One tier order, Reminder then Alarm**, in both sheets. The quick alarm still opens on Alarm | One control, one order |
| D7 | **One clock.** An all-day alert's time follows the phone's 12 / 24-hour setting in the sheet and in every widget that describes the alert | `EventAlert.describe` gains an optional formatter; services keep the neutral 24-hour text |
| D8 | **No repeat or snooze switches.** | `EventAlert` has no such fields; snooze is the one global setting `alert_snooze_minutes`. The adoption roadmap's mention was wrong and is corrected there (§2.4) |
| D9 | **A custom offset keeps today's stepper and bounds** (1–59 min, 1–23 h, 1–30 d), now in the Custom sub-sheet, and writes only on Done | A typed entry is deferred (§8) |
| D10 | **Header actions are text**: Done on the alert sheet and the Custom sub-sheet, Save on the quick alarm and the template form. The filled Save stays the editor's alone. `alert-sheet-save` and `quick-alarm-save` stay on those actions | The adoption roadmap's standing decision; ids are never renamed |
| D11 | **Remove after it rings is parked, not dropped.** On the Reminder tier the switch shows off at 38 %; back on Alarm it shows what it showed before. In the alert sheet the result carries `false` only when *this sheet* turned an alarm into a reminder; a reminder that was opened and confirmed hands the event's flag back as it came (corrected in slice 2: the flag is the event's, and a reminder edited beside an alarm must not disarm it) | Today the quick alarm opens with the switch on and loses it for good on a round trip through Reminder |
| D12 | **Leaving the template form asks when it is dirty** (the editor's guard), and a leave is ignored while its save is in flight | It has typed text; today a close during the write still creates the template and returns `null` |
| D13 | **Icon & color sits in the capture group**, between Category and the description row, as in the editor; DETAILS holds Priority alone | The twin mirrors the editor's order. Found by the mock pass: the first brief had it under DETAILS |
| D14 | **A chip's 32 dp is a minimum, not a fixed height** (slice 2, delegated under the pass's "no defect deferred" rule). Above 160 % text a `FormChip` grows with its label instead of cutting it; at 160 % and below nothing changes | Found when the Type and unit chips replaced segmented buttons that scaled: at 200 % a 14 px label needs a 40 px line and the chip clipped its descenders. The same cut was already shipping in the editor's count-style and assume chips and the detail sheet's presence chips, which this fixes too |

## 3. The spec

### 3.1 Geometry and tokens

Every number comes from `FormMetrics` or `RowMetrics`, every colour from the
`SurfaceRoles`; no literal, nothing from the generic `AppSpacing` scale, no
`Card`, no elevation. New names, added to `lib/constants/form_metrics.dart`
in slice 1:

| Name | Value | Use |
| --- | --- | --- |
| `heroValueSize` | 40 | the quick alarm's time |
| `heroValueLineHeight` | 46 | its line |
| `heroRowMinHeight` | 84 | the hero row: the two-line row's padding around a 46 px line, a 2 px gap and an 18 px caption line |
| `stepperValueMinWidth` | 96 | the stepper row's value box (today `_IntervalRow.valueMinWidth`) |
| `titleRowVerticalPadding` | 8 | the title row, hoisted with it out of the editor (slice 1) |
| `titleFieldTopInset` | 7 | the title field's top inset beside the avatar |
| `titleCounterTopInset` | 2 | the gap above the title's counter line |

Shapes: the alert sheet, the Custom sub-sheet and the quick alarm are
**sub-sheets** (content-tall, clamped at `sheetHeightFactor`, route drag, no
guard); the template form is a **form sheet** on `FormSheetFrame` (fixed at
`sheetHeightFactor`, the discard guard). Bottom clearance in each is the
larger of `viewInsets.bottom` and `viewPadding.bottom`, on the scroll view's
bottom padding. Every picker, menu and sub-sheet opened from a sheet with a
text field drops focus first.

### 3.2 The alert sheet (`AlertEditorSheet`)

`show(...)` keeps its signature, its six named parameters and its three
outcomes (§4.1). Chrome: `FormSheetHandle`, `FormSheetHeader(close_rounded
[alert-sheet-close] · eventAlert · FormHeaderTextButton(eventDescriptionDone)
[alert-sheet-save])`, `Flexible(SingleChildScrollView)`.

| Group | Row | Primitive | Notes |
| --- | --- | --- | --- |
| 1 | Type | `FormChipRow(glyph: notifications_outlined, label: eventAlertTypeSection)` with `FormChip`s `eventAlertModeNotify` [alert-type-reminder] and `eventAlertModeRing` [alert-type-alarm], in that order | Its `caption:` is a `FormCaptionSlot` (§3.7) over three candidates: `eventAlertNotifyHint`, `eventAlertRingHint`, and — in the error colour, while the tier is Alarm and the permission answer is a definite no — `eventAlertFullScreenOff`. The slot is as tall as the tallest of the three, so neither the tier nor the late answer moves anything |
| 2 | When | `FormMenuRow(glyph: timer_outlined, label: eventAlertWhenSection)` [alert-when] | Items: the presets of today (`:178–189`) labelled as today, then `eventAlertCustomItem`. Timed: 0, 5, 10, 15, 30, 60, 1440 minutes [alert-when-`n`], value = `describe`. All-day: 0, 1, 7 days [alert-when-day-`n`], labels `eventAlertOnTheDay` / `TheDayBefore` / `AWeekBefore`, any other count `eventAlertDaysBefore(n)`. The Custom item [alert-when-custom / alert-when-day-custom] is the checked one whenever the value is not a preset. Picking it opens the Custom sub-sheet (§3.3); a cancelled sub-sheet changes nothing |
| 2 | Time of day | `FormPickerRow(glyph: schedule_outlined, label: eventAlertTimeOfDay, value: EventTimeFormatter.formatMinute(…, context))` [alert-time-of-day] in a `ValueChangeHighlight`, the pair inside a `FormIndentedRow` (§3.7) so the group still reads the row's indent | All-day events only. Opens `TimePadSheet.pick` exactly as today (`:349–358`) |
| 3 | Alarm sound | `FormPickerRow(glyph: music_note_outlined, label: alertsSound, value: AlertSoundSheet.labelFor(…), enabled: isAlarm)` [alert-sound] | Present while `showSound`. `_pickSound` is unchanged (`:269–289`) |
| 3 | Remove after it rings | `FormSwitchRow(glyph: auto_delete_outlined, label: eventAlertRemoveAfter, subtitle: eventAlertRemoveAfterHint)` [alert-remove-after] | Present while `showRemoveAfter`. Shows `isAlarm && _removeAfter`, `onChanged: null` on the Reminder tier; `_removeAfter` itself is kept across a tier change (D11). The result's `removeAfterAlert` is `_removeAfter`, except `false` when this sheet demoted an alarm to a reminder — so a reminder confirmed untouched hands the event's flag back |
| 4 | Remove alert | `FormActionRow(glyph: delete_outline_rounded, label: eventAlertRemove, destructive: true)` [alert-remove] | Present while `canRemove`; pops `AlertEditorRemoved` |

Group 3 is absent when it would hold no row (the settings caller on a
repeating sample). No section labels: the two row labels already say
"When" and "Alarm".

### 3.3 The Custom sub-sheet (`AlertOffsetSheet`, new)

`lib/widgets/alert_offset_sheet.dart`. `static Future<int?> show(context,
{required int initial, required bool allDay, required String
Function(int stored) readBack})` returns minutes for a timed event and days
for an all-day one, `null` on ✕ / drag / back / barrier. `readBack` is the
caller's own wording for a value — the alert sheet passes the function its
When row reads its value with, so after Done the row says exactly what the
sub-sheet showed ("The day before", not "1 day before"). The body keeps one
height across the units and their ceilings (a `FormCaptionSlot` over each
unit's widest state), so a unit change moves nothing.
Chrome: `close_rounded [alert-custom-close] · eventAlertCustom ·
FormHeaderTextButton(eventDescriptionDone) [alert-custom-done]`. One
`FormRowGroup(trailingGap: false)`:

- timed only: an unlabelled `FormChipRow(indented: false)` (§3.7 — a chip
  row that stands alone starts at the group's inset, in a 48 dp row) of
  `eventAlertUnitMinutes` / `Hours` / `Days` [alert-custom-unit-minutes /
  -hours / -days];
- a `FormStepperRow` (§3.7): the label is the unit's own name (Days for an
  all-day event), the value the number, tooltips
  `eventAlertOffsetDecrement` / `Increment` [alert-custom-less / -more];
- under the group a `FormCaption(padding: groupCaptionPadding)` reading the
  result back through `readBack`.

The rules move unchanged out of the old sheet into a pure class,
`lib/utils/alert_offset.dart` (`AlertOffset`, table-tested): the unit is a
view over minutes (`:45–56`); the bounds are 1–59 min, 1–23 h, 1–30 d
(`:194–198`, `:322`); changing the unit keeps the number, clamped
(`:325–331`); an all-day event counts in days only (`:342–344`). The sheet
opens on the value's natural unit (days when it divides by 1440, hours when
it divides by 60, else minutes) with the number clamped into that unit's
range and never under 1.

### 3.4 The quick alarm (`QuickAlarmSheet`)

`show({day, now})` and `QuickAlarmDraft` are unchanged. Chrome:
`close_rounded [quick-alarm-close] · quickAlarmTitle ·
FormHeaderTextButton(save) [quick-alarm-save]`, always enabled.

| Group | Row | Primitive | Notes |
| --- | --- | --- | --- |
| 1 | Time | `FormHeroRow(glyph: alarm_outlined, value: EventTimeFormatter.formatMinute(_minute, context), caption: the day label, tooltip: quickAlarmPickTime)` [quick-alarm-time] in a `ValueChangeHighlight`, the pair inside a `FormIndentedRow(dividerIndent: plain)` | One button to `TimePadSheet.pick` with today's arguments (`:110–133`), after `_blur()` |
| 1 | Presets | unlabelled `FormChipRow(indented: false)` of `quickAlarmIn20Min` [quick-alarm-preset-20], `quickAlarmIn1Hour` [-60], `quickAlarmTonight(time)` [-tonight] | The chosen preset is the selected chip, as today; Tonight is a disabled chip once 21:00 has passed (`FormChip.onTap: null`, §3.7) |
| 2 | Title | `FormTitleRow(leading: EventAvatar(alarm icon, the `other` category's colour), hint: eventTitle)` [quick-alarm-name] | Seeded once with `quickAlarmName` as today; the editor's limit and counter (120, from 100) |
| 3 | Type | the alert sheet's chip row and caption slot, without the full-screen candidate [quick-alarm-type-reminder / -alarm] | Opens on Alarm |
| 3 | Remove after it rings | the alert sheet's switch row [quick-alarm-remove-after] | On by default; parked on the Reminder tier (D11) |

### 3.5 The template form (`EventTemplateEditorSheet`)

`show({initial, draft})` returns `EventTemplate?` as today. The sheet is
rebuilt in place — same class, same file — on `FormSheetFrame`. Chrome:
`close_rounded [template-close] · createTemplate / editTemplate ·
FormHeaderTextButton(save, onPressed: _canSave ? _onSave : null)
[template-save]`. A disabled header action is the shipped primitive's:
`onSurface` at 38 %.

The body is the event editor's own rows — glyphs, labels, order, divider
indents — minus what a template cannot hold. Copy the editor's builders
(§5); never invent a row.

| Group | Row | Primitive | Notes |
| --- | --- | --- | --- |
| capture | Name | `FormTitleRow(leading: EventAvatar, hint: templateName)` [template-name] | Limit 60, counter from 50; autofocus only when creating without a draft; a longer seeded name is kept (today's rule) |
| capture | Category | `FormPickerRow(glyph: label_outlined, label: eventCategory)` [template-category] | `CategoryPickerSheet.pickSingle`. No birthday pre-fill |
| capture | Icon & color | `FormPickerRow(glyph: palette_outlined, label: eventAppearance, valueLeading: the colour dot)` [template-look] | `EventLookSheet.show` with an `EventLookDraft(iconKey, colorValue, tintIcon)`, exactly as the editor calls it (`:1886–1903`). Divider indent 52 |
| capture | Description | a private `_DescriptionRow` from `FormGlyph(notes_rounded)` and `FormChevron` [template-description] | `eventDescriptionAdd` in `onSurfaceVariant` when empty, else the text marker-stripped (`MarkdownPlainText.strip`, which returns the whole text collapsed onto one line, the first meaningful line leading — as built in slice 4), two lines at most with an ellipsis. Money is off in descriptions, so the strip must not read a `$`-led line as a ledger row (slice 5). Opens `EventDescriptionSheet.show(initialText, heading: the name, limit: the event description limit, grandfatheredLength: the length it opened with)`; `null` changes nothing |
| WHEN | All day | `FormSwitchRow(glyph: schedule_outlined, label: eventAllDay)` [template-all-day] | |
| WHEN | Starts | `FormPickerRow(subRow: true, label: eventStarts)` [template-starts] in a `ValueChangeHighlight`, bare as the editor's own Starts and Ends are (a sub-row's indent is the group's 52 fallback, so no wrapper is needed) | Absent while all-day, as in the editor. `TimePadSheet.pick` with `TimePadCaptions.endsAfter` |
| WHEN | Ends | `FormPickerRow(subRow: true, label: eventEnds)` [template-ends], with the `close_rounded` trailing button `eventEndTimeRemove` [template-ends-clear] while an end is set | Value `eventEndTimeNone` or "end · duration" as the editor formats it. `periodAfter` = the start, caption `afterStart`. An end at or before the start is the next day (`:238–242`) |
| WHEN | Repeat | `FormPickerRow(glyph: repeat_rounded, label: eventRepeat)` [template-repeat] | Value as the editor's Repeat row reads it. Opens the Repeat sheet's template variant (§3.6) |
| OCCURRENCES | Count occurrences | `FormSwitchRow(glyph: numbers_rounded, label: eventCountOccurrences)` [template-count], and under it while on the editor's count-style `FormChipRow` with its example caption [template-count-style-numbered / -elapsed] | The group exists only while the rule repeats. The switch is offered only for a kind that carries an interval (the editor's gating). The style follows the kind until the user picks one (the editor's `_countStyleTouched` idiom: yearly defaults to elapsed); a template that arrived counting keeps its style |
| OCCURRENCES | Track presence | `FormSwitchRow(glyph: how_to_reg_outlined, label: eventTrackPresence)` [template-presence], and under it while on the editor's assume chips [template-assume-present / -absent] | |
| OCCURRENCES | Separate description per day | `FormSwitchRow(glyph: event_note_outlined, label: eventPerOccurrenceDescriptions)` [template-per-day] | |
| DETAILS | Priority | `FormMenuRow(glyph: flag_outlined, label: eventPriority)` [template-priority, items template-priority-`1…5`] | As the editor's |

State and encoding:

- The repeat state is one `EventRepeatDraft`. `_repeatOf(rule)` (today's
  `:142–152`, collapsing holidays-only and specific dates to one-time) seeds
  it; a small `_ruleOf(draft)` builds the rule and does not clamp the
  interval. **Until the Repeat sheet's Done returns a draft different from
  the one it opened with, the rule that arrived is written back as the
  object it was** (`_ruleTouched` — a confirmed *change*, not any confirm:
  a Done on an untouched Workdays template must neither drop its stored
  count nor make a clean form dirty), so an interval above 99 or any rule
  the sheet cannot show survives an untouched edit.
- The body is inert while the write is in flight (`AbsorbPointer`): a picker
  opened in that window would become the route the save pops.
- The Ends row's label follows the editor's builder: `eventEnds`, and
  `eventCrossesMidnight` when the end falls on the next day.
- `_buildTemplate` keeps today's encoder (`:246–274`): name trimmed, an
  empty description `null`, all-day → `time` null, the repeat-only flags
  ANDed with "repeats", `assumeAbsent` only while tracking presence,
  `countStyle` and `sortOrder` carried. One addition: a rule the user set in
  this form stores `countOccurrences` only for a kind with an interval; a
  rule that arrived untouched carries its stored flag.
- The repeat-only flags stay parked in the form when the rule goes one-time
  and come back if it repeats again before Save (today's behaviour).
- `_canSave` = name non-empty ∧ not saving ∧ the description within its
  limit (the grandfather rule of the description sheet).
- Dirty = what Save would write now differs from what it would have written
  when the form opened (`_buildTemplate() != _initialTemplate`, taken at the
  end of `initState`; a draft-seeded form opens clean; a repeat changed and
  changed back is clean; a trailing space Save would trim is not dirty —
  the fix round, after the review). `_leave()` serves ✕, back,
  the system back gesture, the barrier and a dismissing drag, asks
  `AppDialogs.confirmDiscard` only when dirty, and returns without popping
  while `_saving` (D12). Save never goes through the guard.
- `_onSave` is today's (`:282–304`): create or update through
  `EventTemplateService`, the `saveStatusError` snackbar on a throw.

### 3.6 The Repeat sheet's template variant

`EventRepeatSheet.show(…, forTemplate: false)`. With `forTemplate: true`:
the Holidays kind row and the Ends row are absent; the "also before the
start date" switch keeps its label and reads
`recurrenceBeforeStartTemplateHint` (yearly keeps
`recurrenceBeforeStartYearlyHint`). Everything else — the kinds' order, the
constant height per opening, the stepper, the weekday row — is the shipped
sheet. The sheet shows whatever weekdays its draft carries: pre-selecting
the start date's weekday is the *editor's* doing (`_initRecurrenceFrom`),
so **the template form passes an empty set** for a rule that is not weekly,
and Done is then disabled on Weekly until one is picked. An end date in the
draft is shown nowhere and handed back untouched; a holidays-only rule
never reaches the sheet, because the form collapses it first. The form
passes today's date as `startDate` and a default `CalendarAppearance`;
neither is shown — the sheet reads the appearance only for its end-date
picker, which the variant never builds, and its weekday row is Monday-first
whatever the week start (corrected in slice 5: the first draft of this
record had the form read the appearance from settings). The editor's own
call is unchanged and `forTemplate` defaults to false.

### 3.7 The primitives (`lib/widgets/form_rows.dart`, slice 1)

| Primitive | What | Notes |
| --- | --- | --- |
| `FormStepperRow` | `label … [−] value [+]` | Hoisted from the Repeat sheet's `_IntervalRow` (`event_repeat_sheet.dart:390–453`) without a visual change: plain indent, `FormTrailingButton`s in `primary`, the value 15 / 500 tabular in a `stepperValueMinWidth` box. Takes `label`, `value` (text), `onDecrement` / `onIncrement` (null disables that button), both tooltips, both identifiers. The Repeat sheet uses it |
| `FormTitleRow` | `[avatar] title field` + counter | Hoisted from the editor's `_buildTitleRow` (`event_editor_sheet.dart:1975–2075`) without a visual change: 56 dp, indent 70, a collapsed multi-line field that refuses a newline, 20 / 500 typed and 20 / 400 hint, the counter line from `counterFrom`. Takes `leading`, `controller`, `focusNode`, `hint`, `maxLength`, `counterFrom`, `counterLabel`, `autofocus`, `textCapitalization`, `onSubmitted`, `identifier`. The editor uses it; its title suite passes unchanged |
| `FormHeroRow` | `[glyph] value / caption ›` | New. One `InkWell`, one button node labelled "value, caption" with the tooltip as its hint; the value at `heroValueSize` / 400 with tabular figures inside a `FittedBox(scaleDown)` so it stays one line at any text scale; the caption 13 / 400; `heroRowMinHeight`; plain indent |
| `FormCaptionSlot` | a caption in a slot as tall as its tallest candidate | New. `candidates:` are laid out invisibly under the shown `child`, the `_DependentGroup` idiom of the Repeat sheet as a widget. Excluded from semantics except the shown child |
| `FormChip` | `onTap` becomes nullable | `null` = 38 %, inert, announced disabled — a disabled chip in place |
| `FormChipRow` | `indented:` (slice 2) | Default `true` is today's shape: the sub-row a switch reveals, inset 52. `false` is a chip row that stands alone — the Custom sub-sheet's units, the quick alarm's presets: left inset `groupInset`, a `rowMinHeight` row with no extra vertical padding, plain divider indent. Added in slice 2 with its `form_rows_test` case; the labelled shape is untouched |
| `FormIndentedRow` | a row wrapper that carries a divider indent (slice 2) | `FormRowGroup` reads the indent only off a `FormDividedRow`, so a row wrapped in a `ValueChangeHighlight` falls back to 52. The editor's private `_IndentedRow` solves that; it is hoisted as `FormIndentedRow(dividerIndent:, child:)` and the editor uses it — an extraction, its suites untouched |

As built in slice 1: `FormStepperRow({label, value, onDecrement, onIncrement,
decrementTooltip, incrementTooltip, decrementIdentifier,
incrementIdentifier})`; `FormTitleRow({leading, controller, focusNode, hint,
maxLength, counterFrom, counterLabel, autofocus, textCapitalization,
onSubmitted, identifier})`, which boxes `leading` in a `rowLeadingSize`
square; `FormHeroRow({glyph, value, caption, tooltip, onTap, identifier})`,
which draws no `Tooltip` widget — the tooltip is the node's hint, so a test
finds the row by id; `FormCaptionSlot({candidates, child})`;
`EventAlert.describe(l10n, event, {formatMinute})`; `AlertOffset.seed(stored,
allDay:)` with `withUnit`, `incremented` / `decremented`, `canIncrement` /
`canDecrement`, `minutes` and `stored` (what the sub-sheet returns).
Since the fix round `FormStepperRow` takes `widestValue`: its box is as
wide as the widest value the caller will show (never under
`stepperValueMinWidth`), measured unseen, so the buttons stand still from
"1 week" to "99 weeks"; and when the label's longest word cannot sit beside
the stepper, the stepper drops under the label, end-aligned — a decision
that follows the locale, the scale and the width, never the value. The
Repeat sheet passes "99 <the unit's longer plural>" per kind and its sizer
stacks the four kinds; the Custom sub-sheet passes its unit's maximum.
`FormTitleRow`, since the same round: the whole row is one opaque tap
target that focuses the field (and brings the keyboard back to a field that
kept the focus under a dismissed one), and the field carries its hint as
its accessible name while it holds text.

`test/widgets/form_rows_test.dart` gains a case per primitive: ids on both
stepper buttons and each disabled independently; the title row's counter
appearing at `counterFrom` and turning to the error colour at the limit;
the hero row's single node and its one line at text scale 2.0; the slot's
constant height across its candidates; the disabled chip's flag and target.

### 3.8 Copy and l10n

New keys, three locales, in the tree since slice 1 (German follows its
neighbours: the sub-sheet's title `eventAlertCustom` is "Eigene"):

| Key | en | de | ro |
| --- | --- | --- | --- |
| `eventAlertCustomItem` | Custom… | Eigene… | Personalizat… |
| `recurrenceBeforeStartTemplateHint` | Also on matching days before the day it is added | Auch an passenden Tagen vor dem Tag des Hinzufügens | Și în zilele potrivite dinaintea zilei în care este adăugat |

Reused as they are: the alert sheet's tier, hint, warning, preset, unit,
stepper-tooltip and sound strings, `eventAlertCustom` (the sub-sheet's
title), `eventDescriptionDone`; every quick-alarm string, `eventTitle` as
the title field's hint; for the template form the editor's keys
(`eventCategory`, `eventAppearance`, `eventLookDefault` / `Custom`,
`eventDescriptionAdd`, `eventSectionWhen`, `eventAllDay`, `eventStarts`,
`eventEnds`, `eventCrossesMidnight`, `eventEndTimeNone`,
`eventEndTimeRemove`, `eventRepeat`,
`recurrenceDoesNotRepeat`, `recurrenceScopeLabel`, `eventCountOccurrences`,
`eventCountStyleNumbered` / `Elapsed`, `eventTrackPresence`,
`eventAssumePresent` / `Absent`, `eventPerOccurrenceDescriptions`,
`eventSectionDetails`, `eventPriority` and the five names,
`eventTitleCount`), with `templateName` as the name's hint and
`createTemplate` / `editTemplate` / `save` / `saveStatusError` as today.

Retired in slice 5, each only after a grep shows no reader left:
`repeatMode`, `repeatOnce`, `eventAllDayHint`, `eventTimeSection`,
`eventTrackPresenceDesc`, `eventCountOccurrencesHint`,
`eventPerOccurrenceDescriptionsDesc`, `recurrenceScopeFromStart`,
`recurrenceScopeHint`, `eventAssumePresentHint`, `eventAssumeAbsentHint`,
`templateNameHint`.

### 3.9 Semantics ids (`lib/constants/semantics_ids.dart`)

Kebab-case, never renamed. Kept: `alert-sheet-save`, `quick-alarm-row`,
`quick-alarm-time`, `quick-alarm-name`, `quick-alarm-save`,
`quick-alarm-remove-after`, `event-alert-add`, `event-alert-remove-after`.
New:

| Surface | Ids |
| --- | --- |
| Alert sheet | `alert-sheet-close` · `alert-type-reminder` · `alert-type-alarm` · `alert-when` · `alertWhenItem(n)` = `alert-when-<n>` · `alertWhenDayItem(n)` = `alert-when-day-<n>` · `alert-when-custom` · `alert-when-day-custom` · `alert-time-of-day` · `alert-sound` · `alert-remove-after` · `alert-remove` |
| Custom sub-sheet | `alert-custom-close` · `alert-custom-done` · `alert-custom-unit-minutes` · `-hours` · `-days` · `alert-custom-less` · `alert-custom-more` |
| Quick alarm | `quick-alarm-close` · `quick-alarm-preset-20` · `-60` · `-tonight` · `quick-alarm-type-reminder` · `quick-alarm-type-alarm` |
| Template form | `template-close` · `template-save` · `template-name` · `template-category` · `template-look` · `template-description` · `template-all-day` · `template-starts` · `template-ends` · `template-ends-clear` · `template-repeat` · `template-count` · `template-count-style-numbered` · `-elapsed` · `template-presence` · `template-assume-present` · `-absent` · `template-per-day` · `template-priority` · `templatePriorityItem(p)` = `template-priority-<p>` |

Flows (slice 6, the next free numbers): `13_alert_sheet.txt`,
`14_quick_alarm.txt`, `15_templates.txt`; `11_tier1_sheets.txt:37–47`
walks the alert sheet by label and is updated in slice 2.

## 4. Behaviour

### 4.1 Must not change

**The alert sheet**

- `AlertEditorSheet.show` — its signature, its six named parameters, its
  three outcomes: `AlertEditorSaved(alert, removeAfterAlert:)`,
  `AlertEditorRemoved()`, `null` (`alert_editor_sheet.dart:21–43`,
  `:109–134`). `AlertEditorSheet.draft` and its minting rules (`:142–168`).
- Save returns `widget.alert.copyWith(…)`: `id`, `eventId` and `enabled`
  pass through; both offset sets always come back, the one not shown
  untouched; the clear flags when `dayMinute` / `sound` are null
  (`:360–372`). An untouched save returns an equal alert
  (`event_editor_redesign_test.dart:1713–1736`).
- The presets (`:178–189`), the custom bounds (`:194–198`, `:322`), the
  unit as a view over minutes (`:45–56`).
- The sound: the sheet with `allowInherit: true`, the picker-missing
  snackbar, the async title, the value kept across a tier flip
  (`:206–209`, `:254–289`); the stored values and the never-silent rule
  (`alert_sound.dart:52–82`).
- Time of day through `TimePadSheet.pick` titled `eventAlertTimeOfDay`, in a
  `ValueChangeHighlight`; `dayMinute == null` follows the setting
  (`event_alerts.dart:61–77`).
- The full-screen warning only on a definite no (`:222–225`, `:296–305`); no
  row is ever disabled for a missing permission.
- The editor's wiring: `_addAlert`, `_editAlert`, `_removeAlert`, the cap of
  five, `_blur`, `_alertPreviewEvent`, the fingerprint, the re-baselined
  default alert (`event_editor_sheet.dart:1377–1444`, `:615–622`, `:1916`,
  `:1937–1938`); the A3 save `_removeAfterAlert && _hasAlarmAlert &&
  OneTimeRecurrence` (`:1659–1664`).
- The settings caller: Removed = no default; the tuples written; the sample
  event; no sound row (`calendar_settings_page.dart:1004–1093`).
- Nothing the UI never touched: `enabled` (the hub's switch), the registry,
  the arm signature (`alert_scheduler.dart:82–91`), the cap
  (`event_alerts.dart:19–21`), the planner, `replaceForEvent`.

**The quick alarm**

- `QuickAlarmSheet.show({day, now})` → `QuickAlarmDraft?`; the sheet touches
  no service (`quick_alarm_sheet.dart:19–46`).
- The defaults: the next quarter hour, the opened day, the Alarm tier,
  remove-after on, the name "Alarm" (`:53–77`). The presets, the day roll,
  a hand-picked time going back to the opened day, Tonight disabled after
  21:00 (`:85–133`, `:266–270`) — all of `lib/utils/quick_alarm.dart`.
- Save: the name's fallback, `removeAfterAlert` only for the Alarm tier
  (`:138–150`); `_quickAlarmBody`'s dispatch, snackbar and Undo
  (`calendar_page.dart:1520–1548`).
- Every entry point: the template picker's row (`quick-alarm-row`, above
  Blank event), the Quick Settings tile and the launcher shortcut end to
  end (`QuickAlarmTileService.kt`, `shortcuts.xml`, `MainActivity.kt`,
  `android_alert_gateway.dart`, `pending_navigation.dart`,
  `quick_alarm_request.dart`, `calendar_page.dart:473–492`, `:1414–1420`).
  The tile's device evidence reads `quick-alarm-save`, "Quick alarm" and
  "Today".

**The template form**

- `EventTemplateEditorSheet.show({initial, draft})` → `EventTemplate?`;
  `initial` wins (`:40–63`, `:106`). The three callers
  (`event_templates_page.dart:52–65`, `event_editor_sheet.dart:1561–1606`).
- The encoder and the save path (§3.5); `EventTemplateService.create` mints
  the id and appends the order, `updateTemplate` keeps both
  (`event_template_service.dart:82–109`).
- The collapse of holidays-only and specific dates to one-time; `buildEvent`
  clearing the repeat-only flags; stamping creates no alerts
  (`event_template.dart:67–97`, `calendar_page.dart:1484–1507`).
- The editor's Save as template: disabled with an empty title, its draft
  mapping, the `templateSaved` snackbar, the editor left as it was.
- The templates page: its rows, its delete through
  `AppDialogs.confirm(isDestructive:)` — Tier 4's surface, untouched here.

**Around them**: the event editor's look and behaviour (it gains two
primitives by extraction and nothing else); the Repeat sheet as the editor
opens it; the Look sheet, the time pad, the category picker, the
description sheet, the sound sheet; the schema, the backup format, every
service.

### 4.2 Deliberately changes

Each of these changes a test on purpose; the slice that makes the change
names the test in its report.

1. **Rows at 38 % instead of absent** (D5): on the Reminder tier the sound
   row and the remove-after switch are present and disabled.
   `alert_editor_sheet_test.dart` and `quick_alarm_sheet_test.dart` assert
   their absence today; those assertions become "present, disabled".
2. **Remove after it rings is parked** (D11): Reminder and back to Alarm
   restores what the switch showed.
3. **Custom writes only on Done**: opening it on "At start" no longer
   rewrites the offset; a value Custom cannot count (90 min, 36 h) is kept
   until Done confirms the clamped one.
4. **One clock** (D7): the Time of day row and every widget's `describe`
   read the phone's 12 / 24-hour setting. `describe`'s default stays the
   neutral 24-hour text, so services and `event_alert_test.dart` are
   untouched; widget tests that read an all-day alert's label change.
5. **Tier order** (D6) in the quick alarm.
6. **Focus is dropped** before the quick alarm's time pad and every picker
   of the template form.
7. **The quick alarm's title takes the editor's limit** (120, counter from
   100).
8. **The template form** (D4, D12): the discard guard; a leave refused
   while saving (slice 0's "today: closing while the write is in flight
   still writes" flips); weekly needs a weekday ("today: Weekly with no
   weekday on still saves" flips); the count-style chips and the yearly
   default ("today: a new template that counts occurrences counts from 1, a
   yearly one included" flips for yearly); Count occurrences no longer
   offered for Workdays and Weekends, a stored one kept on an untouched edit
   ("today: … is offered for every repeating kind" and the two "stores
   Count occurrences" tests are rewritten to say that); the description's
   limit ("today: a description longer than the event editor ever allows
   still saves" flips, a grandfathered one still saves); the debug-only ink
   report gone ("today: a changed time row is reported as hidden ListTile
   ink" is deleted with the robot's counter).
9. **Header actions are text** and the alert sheet's reads Done (D10).
10. **Chips grow above 160 % text** (D14) in every sheet that draws a
    `FormChip`, the editor and the detail sheet included. Nothing changes at
    160 % and below.
11. **The Repeat stepper's two tooltips swap** (slice 5), in the editor's
    Repeat sheet too: minus is "More frequent", plus "Less frequent". It is
    the one change to "the Repeat sheet as the editor opens it" (§4.1).
12. **The title row** (the fix round): a tap anywhere in it focuses the
    field, and the field keeps an accessible name while it holds text — in
    the editor as well, whose title row had both gaps before Tier 2.

One change carries no test edit: with the presets in a menu (D2), "an
offset that matches no chip opens the custom row" now means "Custom… is the
checked item", and the alert robot answers the old question in the new
terms, so the test body stands.

## 5. Facts from the tree (`d501f42`, re-grep before editing)

**Alert sheet** — `lib/widgets/alert_editor_sheet.dart` (751 lines): route
`:109–134` (stock drag handle, factor 0.7); header `:400–428`; tier
`:435–464`; warning `:465–473`, `:296–305`; chips `:475–481`, `:614–672`;
unit and stepper `:482–518`, `:696–751`; time of day `:519–544`,
`:349–358`; sound `:545–570`, `:269–289`; remove-after `:571–586`; Remove
alert `:587–600`; `_draft` `:364–372`, `_save` `:374–378`; `_SectionLabel`
`:675–692`. Callers: `event_editor_sheet.dart:1386`, `:1410`,
`calendar_settings_page.dart:1053`. `describe`: `event_alert.dart:145–175`;
its widget callers `event_editor_sheet.dart:2694`,
`event_detail_sheet.dart:719`, `event_alert_badge.dart:76`,
`calendar_settings_page.dart:1044`, `alerts_page.dart:423`, `:594`.
`EventTimeFormatter`: `lib/services/event_time_formatter.dart`
(`formatMinute(minute, context)` follows the device).

**Quick alarm** — `lib/widgets/quick_alarm_sheet.dart` (347 lines): route
`:32–46` (factor 0.7); header `:172–199`; time `:207–230`, `:110–133`; day
`:231–237`; presets `:239–273`, `:85–108`; name `:275–286`, `:71–77`; tier
`:288–320`; switch `:321–339`; save `:138–150`. Rules:
`lib/utils/quick_alarm.dart`.

**Template editor** — `lib/widgets/event_template_editor_sheet.dart` (776
lines): route `:49–63` (factor 0.92); header `:323–347`; the rows
`:355–668`; `_repeatOf` `:142–152`, `_rule` `:162–173`, `_canSave` `:175`,
the pickers `:196–244`, `_buildTemplate` `:246–274`, `_onSave` `:282–304`;
`_IntervalStepper` `:718–746`, the weekday chips `:748–776`.

**The editor's builders to copy or hoist** —
`lib/widgets/event_editor_sheet.dart`: `_buildTitleRow` `:1975–2075`; the
Category and Icon & color rows `:2840–2864`, `_pickLook` `:1886–1903`; the
WHEN rows `:2487–2575`; the OCCURRENCES rows `:2586–2685` (count style
`:2599–2613`, assume chips `:2620–2635`); Priority `:2883–2903`;
`_countStyleTouched` `:404`, `:456`, `:706–707`, `:1499`, `:1855`;
`_leave` and the fingerprint `:1916–1938`. The Repeat sheet:
`lib/widgets/event_repeat_sheet.dart` — `show` `:100–133`, the kinds
`:264–275`, `_DependentGroup` `:312–388`, `_IntervalRow` `:390–453`,
`_WeekdayRow` `:455–530`. The description sheet:
`EventDescriptionSheet.show` `event_description_sheet.dart:108–116`.

**Tests** — robots `test/widgets/support/alert_sheet_robot.dart`,
`quick_alarm_robot.dart`, `template_form_robot.dart`,
`time_pad_support.dart`; suites `alert_editor_sheet_test.dart` (15),
`quick_alarm_sheet_test.dart` (11), `event_template_editor_sheet_test.dart`
(75), `event_editor_alerts_test.dart` (9), `event_editor_redesign_test.dart`
(72), `event_editor_title_test.dart`, `event_repeat_sheet_test.dart`,
`form_rows_test.dart`, `sheet_bottom_clearance_test.dart` (the three
sheets' cases at about `:426`, `:489`, `:514`),
`calendar_quick_alarm_test.dart`, `event_template_picker_sheet_test.dart`.
Flows: `tool/qa/flows/calendar/04_alerts.txt` (the editor's rows),
`11_tier1_sheets.txt:37–57`. Fixture: `qa-cal-walk` carries five alerts,
`qa-cal-template-legs` is the one template.

**Deleted in slice 5** — in the three sheets: `_SectionLabel`,
`_OffsetStepper`, `_OffsetUnit`'s widget half, `_IntervalStepper`, the
weekday `FilterChip` row, every `Card`, `ListTile`, `SwitchListTile`,
`ChoiceChip`, `FilterChip` and `SegmentedButton`, the three hand-rolled
headers and their height factors (0.7, 0.7, 0.92 as a literal). The Repeat
sheet's `_IntervalRow` and the body of the editor's `_buildTitleRow` already
went in slice 1 — an unreferenced private class is an analyzer warning, so
the gate removes it with the extraction — and the editor's `_IndentedRow`
and everything of the old alert sheet went the same way in slice 2. Slice 5
is left with the quick alarm's and the template editor's remains and the
ARB keys. No generic `AppSpacing` value and no literal
number remains in the four sheet files.

Since slice 1 the editor's lines have moved (about −4 before
`_buildTitleRow`, about −95 after it): `_pickRepeat` 1827, `_pickLook`
1882, `_fingerprint` 1909, `_leave` 1955, `_buildTitleRow` 1971,
`_buildWhenRows` 2377, `_buildAlertRows` 2590; the Repeat sheet's `show`
110, the kinds 273, `_DependentGroup` 327, `_WeekdayRow` 420.

## 6. Slices

### Slice 0 — The safety net (done 2026-10-02)

Tests only. Three robots and a time-pad helper in `test/widgets/support/`;
the alert and quick-alarm suites moved onto their robots with names, order
and expected values unchanged; a new 75-test suite pinning what the
template editor writes. Gate: analyze clean, 6326 passed / 7 skipped / the
known Windows case. Findings in §9.

### Slice 1 — Primitives, ids, copy, the pure rules (done 2026-10-02)

1. `FormMetrics`: the names of §3.1.
2. `form_rows.dart`: `FormStepperRow`, `FormTitleRow`, `FormHeroRow`,
   `FormCaptionSlot`, the nullable `FormChip.onTap` (§3.7), each with its
   cases in `form_rows_test.dart`.
3. The Repeat sheet uses `FormStepperRow`; the editor uses `FormTitleRow`.
   Both are extractions: `event_repeat_sheet_test.dart`,
   `event_editor_title_test.dart` and `event_editor_redesign_test.dart`
   pass unchanged.
4. `EventRepeatSheet.show(forTemplate:)` (§3.6) with its cases in
   `event_repeat_sheet_test.dart`.
5. `lib/utils/alert_offset.dart` (§3.3) with a table suite.
6. `EventAlert.describe`'s optional formatter (D7) and the six widget
   callers of §5 passing `EventTimeFormatter.formatMinute`.
7. `SemanticsIds` (§3.9) and the two ARB keys (§3.8) in three locales.

No sheet changes its look in this slice except through an extraction that
is pixel-equal.

### Slice 2 — The alert sheet and its Custom sub-sheet

First the two primitive items slice 1 showed to be missing (§3.7):
`FormChipRow(indented:)` with its case in `form_rows_test.dart`, and
`FormIndentedRow` hoisted from the editor's `_IndentedRow`, the editor
using it with its suites untouched. Then rebuild `AlertEditorSheet` (§3.2)
and add `AlertOffsetSheet` (§3.3), the old sheet's offset arithmetic
replaced by `AlertOffset`. Rewrite `AlertSheetRobot` for the new UI; the suites' bodies change only
for §4.2 items 1–4 and 9. New cases: the Custom sub-sheet's Done / cancel
paths and its seeding; the caption slot's constant height across the tier
and the late warning; German at text scale 2.0 and a 360 × 780 surface; the
clearance test gains the sub-sheet and keeps the sheet. Update
`11_tier1_sheets.txt` for the chips and the Done action.

### Slice 3 — The quick alarm

Rebuild `QuickAlarmSheet` (§3.4). Rewrite `QuickAlarmRobot`; bodies change
only for §4.2 items 1, 2, 5, 6, 7 and 9. New cases: the hero row's single
line at text scale 2.0, German at 2.0 and 360 × 780, the disabled Tonight
chip in place, focus dropped before the pad.
`calendar_quick_alarm_test.dart` passes unchanged.

### Slice 4 — The template form

Rebuild `EventTemplateEditorSheet` (§3.5) on `FormSheetFrame`. Rewrite
`TemplateFormRobot`; the 75 bodies change only for §4.2 item 8. New cases:
the guard on every way out, clean and dirty; a leave ignored while saving;
the description row's three states and its round trip through the
description sheet; the Repeat variant's round trip and an untouched rule
written back as it came; German at 2.0 and 360 × 780; the clearance case.

### Slice 5 — Delete the old UI and the dead keys

Everything §5 names that is still in the tree, each after a grep for its
last reader; the twelve ARB keys of §3.8 in three locales, `gen-l10n`,
`untranslated.txt` `{}`. One consolidation: the event title's limit and
counter threshold (120, from 100) exist twice since slice 3, as the editor's
private statics and as the quick alarm's — they become one named pair in
`lib/constants/` that both read, the editor's suites untouched.

Two defects a read-only review of slice 3 confirmed, both in shared pieces
(§9), fixed here with a test each:

1. **`FormHeroRow` changes height with the value's length once it is
   fitted.** `FittedBox(scaleDown)` sizes its box to the child's aspect
   ratio, so a wider time makes a shorter row: on a 12-hour phone at large
   text (from about 1.36× on a 360 dp phone) "9:30 AM" → "10:20 AM" drops
   the row by about 9 dp at 2.0 and everything under it jumps, under the
   finger that tapped a preset. The primitive reserves the scaled line for
   the fitted value — the row's height depends on the text scale and never
   on the string. Test: 09:20, text scale 2.0, 360 × 780, In 1 hour; the
   preset chips' rects do not move. The quick alarm's "one line at 2.0"
   test also asserts the fit, not only the line count.
2. **A header hairline that stays on after the content shrinks.** The
   `scrolled` notifier is fed only by the scroll controller's listener, and
   a `SingleChildScrollView` corrects its offset silently when the content
   gets shorter (the keyboard closing). One shared helper feeds the notifier
   from scroll metrics changes too; the quick alarm, the template form, the
   alert sheet and the Custom sub-sheet use it. Test: keyboard inset up,
   drag the body, inset down, the hairline is off. The shipped sheets that
   copy the old listener are long forms whose offset stays above zero; they
   move to the helper when a change opens them (the master's retire list).

And one cosmetic: the hero row's `ValueChangeHighlight` takes the group's
radius, so its flash is not shaved at the group's top corners.

Five more that slice 4 turned up:

3. **The Repeat stepper's tooltips are inverted.** `recurrenceIntervalDecrement`
   reads "Less frequent" and `recurrenceIntervalIncrement` "More frequent"
   in all three locales, but a smaller interval is a *more* frequent event —
   a screen reader announces the opposite of what each button does. The two
   texts swap in the three ARBs; the keys keep their names. Tests that tap
   a button by its tooltip text follow.
4. **A typed name sits over a blank line at 200 %.** A two-line hint
   ("Vorlagenname" at 200 % on 360 dp) keeps its height after the name is
   typed, because an `InputDecoration` maintains its hint's size by default.
   `FormTitleRow` turns that off, so the field is as tall as what it shows.
   The editor's one-line "Title" hint is unaffected.
5. **One colour dot.** The editor's private `_ColorDot` (a literal 10) and
   the template form's own dot on `FormMetrics.valueDotSize` become one
   primitive both use.
6. **A dead settings read.** The template form reads the calendar
   appearance only to hand it to the Repeat sheet, whose template variant
   never opens the date picker that needs it. It passes a default
   `CalendarAppearance` instead.
7. **`MarkdownPlainText.strip` reads a `$`-led description line as a ledger
   row**, so a template description starting "$= 500" previews as "500".
   The strip gains a switch for callers whose text has no ledger (the
   `markdown-engine` skill; one grammar, extended, never a second scanner),
   and the template's description row uses it.

### Slice 6 — Device pass, review, docs

1. **Device pass** through the `qa-emulator` skill on the Pixel emulator:
   `tool\qa\qa.cmd run --fresh --seed tool/qa/fixtures/calendar.json`, then
   `$env:ANTA_QA_VIA = 'agent'` and `qa flows calendar` — the thirteen
   saved flows green before anything else, then the three new ones
   (`13_alert_sheet`, `14_quick_alarm`, `15_templates`); the matrix `qa set
   theme=dark locale=de text-scale=2.0` with every board of the canvas shot
   beside it; a cold start in dark to check the navigation bar's colour
   (the 2026-10-02 walk saw it stay light after a runtime theme switch);
   the Quick Settings tile's path to the quick alarm; the Custom
   sub-sheet's opening for a dropped frame (its sizer lays out up to 112
   unseen lines once); the Repeat sheet's stepper in German at 200 % with a
   two-digit interval ("12 Wochen" in the rigid value box); the editor's
   count-style and assume chips at 200 % (grown, not cut — no permanent test
   covers them there); `qa errors` clean; `qa set theme=light locale=system
   text-scale=off` at the end.
2. **Independent review** by a fresh `fable-max` that has not seen this
   session: this record and the diff, confirmed defects only; fix what it
   confirms, re-run the gate.
3. **Docs in the same change**: an addendum in
   `docs/calendar-events-feature.md`; `COPILOT_CONTEXT.md`'s calendar
   sections; the rule lines in `calendar-events`, the new primitives in
   `ui-language`'s table, the new ids in `calendar-ui`'s catalogue, the
   flow count in `qa-emulator`; `calendar-language-adoption-roadmap.md` §9;
   this record's status line and §9.

## 7. Definition of done

1. For the same input each sheet returns what its old version returned:
   every robot-driven test passes with its body unchanged, except the
   bodies §4.2 names.
2. Alert sheet: the tier, a preset, Custom, the time of day, the sound and
   the switch each round-trip through Done from both callers; ✕, drag, back
   and the barrier return `null`; Remove alert returns Removed; the sheet's
   height is the same on both tiers and before and after the permission
   answer.
3. Custom sub-sheet: 45 minutes from "At start" is confirmed only by Done;
   changing the unit keeps the number, clamped; the stepper stops at each
   unit's bounds with the button disabled in place.
4. Quick alarm: opens on the next quarter hour, today, Alarm, the switch
   on; a preset, a hand-picked time, a typed title and a tier each reach
   the saved event; Tonight is disabled in place after 21:00; the tile
   opens it on today.
5. Template form: create, edit and the Save-as-template draft each store
   what §3.5 says; an untouched edit writes the template back unchanged; a
   dirty form asks on ✕, back, the system back gesture, the barrier and a
   drag; a clean one leaves silently; a leave during the write is ignored.
6. One-handed at 360 × 780: every chip, stepper button, switch and row has
   a 48 dp target.
7. Light and dark; en, de and ro; text scale 1.3 and 2.0 with no clipped
   label and no overflow; the hero time on one line at 2.0.
8. Keyboard up and down in the quick alarm and the template form: the
   clearance rule holds, nothing shifts, nothing sits under the navigation
   bar.
9. Every string through `AppLocalizations` in three ARBs;
   `untranslated.txt` `{}`.
10. One semantics node per row; every id of §3.9 seen on its control in a
    device dump; tooltips on every icon button.
11. Nothing §5 lists for deletion is referenced; no literal number and no
    generic `AppSpacing` value in the four sheet files.
12. The thirteen saved flows and the three new ones green; `qa errors`
    clean after the matrix.

## 8. Deferred

- **A typed custom offset** (digits, then the unit as the finishing key, in
  the time pad's manner). The stepper keeps today's bounds.
- **Template alerts** — the v41 half of the alerts roadmap's session 6; a
  template still stamps an event with no alert.
- **The templates page** (`pages/event_templates_page.dart`): its `Card`
  rows, its delete confirm and a reorder for `sortOrder` are Tier 4.
- **The confirm dialog's style**: the open app-wide decision 2 of
  `docs/ui-language-adoption-roadmap.md`. No Tier 2 sheet shows a
  destructive confirm.
- **`templateSummary`** (`event_template_summary.dart:31`) still prints a
  24-hour range on the templates page and in the template picker: a text
  composed without a context, to take with Tier 4's page.
- **The two-line header at 200 %**: still the owner's open call from Tier 1;
  "Erinnerung" and "Vorlage bearbeiten" ellipsize in one line.
- **Count occurrences on a stored Workdays or Weekends template**: kept
  when untouched, no longer offered. Whether such an event should count at
  all is the editor's question, not this tier's.
- **Seven days, two wordings**: the When menu says "A week before", every
  row that describes the alert "7 days before, 9:00 AM" (`describe`, pinned
  by `event_alert_test.dart`). A copy question for the owner.
- **The quick alarm rides the keyboard.** It is content-tall with a text
  field, so focusing the title grows the sheet up to its clamp and its top
  edge moves, as the category picker's does with its search field; the old
  fixed 0.7 box did not. Accepted with the sub-sheet shape; the form box
  would leave a blank lower third.
- **The Custom sub-sheet's first frame** is 35–42 ms in a debug build on the
  emulator (its sizer lays out every read-back line once). To watch in a
  release build on a phone, not to tune blind.
- **Two handles at 200 %**: a sub-sheet at its clamp ends about 17 dp under
  the editor's top, so the editor's handle shows above it. Every sub-sheet
  at the clamp has done this since Tier 1.
- **Found by the device pass and not the calendar's alone**, recorded in
  `docs/ui-language-adoption-roadmap.md` §8: the system navigation bar stays
  light in dark theme, cold start included; the discard dialog's title
  breaks mid-word in German at 200 %; the description sheet's editing text
  does not follow the text scale and its markdown bar offers the money
  shortcuts although money is off in descriptions.
- **The boards' new template** draws All day off with a 9:00 AM start; the
  form opens all-day, as the old editor did (`time == null`). The board was
  wrong, the behaviour is unchanged.

## 9. Ledger

| Slice | Date | Result |
| --- | --- | --- |
| 0 | 2026-10-02 | **Done, uncommitted.** Robots `AlertSheetRobot`, `QuickAlarmRobot`, `TemplateFormRobot` and `time_pad_support.dart`; four suites moved onto them unchanged in name, order and expectation (one read became stricter: the quick alarm's "Today" is now read from the sheet's own line, not from either the sheet or the pad); `event_template_editor_sheet_test.dart`, 75 tests. Gate: `dart analyze lib test` clean; `flutter test` 6326 passed / 7 skipped / the known Windows case. **Found while pinning, each pinned under a "today:" name**: the time rows' `ValueChangeHighlight` sits between a `ListTile` and its `Material`, which Flutter reports in debug builds as invisible ink (the robot counts and drops exactly that report); a close during an in-flight save still writes; weekly saves without a weekday; no count-style control, so a yearly template counts from 1; Count occurrences is offered and stored for Workdays and Weekends, which the editor's own Save as template refuses; no description limit; an interval above 99 that arrives with a template is kept. **Seen, not pinned** (the alert and quick-alarm suites were to stay as they were): opening Custom on "At start" rewrites the offset to one minute; an offset Custom cannot count opens with a clamped number beside a label reading the true one; the quick alarm's switch does not come back after a round trip through Reminder |
| 1 | 2026-10-02 | **Done, uncommitted.** `FormStepperRow`, `FormTitleRow`, `FormHeroRow`, `FormCaptionSlot`, the nullable `FormChip.onTap`; seven `FormMetrics` names (the four planned and the title row's three); the Repeat sheet on `FormStepperRow` and the editor on `FormTitleRow`, both proved equal to the old rows pixel for pixel and node for node in a throwaway comparison over 120 stepper and 84 title states (light and dark, 360 and 412 wide, text scale 1.0 / 1.3 / 2.0); `EventRepeatSheet.show(forTemplate:)`; `lib/utils/alert_offset.dart`; `EventAlert.describe`'s optional `formatMinute` with the six widget callers passing the device's clock; the 45 ids of §3.9; two ARB keys in three locales. Gate: `dart analyze lib test` clean; `flutter test` 6384 passed / 7 skipped / the known Windows case (58 added: `form_rows_test` 23, `event_repeat_sheet_test` 11, `alert_offset_test` 17, `event_alert_test` 4, one each in the badge, detail-sheet and alerts-page suites); `untranslated.txt` `{}`. **Expectations changed on purpose** (§4.2 item 4, the editor's alert row now reads the phone's clock): four strings in `event_editor_alerts_test.dart` and one in `event_editor_redesign_test.dart`, "On the day, 09:00" → "On the day, 9:00 AM" and "The day before, 09:00" → "The day before, 9:00 AM". **Deviations**: German `eventAlertCustomItem` is "Eigene…", after its neighbours; `_IntervalRow` and the old title-row body were deleted here, not in slice 5. **Found**: a standalone chip row and a highlighted row's divider indent were unspecified — §3.7 now carries `FormChipRow(indented:)` and `FormIndentedRow`, built first thing in slice 2. Until slice 2 lands, the editor's alert row is 12-hour on a 12-hour phone while the old alert sheet still prints 24-hour |
| 2 | 2026-10-02 | **Done, uncommitted.** `AlertEditorSheet` rebuilt as §3.2 on the sub-sheet chrome; `AlertOffsetSheet` (new) on the pure `AlertOffset`, the old sheet's arithmetic, `_OffsetUnit`, `_SectionLabel` and `_OffsetStepper` gone; `FormChipRow(indented:)` and `FormIndentedRow` (the editor's `_IndentedRow` hoisted, the editor using it); `FormChip`'s height a minimum (D14); `AlertSheetRobot` rewritten, every tap by id. Gate: `dart analyze lib test` clean; `flutter test` 6463 passed / 7 skipped / the known Windows case (79 added: `alert_editor_sheet_test` 15 → 60, `alert_offset_sheet_test` 24 new, `form_rows_test` 64 → 72, one each in the clearance and the editor-alerts suites). **Expectations changed on purpose**, both §4.2 item 1 in `alert_editor_sheet_test.dart`: "the remove switch is offered for an alarm and rides the result" and "the Sound row belongs to the alarm tier alone" now read present-and-disabled on the Reminder tier where they read absent. No body changed in `event_editor_redesign_test.dart` or `event_editor_alerts_test.dart`. **Corrected against the record**: the remove-after result (D11 — a literal `false` on the Reminder tier would have disarmed an event whenever a reminder was edited beside an alarm; the flag is handed back unless this sheet demoted the alarm); the sub-sheet holds one height, sized over every line its read-back can say (112 for a timed event, 30 for an all-day one — laid out unseen once, a cost the device pass watches); the read-back is the caller's wording (`readBack`), so the sub-sheet and the When row agree on "The day before"; the header hairline (`scrolled:`) is wired on both sheets; Starts and Ends need no indent wrapper. **Found**: the chip clipping at 200 %, fixed the same day as D14 and measured in a throwaway render (German, 2.0, 360 × 780: label 40, chip 40, target 48 for the Type chips, the units, the detail sheet's presence chips and the editor's count and assume chips; the editor's chips at 2.0 have no permanent test). **Unrun**: `11_tier1_sheets.txt`, updated to the new ids, until the device pass |
| 3 | 2026-10-02 | **Done, uncommitted.** `QuickAlarmSheet` rebuilt as §3.4; the Type row extracted into one shared widget, `lib/widgets/alert_type_row.dart` — `AlertTypeRow({mode, onChanged, reminderIdentifier, alarmIdentifier, alarmWarning, showAlarmWarning})` — used by both sheets and proved equal to the alert sheet's inline row over 216 states; `QuickAlarmRobot` rewritten, every tap by id. `show`, `QuickAlarmDraft`, the defaults, the presets, the day roll, the name's fallback, the pad's four arguments and `lib/utils/quick_alarm.dart` untouched; `calendar_quick_alarm_test`, `event_template_picker_sheet_test` and `utils/quick_alarm_test` pass unedited. Gate: `dart analyze lib test` clean; `flutter test` 6503 passed / 7 skipped / the known Windows case (40 added: `quick_alarm_sheet_test` 11 → 42, `alert_type_row_test` 9 new). **Expectation changed on purpose**, §4.2 item 1: "the reminder tier hides the switch and never removes" is now "… dims the switch in place and never removes"; the other ten bodies are byte-identical. **Mutation-checked**: removing the focus drop, the parked value or the seed guard fails four tests; removing the caption slot fails eight across three suites. **Notes**: the tile's "Today" is still drawn but is now part of the hero row's one node ("10:15 AM, Today") — a substring match finds it, an exact-label match would not; the three presets take two lines at 360 dp in every locale and one line at 390 and 412 in English and Romanian; the title's 120 / 100 are a named pair in the sheet beside the editor's private one (slice 5 makes them one); "Schnellalarm" ellipsizes at 200 %, the open header question of §8. Nothing of the older chrome is left in the file for slice 5. **Reviewed the same evening** by a read-only `fable-max` the implementer had launched: §4.1 held line by line against `HEAD`, the extraction was equivalent in all six states, the ten untouched bodies were byte-identical to their saved copies, and no test was found that cannot fail. It **confirmed two defects in shared pieces**, both by reading and both scheduled into slice 5: the hero row's height follows the time's length once the value is fitted (a 12-hour clock at large text only), and a header hairline stays on after the keyboard closes over a body that no longer scrolls. It also noted, as pre-existing and protected: Tonight picked at 20:59 and saved after 21:00 rolls to tomorrow, as on `HEAD` |
| 4 | 2026-10-02 | **Done, uncommitted.** `EventTemplateEditorSheet` rebuilt in place as §3.5 on `FormSheetFrame`: the editor's rows, the description row, the Repeat variant, the Look sheet, the time pads, the guard; nothing of the old chrome left in the file. `TemplateFormRobot` rewritten and stateless — a Repeat or Look action opens the sub-sheet, makes its change, taps Done and reopens it, so each legacy call still changes the form at once. One new metric, `valueDotSize`. Gate: `dart analyze lib test` clean; `flutter test` 6620 passed / 7 skipped / the known Windows case (`event_template_editor_sheet_test` 75 → 191, the clearance suite +1). **Flipped on purpose**, every one §4.2 item 8: the close during a write (now refused, the save returns its template); weekly without a weekday (cannot be confirmed); the count style (three tests: numbered / numbered / elapsed by kind); Count occurrences offered only for a kind with an interval, a rule set here to Workdays or Weekends storing none, a stored one kept while its rule is left alone (four tests for two); the description limit, a grandfathered one still saving; the ink report deleted with the robot's counter, replaced by "raise no framework error". Two more bodies gained one line each and were accepted: "the system back returns null and writes nothing" now answers the discard question, and "the interval cannot go over 99" opens the Repeat sheet first. **Mutation-checked**: ten mutations, each caught. **Beyond the record, kept**: the body inert while the write is in flight; three caller tests (the templates page creating and editing, the editor's Save as template end to end), paths that had none. **Corrected against the record**: `_ruleTouched` means a confirmed change; `_ruleOf` does not clamp; the Ends label switches to "Ends next day"; `strip` returns the whole text, not a first line; a template that arrived not counting keeps its dormant style. **Found for slice 5**: the inverted stepper tooltips, the blank line under a typed name at 200 %, two colour dots, a dead appearance read, `$`-led descriptions previewing as ledger rows. **Seen, not Tier 2's**: `resetToDefault` is twice in `app_en.arb`; the header title ellipsizes at 200 % ("Vorlage…") |
| 5 | 2026-10-02 | **Done, uncommitted.** Nothing of the old chrome was left to delete: slices 1–4 had removed it with their rebuilds (grep-verified in the five sheet files). The twelve keys of §3.8 removed from the three ARBs, none with a reader left; `gen-l10n` run, `untranslated.txt` `{}`. `lib/constants/event_title.dart` (`kEventTitleMaxLength`, `kEventTitleCounterFrom`) read by the editor and the quick alarm. The two review defects: `FormHeroRow` holds its line open with one digit laid out at full size and never drawn, and fits the value inside it (a line *computed* as scale × 46 is not what the text engine lays out — 59.8 against 60 at 1.3 — so a value that fits would have been scaled by a hair); `FormHeaderHairline` (`scrolled`, `watch({child})`, `dispose`) feeds the header's hairline from scroll and scroll-metrics notifications at depth 0 on the vertical axis, used by the four Tier 2 sheets, which no longer own a scroll controller. The hero row's highlight on the group's radius. The stepper tooltips swapped in three locales; `FormTitleRow` with `maintainHintSize: false`; `FormValueDot` used by the editor and the template form; the template form's appearance read removed (confirmed: the Repeat sheet reads `appearance` only for its end-date picker, which the variant never builds); `MarkdownPlainText.strip(money:)`. `FormMetrics.valueMaxLines` names the two-line clamp `FormLabelValue` and the description row share. Gate: `dart analyze lib test` clean; `flutter test` 6644 passed / 7 skipped / the known Windows case (24 added). **Existing expectations changed**: the three stepper tests in `event_repeat_sheet_test.dart` follow the tooltip swap and tap the same buttons; the quick alarm's "one line at 2.0" gained the fit; and one not foreseen — the template suite's "every control keeps a 48 dp target" at 360 × 780 no longer measures the name *field*, which had passed only because its hidden hint wrapped to two lines in the test font: the field is one 26 dp line in its 56 dp row, in the editor and the quick alarm too, and a tap beside the text focuses nothing (taken to the fix round). **Mutation-checked**: twelve mutations, each caught. **Seen**: the alert sheet's Time of day highlight still has the default radius on a group's last row; `_defaultStartMinute` / `_defaultDurationMinutes` exist in the editor and in the template form |
| 6 · review | 2026-10-02 | **Independent review** by a fresh read-only `fable-max` (the working tree against `d501f42`, no Flutter command run). **No defect in what a sheet returns or stores**: the alert sheet's `show`, `draft`, `_draft`, the presets, the sound and permission blocks and `_pickDayMinute` against `HEAD`; remove-after over twelve paths, differing only where Alarm → Reminder → Alarm now restores the value; `AlertOffset` against the old arithmetic; no diff at all in `_addAlert`, `_editAlert`, `_removeAlert`, the A3 save, `_quickAlarmBody`, the templates page or Save as template; the quick alarm's defaults, presets, day roll and `_save`; the template encoder field by field and `_ruleTouched` in every case of §3.5; every row of §3.2–§3.6; all ids unique and on the right nodes; the extractions equivalent; the ARBs consistent in three locales with no reader left for a retired key; no test found that cannot fail. **Three confirmed defects, all in the rebuilt UI**: the title row's tap target is one text line (the quick alarm and the template form lost the full-height outlined fields they had; the editor has had the gap since its redesign); the title field has no accessible name once it holds text (the same two had `labelText`); the template form asks to discard after a repeat was changed and changed back. **Gaps**: nothing drove the settings caller (closed by the flow `16_alert_defaults.txt`); the quick alarm's "… and back on again" never turned the switch back on. All five went to the fix round |
| 6 · device | 2026-10-03 | **Device pass** on the Pixel emulator (427 × 952 dp, the current tree built fresh). `qa flows calendar`: 13 / 13 before the new flows — `11_tier1_sheets.txt` passed as slice 2 had updated it blind, `04_alerts.txt` unchanged — then **17 / 17** with `13_alert_sheet`, `14_quick_alarm`, `15_templates` and `16_alert_defaults` (the settings caller: no sound row, no remove-after row, a preset read back on the settings row, the all-day default's Time of day, both restored to none). Every id of §3.9 on its control in the dumps of three cells (light default, dark German 200 %, light Romanian 130 %). Colours equal the boards'. **Checks**: the Quick Settings tile opens the sheet on today with `quick-alarm-save`, the title and "12:15 AM, Today"; the hero row's neighbours do not move from "9:30 AM" to "10:20 AM" at 200 %; the header hairline goes off when a 300 dp inset is cleared; "12 Wochen" fits its box; the editor's count and assume chips are whole at 200 %; no blank line under a typed name; Custom from "At start" opens on one minute and a cancel writes nothing; the stepper stops at 59 / 23 / 30 with its button disabled in place. The Custom sub-sheet's first frame is 35–42 ms in a debug build (the sound sheet's is 8–9 ms): two frame intervals at the start of the slide-in. **Found**: Calendar settings goes blank in German at 200 % (a trailing `DropdownButton` consumes its tile — not a Tier 2 file, but on the way to two Tier 2 surfaces); the default-alert rows are unreadable at large text once a default is set; the Repeat stepper's label breaks mid-word in German at 200 %; "Template saved" is drawn under the editor sheet; Romanian offsets are lowercase beside capitalised neighbours; the title row's tap target, as the review said. All went to the fix round. **Recorded, not Tier 2's** (§8): the system navigation bar stays light in dark theme, cold start included; the discard dialog's title breaks mid-word in German at 200 %; the description sheet's text does not follow the text scale and its bar offers the money shortcuts. `qa errors` at the end: three `E/AccessibilityBridge … transform has not been initialized` lines from scrolling Calendar settings with semantics on — engine noise, added to the tool's known-noise list in the fix round |
| 6 · fixes | 2026-10-03 | **The fix round, done, uncommitted.** `FormTitleRow`: the whole row is one opaque tap target that focuses the field (and brings the keyboard back to a field that kept focus under a dismissed one), and the field carries its hint as its accessible name while it holds text — in the editor, the quick alarm and the template form; the template suite's 48 dp check measures the row's tap surface again. The template form's dirty check is "what Save would write now differs from what it would have written at open" (a repeat changed and changed back is clean; a stored Workdays count whose rule was changed and changed back still asks). `FormStepperRow.widestValue`: the box as wide as the widest value, measured unseen, the buttons still from 1 to 99; the stepper drops under a label whose longest word cannot sit beside it (German 200 %), by locale, scale and width, never by the value; the Repeat sheet's sizer stacks the four kinds at their ceiling. "Template saved", the alert sheet's "no sound picker", the template form's "Save failed" and the two filter sheets' messages are raised through `OverlaySnackbar` above their sheets (the overlay bar now owns a cancellable timer, removes idempotently, is a live region) — every one had been drawn on the page under its sheet. Calendar settings: a private tile whose trailing yields to the title (the title's longest word measured first; the trailing takes what is left, or moves under the description when under 96 dp) on the Holiday set row (a capped, ellipsized dropdown whose menu wraps whole names), the two default-alert rows and the Alarm sound row — the page lays out in German at 200 % and both default rows keep their titles; a new suite, `calendar_settings_large_text_test.dart`, pumps the real page at that size and proves the stock tile at 1.0. The Time of day highlight on the group's radius. Romanian: the three timed offsets and the all-day day-count capitalised like their neighbours. "The switch off is reported, and back on again" completed. The engine's `AccessibilityBridge … transform has not been initialized` line on the QA tool's known-noise list, narrowly, with its case. Gate: `dart analyze lib test tool test_driver` clean; `flutter test` 6665 passed / 7 skipped / the known Windows case (21 added over the round and its follow-up); `untranslated.txt` `{}`. **Existing bodies changed**: the stepper's "label wraps beside a bare number" case replaced by the drop rule (C); the quick alarm's "… and back on again" completed (H); the template 48 dp case measures the tap surface (A1); one hit-testable assertion appended to the category-filter suite's "the bookmark saves the draft". **Left, recorded in the master's §8**: the category editor, palette, colour picker, removed-holidays and pairing sheets still raise their messages under themselves; the Holiday set row in German and Romanian at normal text had squeezed its title before this round and now caps its dropdown instead — the owner may look at that row |
| 6 · re-check | 2026-10-03 | **Device re-check** of the fix round on the rebuilt tree: `qa flows calendar` **17 / 17**, `qa errors` clean on all three sources with the engine line hidden as known noise. Yes on every check: Calendar settings lays out in German at 200 % (the Holiday set row, both default rows with the all-day default set, the Alarm sound row, the alert sheet from that page); the default rows in English at 200 % keep their titles whole with the value beside them; the Repeat sheet in German at 200 % holds "Wiederholen alle" whole on its own line with the stepper under it and the minus button at the same x from 1 to 12, "12 Wochen" whole in a fixed box; "Template saved" over the editor and "Saved as …" over the Filters sheet; a tap above, below, right of or on the avatar of the title row focuses the field in the quick alarm, the template form and the editor, and the nodes read `EditText "Title" text="Alarm"`, `"Template name" text="Leg day"`, `"Title" text="Lifting session"`; every Romanian When item capitalised, the editor's row "Cu 2 zile înainte, 09:00" and the Custom read-back agreeing; the Holiday set row at 1.0 in three locales with the dropdown capped at about 60 % of the row and nothing squeezed. **Still wrong at German 200 % on the settings page**, taken to a last round: a set default's value that needs three lines beside its title is clipped by `ListTile`'s 56 dp trailing cap ("Alarm · 7 Tage vorher, 09:00" loses its "09:00"; the Alarm sound row loses "Telefons"), and the capped rows' subtitles break mid-word because the width check measured the title's longest word only. **Seen once, not Tier 2's**: after saving a preset from the saved-filters sheet its new row's ⋮ did nothing until another menu had opened and closed, and the sheet then moved up |
| 6 · settings | 2026-10-03 | **Two last rounds on the settings tile** (`_YieldingTile`, `calendar_settings_page.dart`), after the re-check: the text column's longest word is measured over the title *and* the subtitle, so a capped row no longer breaks its description mid-word; and a value stays beside the title only while its laid-out height fits the trailing cap a `ListTile` hands its trailing — `listTileTrailingCap(context)`, the SDK's private 48 / 56 plus the density term, pinned by a test that reads the real constraint off a laid-out tile at the phone's density and the desktop's — otherwise it goes under the description, uncut. At 1.0 and 1.3 two lines fit and nothing moves; at 200 % every value that wraps goes under. `calendar_settings_large_text_test.dart` asserts every value row uncut in German at 2.0, the placement rule at 2.0 and at 1.0, and the cap. Gate: `dart analyze lib test tool test_driver` clean; `flutter test` **6669 passed / 7 skipped / the known Windows case**; `untranslated.txt` `{}`. The whole tier added 418 tests over the baseline of 6251 |
