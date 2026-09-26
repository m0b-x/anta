# Event Detail Sheet Redesign — Roadmap & Slice Prompts (2026-09-26)

**Status: SHIPPED 2026-09-26** (uncommitted on top of `88b043e`; the owner
reviews and commits). Slices 1–4 are done: the shared primitives and numbers,
the sheet, the retired keys, the tests, the device pass on the iOS simulator
and the Android emulator, the independent review, and the docs
(`calendar-events-feature.md` §6.2 + the 2026-09-26 addendum,
`COPILOT_CONTEXT.md`, the `calendar-events` and `calendar-ui` skills). Line
numbers in §5 are as of `88b043e`.

**Deviations from this document, and why** (the full account is the feature
doc's addendum):
- The next-occurrence scan starts the day **after** the opened occurrence
  (today for a past one), never from today: on the device pass, opened on
  today's occurrence, the Date row and the Next occurrence row both said
  today. `_maxOccurrences` is 4, the next plus the caption's three. E7 and
  §4.1 were amended in place.
- The description cell's lines are 23.25 px, not 22 (E6): the shared
  markdown builder pins `MarkdownConstants.lineHeight` in every span style;
  the fix (a `lineHeight` on `LineMarkdownStyle`) belongs to the markdown
  engine and is deferred (§8). Nothing moves in place — the editor's cell and
  this one sit on different routes.
- `FormSheetHeader` caps its trailing slot at `FormMetrics.headerActionMaxShare`
  (0.6) and `FormHeaderTextButton` ellipsizes on one line, as does the
  editor's Save label: the new suite's German-at-2.0-on-360 case overflowed
  the header by 9 px under the test font (a 28 px "Bearbeiten" beside the
  48 dp close button). Real labels sit well under the cap.
- `FormPickerRow` wraps an id-less row in `MergeSemantics` so every read row
  is one announcement (§7.8); rows with an id were already merged by
  `AutomationId`.
- The Android pass ran as well as the iOS one (both through the agent
  layer); its error buffer carried pre-existing, debug-only precision
  assertions from `table_calendar`'s month pager, none from this sheet.

**Independent review (fable-max, 2026-09-26): six confirmed findings, all
resolved** — the empty description cell's target was only as wide as its
words (a loose `Stack`; now `StackFit.passthrough`, one merged button node,
a test tapping between the words and the pencil); the Time row had drifted
from §3.3's `formatRangeOfContext` to the neutral 24-hour skeleton while
the alert rows and the editor honour the device's clock (restored, the
widget harness pinned to a 24-hour `MediaQuery`); `_resolveNoteTitle` had
been inserted under `_openLinkedNote`'s doc comment (moved); the note lookup
awaited unguarded (a throwing resolver now leaves the loading state); the
line-height deviation above (recorded); the presence test never checked
that the adherence line moved (it does). Nits fixed alongside. The reviewer
read the code only — a QA run was up, so it did not execute the suite; the
whole suite ran green after its fixes.

Design source: the canvas **"Event editor layout"**, page **Detail sheet**,
the boards labelled **D** — https://claude.ai/artifact/398RMNqUHLc2TtCTKhoCow.
The second row holds the alternatives behind the open questions (Q1 B, Q3 B,
Q2 B); they are history. Every board is 412 dp wide; a tall board's dashed
line marks where a 915 dp screen ends.

| Board | File | Shows |
| --- | --- | --- |
| D · Recurring event, opened from the day panel | `DEdit` | the hero: "Leg day", the description with tasks, WHEN with Date / Time / Repeat / Start date / Next occurrence, OCCURRENCES with the presence chips and Skip this day, one reminder with its next fire, Priority High, a linked note |
| D · One-time event: the sheet is as tall as its content | `DOnce` | "Dentist": no description (placeholder), Date, Add date, Time, an alarm; the month grid stays visible behind the short sheet |
| D · Yearly, counting | `DBirthday` | Date with the age, All day, Yearly, Start date, Next occurrence with the next age, Skip this day alone in OCCURRENCES, an all-day reminder, Priority Highest |
| D · Pinned dates (Physio) | `DDates` | the bundled Dates row over two lines, Add date, Time with the duration, Skip this day |
| D · Recurring event, dark theme | `DEditDark` | the hero in dark |
| D · Recurring event, German | `DGerman` | the hero in German, the alert value dropping under its label |

**Scope: UI only.** `lib/widgets/event_detail_sheet.dart`, four shared
primitives in `form_rows.dart` / `form_metrics.dart`, one page-side
callback, ARB strings, tests, a QA flow and docs. No Drift table, model,
service, repository, backup or `.ics` change. Every callback the sheet
fires and every action it pops must be what it fires and pops today.

---

## 0. How to run this

Hand this to the implementing session (Fable), from `frontend/anta`:

> Implement the event detail sheet redesign described in
> `docs/event-detail-sheet-redesign-roadmap.md`.
>
> 1. Read that document end to end before touching code.
> 2. Load the skills it names: `anta-context`, `calendar-events`,
>    `calendar-ui`, `ui-revamp`, `l10n`, `qa-emulator`, `verify`.
> 3. Run Slices 1–4 in order, in this session. Run the gate after every
>    slice (`verify` §0). Never start the next slice with anything red.
> 4. Every behaviour in §5.1 and the checklist in §8 must survive. The
>    actions the sheet pops and the callbacks it fires must not change.
> 5. Every string in all three ARBs plus `flutter gen-l10n`; comments carry
>    the why; tests are welcome.
> 6. Slice 4 is not optional: the device pass against the boards, the
>    independent review by a fresh subagent, the fixes it confirms, the
>    docs in the same change.
> 7. Do not commit. The owner reviews and commits.

---

## 1. Why

The editor was redesigned on 2026-09-25 (`event-editor-redesign-roadmap.md`)
and the detail sheet — the surface the editor is reached *from* in the
day-panel loop — still speaks the language that redesign retired, on every
point:

- Flutter's own 48 dp drag band (`showDragHandle: true`) and a 16 dp radius
  on the plain `surface`, against the editor's 22 dp strip, 28 dp radius and
  `pageGround`;
- a centred header title and a filled Edit with an icon (D6, D18);
- loose icon-and-text lines (`_InfoRow`: an 18 px `onSurfaceVariant` glyph
  and body text) with no group, no hairline and no section label;
- an `OutlinedButton` for the note, `TextButton.icon`s for Add date and Skip,
  a tonal card for the description, Material `Chip`s for dates and the next
  occurrences — five control shapes the editor has none of;
- facts first: the description, the thing the sheet exists to show, sits
  below up to eight fact rows and three buttons.

Editing round-trips through this sheet on every trip (`_detailSheetLoop`
reopens it after Save and after Back), so the two surfaces alternate on
screen and the difference is seen every time.

## 2. Decisions (owner, 2026-09-26)

The proposal was argued on 2026-09-26 with three lettered questions; the
owner approved it whole ("I like it") and delegated the questions, so the
recommended option stands on each (`anta-design-debate`: a bare approval
after a lettered proposal is delegation).

| # | Decision |
| --- | --- |
| E1 | **The read-only twin of the editor** (Q1 · A). Same chrome, the same groups in the same order (capture · WHEN · OCCURRENCES · ALERTS · DETAILS), the same glyphs, so Edit and Back never shuffle the facts. Rows merge where a reader wants one fact (Time is one row, not All day + Starts + Ends). The alternative — facts first, the description last — keeps controls at fixed heights but buries the plan, which is today's problem. |
| E2 | **The sheet is as tall as its content, clamped at 0.92** (Q2 · A): the sub-sheet shape (`ConstrainedBox` → `Column(min)` → `Flexible(SingleChildScrollView)`), `useSafeArea: true`, the route's own drag, no discard guard — the sheet holds nothing that can be lost. A short event leaves the month grid visible behind it. The fixed-0.92 alternative leaves a one-time event on two thirds of empty ground. |
| E3 | **Header: `close_rounded` · "Event" · a text-button Edit** (Q3 · A), the sub-sheets' Done shape, so the filled button stays the commit button and the header alone says whether you are in a form. One shared primitive, `FormHeaderTextButton`, replaces the three hand-rolled copies (Repeat, Icon & color, this sheet). |
| E4 | **The read rule.** A row exists only when it carries a fact: a default priority, no note, no alerts, no end date, a start date equal to the opened day, all mean the row is absent — never a "None". A group with no rows is omitted; the capture group and WHEN always exist. This is what keeps the twin from being a second form. |
| E5 | **The title row is the day-panel row's twin**: `EventAvatar` (the `colorFor` look), the title at 20 / 500 wrapping, the category as a 13 px caption. The editor needs Category as a picker row; a reader needs it as the identity line under the title. |
| E6 | **The description renders in full**, one scroll, no inner scroll box: `SimpleMarkdownPreview` with `scrollable: false` in the editor's cell geometry (padding 16 / 13 / 48 / 13, 15 px over 22), the pencil (`edit_note_rounded`, tooltip `eventDescriptionEdit`) where the editor's expand button sits. Empty: the `eventDescriptionAdd` placeholder in `onSurfaceVariant`, the whole cell one target for the quick edit. The inert-box caption (`eventDescriptionTickAllOccurrences`) stays, as a `FormCaption` inside the cell. A read surface exists to show the text; a ten-line cap with nested scrolling is an input-cell rule. |
| E7 | **WHEN reads, top to bottom:** Date (the opened occurrence, with the count label — "Thu, Sep 24, 2026 · Week 4"); for a pinned set the bundled Dates row (`CalendarDatePickerSheet.datesValue`, the editor's two-line value) opening the Dates sheet's list; Add date for every event with `explicitDates`; Time (`eventTime`: the range plus the duration, or `eventAllDay`); Repeat with the editor's exact value (`RecurrenceFormatter.format` wrapped in `recurrenceUntilSuffix`), periodic rules only; Start date (`eventDate`) only when it differs from the opened day; Next occurrence (`eventDetailsNext`) with the count label and a `then …` caption listing the following three — counted from the day after the opened occurrence, or from today when a past day is opened, so the row never repeats the Date row (found on the device pass: opened on today's occurrence the old from-today scan made both rows say today). |
| E7a | *(lead, 2026-09-26, a deviation from the Physio board recorded here rather than later)* **A pinned set never gets per-date rows.** The editor's per-date rows exist for their ✕; a read sheet has nothing to do per date, so every set of two or more shows the Date row for the opened day above the bundled Dates row — the same two rows at two dates and at three hundred. |
| E7b | *(lead)* The row is labelled **"Next occurrence"**, not the board's "Next": German has no one-word form that reads as a row label ("Weiter" is the pager's Next). |
| E8 | **Presence is a chip pair on a labelled chip row** — `FormChipRow(glyph: how_to_reg_outlined, label: eventPresence, chips: Present / Missed)` with the two adherence lines as its caption — followed by **Skip this day** as an action row; both in OCCURRENCES, which exists only for a rule with several occurrences (`EventSkips.appliesTo`). The chips are the editor's Assume present / absent shape; the label and glyph drop under nothing. |
| E9 | **Alerts**: one `FormPickerRow` per alert — glyph `notifications_outlined` / `alarm_outlined`, label `alert.describe`, value the kind (`eventAlertModeNotify` / `eventAlertModeRing`) plus ` · ` + `eventAlertNext(when)` once the registry answers — tapping opens the editor as today. `removeAfterAlert` is a label-only fact row (`auto_delete_outlined`, `eventAlertRemoveAfter`) under the alerts. |
| E10 | **DETAILS**: Priority (`flag_outlined`) only when it is not `kDefaultEventPriority`; Linked note (`sticky_note_2_outlined`) showing the note's title with the editor's D19 states — an empty value while it loads, `untitledNote` for an empty title, `eventLinkedNoteNotFound` in `error` with the `eventLinkedNoteMissing` semantics label when it is gone — and a tap pops `openNote`. The title comes through a page-supplied `resolveNoteTitle` callback, so the sheet keeps its no-DI contract (every service it touches arrives as a callback, like `onOpenWikiLink`). |
| E11 | **Nothing the page sees changes**: `EventDetailAction` keeps its six values, every callback keeps its signature and timing, `show` gains one optional parameter. `_detailSheetLoop` is untouched apart from wiring `resolveNoteTitle`. |
| E12 | **Async facts fill in after open** (the registry's next fires, the note title), as today. The sheet may grow by one wrapped line inside the entrance animation. If the device pass shows a visible jump, the recorded fallback is to resolve both before `show` and pass them in. |
| E13 | **Semantics ids**: keep `event-detail-edit` / `event-detail-close`; add `event-detail-description` (the pencil), `event-detail-present`, `event-detail-missed`, `event-detail-skip`, `event-detail-add-date`, `event-detail-dates`, `event-detail-note`. `FormChip` gains `identifier`. |
| E14 | **Retire, after a repo-wide grep each, the keys only the old sheet read**: `eventDetailsNextOccurrences`, `eventDetailsNoDescription`, `eventDetailsSeriesStart`, `eventDetailsAllDates`. `eventDatesLabel` (the editor), `eventOpenLinkedNote` (the day panel's tooltip) and the presence, adherence, dates and alert strings stay. |
| E15 | **Shared numbers move to `FormMetrics`** the first time a second surface reads them: the 0.92 factor (the editor, both sub-sheets and this sheet), the header text button's 14 / padding 12 / inset 8, the description cell's 15 / 22 / 13, the title's 20 / 1.3. The editor and the sub-sheets are pointed at the shared constants in the same slice — a rename, no behaviour change. |

## 3. The spec

### 3.1 Geometry and tokens

- **Sheet.** `showModalBottomSheet(isScrollControlled: true, useSafeArea: true,
  showDragHandle: false, backgroundColor: pageGround, shape: top radius
  FormMetrics.sheetRadius)` → `ConstrainedBox(maxHeight: screen height ×
  FormMetrics.sheetHeightFactor)` → `Column(mainAxisSize: min)` of
  `FormSheetHandle`, `FormSheetHeader`, `Flexible(SingleChildScrollView)`.
  The route keeps `enableDrag` and `isDismissible` at their defaults; a
  drag-dismiss, the barrier and system back pop `null`, and `dispose`
  flushes a pending tick as today.
- **Header.** `FormSheetHeader(leadingIcon: close_rounded, leadingTooltip:
  close, leadingIdentifier: eventDetailClose, title: eventDetailsTitle,
  scrolled: <ValueNotifier fed by the body's ScrollController>,
  trailingInset: FormMetrics.headerActionInset, trailing:
  FormHeaderTextButton(label: edit, identifier: eventDetailEdit))`.
- **Body.** Padding `groupInset, bodyTop, groupInset, bodyBottom + clearance`
  where clearance is `max(viewInsets.bottom, viewPadding.bottom)`. Groups are
  `FormRowGroup`s under `FormSectionLabel`s; the capture group has no label.
- **Text roles, glyphs, chevrons, hairlines**: the `calendar-ui` skill's
  table, unchanged. Inert rows (`FormPickerRow(onTap: null, showChevron:
  false)`) draw no ink and carry no button semantics; tappable rows keep the
  chevron.

### 3.2 Row types — what is new

| Primitive | Change |
| --- | --- |
| `FormHeaderTextButton(label:, onPressed:, identifier:)` | new: the 48 dp `TextButton` at `FormMetrics.headerActionFontSize` (14 / 500 `primary`) with `headerActionPadding`; the Repeat and Icon & color sheets' Done and this sheet's Edit |
| `FormPickerRow(caption:)` | new optional caption line under the pair, inside the same row (one node, one target): 13 / 400 `onSurfaceVariant`, padded `subRowInset, 0, groupInset, rowCaptionBottomPadding` |
| `FormChipRow(glyph:, label:)` | new optional leading glyph and label: the row then reads `[glyph] label … [chips]` on one line, the chips dropping under the label when they do not fit (the `FormLabelValue` wrap), with the existing `caption` under it; without a label it is unchanged (the sub-row shape) |
| `FormChip(identifier:)` | new optional id, through `AutomationId` |
| `SimpleMarkdownPreview(scrollable:)` | new, default `true`; `false` lays the text out at its natural height with no `Scrollable`, so the sheet's body owns every vertical drag |
| `_TitleRow` (local to the sheet) | avatar · title 20 / 500 (`FormMetrics.titleFontSize`, `titleLineHeight`) wrapping · category caption 13; min `twoLineRowMinHeight`, `RowMetrics.twoLinePadding`; hairline from `dividerIndentTitle` |
| `_DescriptionCell` (local) | E6; hairline from `dividerIndentPlain` |

### 3.3 The screen, top to bottom

Copy in English; every string from an ARB key (§3.4). Gates are the
current code's, named.

**Capture group** (always):
1. `_TitleRow`: `CalendarCategories.iconFor(event)`,
   `EventSummaryProvider.colorFor(event, category)`, `event.title`,
   `CalendarCategories.labelOf(category, l10n)`.
2. `_DescriptionCell`: `_description` (the trimmed working copy) through
   `SimpleMarkdownPreview(scrollable: false, fontSize:
   FormMetrics.descriptionFontSize, moneyConfig: disabled, colorPalette,
   onCheckboxTap: _tasksInteractive ? _toggleTask : null, onTapWikiLink)`;
   the pencil `FormTrailingButton(edit_note_rounded, eventDescriptionEdit)`
   at the top right (`identifier: eventDetailDescription`) → `_close(editDescription)`;
   empty → the placeholder and an `InkWell` over the cell → the same action;
   `!_tasksInteractive && _hasTaskBox` → `FormCaption(eventDescriptionTickAllOccurrences)`.

**WHEN** (`eventSectionWhen`, always):
1. **Date** (`calendar_today_outlined`, `eventDateLabel`): `yMMMEd(day)`,
   suffixed ` · ` + `RecurrenceFormatter.countLabel(event, day, l10n)` when
   non-null. Inert.
2. **Dates** (`event_note_outlined`, `eventDatesLabel`), only while
   `explicitDates` has two or more: value
   `CalendarDatePickerSheet.datesValue(l10n, sorted, today)` (two lines, the
   editor's `_datesValue` moved next to `summaryLabel`), chevron, tap →
   `_close(showDates)`, `identifier: eventDetailDates`.
3. **Add date** (`add_rounded`, `eventAddDate`), while `explicitDates !=
   null` → `_close(addDate)`, `identifier: eventDetailAddDate`.
4. **Time** (`schedule_outlined`, `eventTime`): `time == null` →
   `eventAllDay`; else `EventTimeFormatter.formatRangeOfContext(time,
   context)` + (`durationMinutes != null` ? ` · ` +
   `EventTimeFormatter.formatDuration(durationMinutes, l10n)` : ``). Inert.
5. **Repeat** (`repeat_rounded`, `eventRepeat`), periodic rules only (not
   one-time, not a pinned set): `RecurrenceFormatter.format(rule, l10n,
   localeName, retroactive:)`, wrapped in `recurrenceUntilSuffix(rule,
   yMMMd(endDate))` when `endDate != null`. Inert.
6. **Start date** (`event_repeat_outlined`, `eventDate`), periodic only and
   only while `day != startDate`: `yMMMEd(startDate)`. Inert.
7. **Next occurrence** (`next_plan_outlined`, `eventDetailsNext`), periodic
   only: `_upcoming` empty → `eventDetailsNoOccurrences`; else
   `MMMEd(first)` + the count label as on the Date row; caption
   `eventDetailsThen(the next three, MMMEd, joined " · ")` when more than
   one is upcoming. Inert.

**OCCURRENCES** (`recurrenceScopeLabel`), only while `EventSkips.appliesTo(event)`
and at least one row applies:
1. **Presence** (E8) while `_presenceVisible`: chips `eventPresencePresent`
   (`selected: !_missed`, `identifier: eventDetailPresent`) and
   `eventPresenceMissed` (`selected: _missed`, `identifier:
   eventDetailMissed`) → `_setMissed`; caption `eventAdherenceSummary` and
   `eventAdherenceStreak` on two lines while `_stats != null`.
2. **Skip this day** (`event_busy_outlined`, `eventSkipOccurrence`) while
   `!EventSkips.isSkipped(event.id, day)` → `_close(skipOccurrence)`,
   `identifier: eventDetailSkip`.

**ALERTS** (`eventAlerts`), only while `_alerts.isNotEmpty`:
- one row per alert (E9), tap → `_close(edit)`;
- `event.removeAfterAlert` → the label-only row `eventAlertRemoveAfter`.

**DETAILS** (`eventSectionDetails`), only while a row applies:
- **Priority** while `priority != kDefaultEventPriority`: `EventPriorities.labelOf`. Inert.
- **Linked note** while `noteId != null` (E10): tap → `_close(openNote)`,
  `identifier: eventDetailNote`.

No actions group.

### 3.4 Copy and l10n

Load the `l10n` skill; add every key to `app_en.arb`, `app_de.arb`,
`app_ro.arb` together, run `flutter gen-l10n`, check `untranslated.txt`.

**New**

| Key | en | de | ro |
| --- | --- | --- | --- |
| `eventTime` | Time | Uhrzeit | Ora |
| `eventDetailsNext` | Next occurrence | Nächstes Vorkommen | Următoarea apariție |
| `eventDetailsThen` | then {dates} | dann {dates} | apoi {dates} |
| `eventPresence` | Presence | Anwesenheit | Prezență |

**Reuse**: `eventDetailsTitle`, `edit`, `close`, `eventDescriptionEdit`,
`eventDescriptionAdd`, `eventDescriptionTickAllOccurrences`,
`eventSectionWhen`, `eventDateLabel`, `eventDatesLabel`, `eventDatesNext`,
`eventDatesAhead`, `eventDatesAllPast`, `eventAddDate`, `eventAllDay`,
`eventRepeat`, `recurrenceUntilSuffix`, `eventDate`,
`eventDetailsNoOccurrences`, `recurrenceScopeLabel`,
`eventPresencePresent`, `eventPresenceMissed`, `eventAdherenceSummary`,
`eventAdherenceStreak`, `eventSkipOccurrence`, `eventAlerts`,
`eventAlertModeNotify`, `eventAlertModeRing`, `eventAlertNext`,
`eventAlertRemoveAfter`, `eventSectionDetails`, `eventPriority` and its
levels, `eventLinkedNote`, `eventLinkedNoteNotFound`,
`eventLinkedNoteMissing`, `untitledNote`.

**Retire** (E14), each after `grep -rn <key> lib test tool`.

## 4. Behaviour

### 4.1 Must not change

Every item is current code or a rule in the `calendar-events` skill; each
one is a past bug.

- **Actions.** `EventDetailAction` keeps `edit`, `editDescription`,
  `openNote`, `skipOccurrence`, `addDate`, `showDates`; `editDescription`
  carries no payload. `_detailSheetLoop`'s switch is untouched.
- **Exit funnel.** `_close` is the single exit: `_popped` guard, then
  `_flushWrite`, then pop. `_openWikiLink` reads `_popped` itself, pops with
  `null` first and hands the title over after. `dispose` flushes the last
  burst.
- **Checkbox ticks.** `_tasksInteractive` (per-occurrence on, or one-time
  with `onEventChanged` wired); `_writeDelay` 600 ms coalescing; a
  per-occurrence tick goes through `onOccurrenceChanged(day, text)`, a shared
  one through `onEventChanged(copyWith(description, clearDescription:
  isEmpty))`; the rendered string and the rewritten string are the same
  trimmed copy; `onCheckboxTap` is null when inert.
- **Pending text.** `pendingOccurrenceDescription` beats the facade.
- **Presence.** `_presenceVisible` = callback wired ∧
  `EventPresence.appliesTo`; a tap writes immediately (`onPresenceChanged`),
  `_stats` recomputes with the override, haptics as today.
- **Upcoming.** `_computeUpcoming`: 366 days, at most 4 (the next plus the
  three the caption lists), empty for any `explicitDates`; resolved once in
  state, never in `build`; `_today` read once. The scan starts the day after
  the opened occurrence (today for a past one) — see E7.
- **Alerts.** `EventAlerts.alertsFor` read once; `AlertScheduler.nextFiresForEventById`
  resolved once, failures swallowed; the "Next …" half formats through
  `MaterialLocalizations.formatTimeOfDay` honouring `alwaysUse24HourFormat`;
  an alert row's tap pops `edit`.
- **Description.** Money disabled by omission; `SimpleMarkdownPreview` with
  the palette passed in; `_hasTaskBox` through `MarkdownListSyntax.parse`.
- **Chrome contract.** `event-detail-edit` and `event-detail-close` keep
  their ids; the clearance test keeps both detail-sheet cases green; the
  header stays the first `Column` child.
- **Callers.** `calendar_page.dart` is the one caller; the two page-level
  suites (`calendar_sheet_double_tap_test.dart`, `calendar_initial_event_test.dart`)
  keep every assertion, with finders updated.

### 4.2 Deliberately changes

| Today | After |
| --- | --- |
| Flutter's 48 dp drag band, 16 dp radius, plain surface, 0.8 fixed height | 22 dp strip, 28 dp radius, `pageGround`, content height clamped at 0.92 |
| Centred "Event", `FilledButton.icon` Edit | Left-aligned "Event", text-button Edit |
| Avatar + title + category in a loose row | The title row: avatar, wrapping title, category caption |
| `_InfoRow` lines | Grouped rows with glyphs, labels and values under section labels |
| Date as the long form ("Friday, September 25, 2026") | `yMMMEd`, with the count label |
| Time row + separate "Repeats since" and end-date rows | One Time row with the duration; Repeat carries "until"; Start date only when it differs |
| Presence `SegmentedButton` + two caption lines | A labelled chip row with the same two lines |
| Priority row with `EventPriorities.iconFor` | `flag_outlined` (D12), only when non-default |
| `OutlinedButton` Open linked note | Linked note row with the note's title |
| `TextButton.icon` Add date / Skip this day | Action rows in WHEN / OCCURRENCES |
| Description label row + tonal card capped at 260 dp + pencil | The editor's cell, full height, the pencil top right |
| Next occurrences as five `Chip`s | One Next occurrence row plus a "then …" caption |
| Dates block: label, "3 of 10 ahead", up to eight `Chip`s, "All 10 dates" | The Date row and one bundled Dates row (E7a); the whole set lives in the Dates sheet |
| No ids beyond edit / close | E13 |

## 5. Facts from the tree (re-grep before editing)

- `lib/widgets/event_detail_sheet.dart` (978 lines): `EventDetailAction` :34;
  `show` :146 (`showDragHandle: true`, `heightFactor: 0.8`); state :185;
  `_presenceVisible` :246; `_setMissed` :262; `_perOccurrence` :274;
  `_tasksInteractive` :281; `_hasTaskBox` :291; `_alertLine` :305;
  `_resolveNextFires` :325; `_toggleTask` :343; `_flushWrite` :358;
  `_close` :394; `_openWikiLink` :410; `_computeUpcoming` :417; `build` :452;
  `_buildExplicitDates` :867; `_InfoRow` :940 (to delete).
- `lib/pages/calendar_page.dart`: `_openDetailSheet` :777, `_detailSheetLoop`
  :786 (the `show` call :801), `_quickEditDescription` :932, `_skipOccurrence`
  :992, `_editExplicitDates` :1618, `_setOccurrencePresence` :1739,
  `_openLinkedNote` :1809 (resolves through `NoteRepository.getNotesByIds`
  — the shape `resolveNoteTitle` copies), `_openWikiLink` :1856.
- Primitives: `lib/widgets/form_rows.dart` — `FormSheetHeader` :124,
  `FormLabelValue` :211, `FormPickerRow` :359, `FormSwitchRow` :457,
  `FormActionRow` :555, `FormChip` :685, `_TapTargetPadding` :745,
  `FormChipRow` :805, `FormCaption` :834; `lib/constants/form_metrics.dart`.
- The three hand-rolled header buttons and factors: `event_look_sheet.dart`
  `_LookMetrics` :46 (`maxHeightFactor`, `headerTrailingInset`,
  `doneFontSize`, `donePadding`) and the `TextButton` :158;
  `event_repeat_sheet.dart` `_doneFontSize` :102, `_headerTrailingInset` :104,
  `show` :106, the `TextButton` :243; `event_editor_sheet.dart`
  `_sheetHeightFactor` :262, `_titleFontSize` :263, `_titleLineHeight` :264,
  `_descriptionFontSize` :269, `_descriptionLineHeight` :270,
  `_descriptionCellPadding` :272, `_datesValue` :1753, `_loadLinkedNoteTitle`
  :1403, the linked-note row :2660.
- `lib/widgets/simple_markdown_preview.dart`: the `SingleChildScrollView` :144.
- Facades and helpers: `EventSkips.appliesTo` :48, `isSkipped` :55;
  `EventPresence.appliesTo` :81, `isMissed` :95; `OccurrenceDescriptions.appliesTo`
  :60, `descriptionFor` :93; `PresenceAdherence.compute`; `RecurrenceFormatter.format`
  :12, `countLabel` :48; `EventTimeFormatter.formatRangeOfContext` :38,
  `formatDuration` :75; `CalendarDatePickerSheet.summaryLabel` :146;
  `AlertScheduler.nextFiresForEventById` :485; `EventAlert.describe` :155,
  `isAlarm` :80; `EventSummaryProvider.colorFor` (`day_summary_resolver.dart:144`);
  `CalendarCategories.resolve` :152, `iconFor` :156, `labelOf` :165;
  `EventPriorities.labelOf` :24; `kDefaultEventPriority`.
- `lib/constants/semantics_ids.dart`: `eventDetailEdit` :83,
  `eventDetailClose` :84.
- Tests on this sheet: `test/widgets/event_detail_dates_test.dart` (6),
  `event_detail_description_test.dart` (7), `event_detail_sheet_wiki_link_test.dart`
  (5), `sheet_bottom_clearance_test.dart` (two cases), and through the page
  `calendar_sheet_double_tap_test.dart` :386 (`FilledButton` 'Edit') and
  `calendar_initial_event_test.dart` (by type only). `form_rows_test.dart`
  exists (11 cases) and gains the new primitives.
- QA: `tool/qa/flows/calendar/02_editor_sheets.txt`, `03_dates.txt`,
  `04_alerts.txt` pass through the sheet by `event-detail-edit` /
  `event-detail-close` only. The seed's `qa-cal-lift` (weekly, presence,
  per-day, a linked note, P2) and `qa-cal-physio` (six pinned dates) are the
  flow subjects.

## 6. Slices

### 6.0 The gate, after every slice

`dart analyze lib test` clean; the **whole** `flutter test` green, one run
at a time and never beside a QA `flutter run`; `flutter gen-l10n` run and
`untranslated.txt` empty when an ARB changed; §4.1 re-read against the diff.

### Slice 1 — Primitives and shared numbers

1. `FormMetrics`: `sheetHeightFactor` 0.92, `headerActionFontSize` 14,
   `headerActionPadding` (0 12), `headerActionInset` 8, `titleFontSize` 20,
   `titleLineHeight` 1.3, `descriptionFontSize` 15, `descriptionLineHeight`
   22, `descriptionCellPadding` 13, `rowCaptionBottomPadding` 10.
2. `form_rows.dart`: `FormHeaderTextButton`; `FormPickerRow.caption`;
   `FormChipRow.glyph` / `label`; `FormChip.identifier`.
3. `SimpleMarkdownPreview.scrollable`.
4. Point the editor and both sub-sheets at the shared constants and the
   shared header button (E15). No behaviour change; their suites stay as
   written.
5. Tests in `form_rows_test.dart`: the header button carries its id and
   label; a picker row's caption sits inside the row's node; a labelled chip
   row keeps its chips' 48 dp targets and drops them under a long label at
   360 dp; a chip's id lands on its node.

### Slice 2 — The sheet

1. Rewrite `event_detail_sheet.dart` to §3, keeping every member §4.1 names.
2. `CalendarDatePickerSheet.datesValue` (from the editor's `_datesValue`; the
   editor calls it).
3. ARB (§3.4), `SemanticsIds` (E13), `resolveNoteTitle` wired in
   `_detailSheetLoop`.
4. Tests: update the three detail suites' finders (the pencil, the
   placeholder, the Dates row, Add date, the next-occurrence row, no chips)
   keeping every assertion's intent; update the two page-level finders; a
   new `event_detail_sheet_test.dart` covering: close pops `null` and Edit
   pops `edit`; the read rule (a default priority and no note leave no
   DETAILS group; no alerts leave no ALERTS group); Time for all-day, a
   range, a range with a duration; Repeat with and without "until"; Start
   date only when it differs; Next occurrence and its caption, and the
   no-occurrence value; the presence chips select and write, and the
   caption updates; Skip present, absent when skipped, absent for one-time;
   an alert row pops `edit` and reads its kind; Remove after it rings shows
   only when set; the linked note's three states through a fake resolver;
   `de` at text scale 2.0 on 360 × 780 with no overflow; the ids of E13.
5. `tool/qa/flows/calendar/07_detail.txt`: open the weekly session, shot,
   tap Missed then Present, open the linked note row is *not* tapped
   (a page push would leave the calendar), Skip is only checked present,
   close; open Physio, the Dates row → the Dates sheet's list → cancel →
   close.

### Slice 3 — Delete the old UI

1. `_InfoRow` and the chip code go with the rewrite; grep for the retired
   ARB keys (E14) and remove them from all three files; `gen-l10n`.
2. Re-read §4.1 against the full diff.

### Slice 4 — Device pass, independent review, docs

1. **Device pass** (`qa-emulator`): `qa relaunch --fresh --seed
   tool/qa/fixtures/calendar.json` (a `qa run` after the lib change), `qa
   flows calendar` green first; then the D boards on the iOS simulator in
   light, the hero in dark and German, `qa set text-scale=2.0`, screenshots
   beside the boards; `qa errors` clean; the Android emulator if it boots.
   Check on the device: the sheet's height follows the content and clamps;
   drag-dismiss, the barrier and system back pop; the presence chips write
   and the caption moves; Skip cancels with Undo; the Dates row opens the
   list; Edit → Back returns to the same sheet; the description's task boxes
   tick on the weekly session (per-day on); no visible jump when the alert's
   "Next …" arrives (E12).
2. **Independent review** by a fresh `fable-max` subagent briefed with this
   record and the diff: confirmed defects only, ranked; fix what it
   confirms; re-run the gate.
3. **Docs in the same change**: `docs/calendar-events-feature.md` addendum
   (2026-09-26, the detail sheet) and its §6.2 paragraph; `COPILOT_CONTEXT.md`'s
   detail-sheet passages; the `calendar-events` skill's detail-sheet lines;
   the `calendar-ui` skill's adoption paragraph and primitives table; this
   record's status header.

## 7. Definition of done

1. Every action round-trips through the page loop exactly as before: Edit →
   Back returns here; a quick description edit returns here; Skip, Open note
   and a delete end the trip.
2. Every control is reachable one-handed on a 360-wide phone with 48 dp
   targets — the chips, the pencil, the rows.
3. Drag, the barrier and system back close silently; a pending tick is
   flushed on every exit.
4. Light and dark; en, de, ro; text scale 1.3 and 2.0 with no clipped label
   and no overflow; 360 × 780 and 412 × 915.
5. The bottom-clearance rule holds (both existing cases stay green).
6. Nothing moves under the finger after the entrance: a presence tap changes
   text, not geometry; a tick changes a glyph.
7. Every string through `AppLocalizations` in all three ARBs;
   `untranslated.txt` empty.
8. Semantics: tooltips on the pencil and the close button; one node per row;
   E13's ids present.
9. The three existing detail suites, both clearance cases and the two
   page-level suites pass with their intent intact; the new suite covers §6
   Slice 2.4.

## 8. Deferred

- The pre-redesign sheets that still hand-roll their chrome (the day-list
  sheet, the filter and preset sheets, the category picker, the Dates
  sheet's header): the `calendar-ui` adoption rule — when a change opens
  them.
- A tap on the Next occurrence row selecting that day on the grid: a new
  action, not needed for this pass.
- Ids on alert rows (`event-detail-alert-<id>`): no flow needs one yet.
- Pre-resolving the async facts before `show` (E12's fallback), only if the
  pass shows a jump.
- A `lineHeight` on `LineMarkdownStyle`, threaded through the ten span
  styles of `LineBasedMarkdownBuilder`, so a read cell can ask for the
  editor's 22 px line (E6; the review's finding 5). A markdown-engine change,
  worth doing together with the editor's own preview toggle, which has the
  same 1.25 px-per-line difference.
