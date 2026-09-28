# Calendar UI Language — Tier 1 record: the agenda filters sheet and the chrome-only pass (2026-09-27)

**Status: IMPLEMENTED and REVIEWED 2026-09-27, uncommitted — the owner
reviews and commits; Tier 2 starts on a clean tree.** Slices 1–6 are in the
tree with the fix round of D24 applied: `dart analyze lib test` clean,
`flutter test` 6137 passed / 7 skipped / 1 failed (the known Windows-only
`host_devices_test.dart` case), `untranslated.txt` `{}`, `qa flows calendar`
**12 / 12** on the Pixel emulator through the agent (twice: after slice 5 and
after the fix round), `qa errors` clean after the dark / German / 200 %
matrix, every §3.10 id seen on its control in the `look` dumps. The
independent review (a fresh `fable-max`, read-only) confirmed **no
behaviour, layout or semantics defect** and left three low nits plus two
undeclared deviations, all taken in D23 / D24; the device pass found the
nine 200 % findings D24 lists. §9 is the slice ledger. Tier 1 of
`docs/calendar-language-adoption-roadmap.md` (the owner's max-effort plan for
every calendar surface still outside the 2026-09-25 language). The owner's
instruction for the whole pass: "implement it, max effort" — every design
question below was **delegated**, so the recommended option stands and each
decision says so. The mocks for the one surface with real layout questions
(the agenda filters sheet) are on the Design canvas **"Agenda Filters
Mocks"** — https://claude.ai/artifact/FGLdxuNj5a3ATaDCpiaKYo — (eleven
boards: today's two device shots, the direction in light and dark, the
active and "No events" states, the Period menu, the inert fasting tile, the
German 200 % stress board, the rejected alternative A, the ids); where a
board and this record disagree, **this record wins** (the places: the
Active board draws Fasting enabled because the QA seed configures a
tradition; the German strings on the stress board are the record's §7.4
wording, harsher than the ARB's). Line numbers in
§5 are from a read of the tree on 2026-09-27 (`534d6ae` plus the uncommitted
roadmap doc); re-grep every one before editing.

## 0. How to run this

Load `anta-context`, `calendar-events`, `calendar-ui`, `ui-revamp`, `verify`,
`l10n`, `qa-emulator`, and `markdown-engine` for slice 4 (the description
sheet). Read this record whole, then §5 against the tree. Work the slices of
§6 in order; never start a slice with anything red. After **every** slice the
gate:

- `dart analyze lib test` clean;
- the **whole** `flutter test` green, one run at a time (`test/qa/
  host_devices_test.dart` has one known Windows-only failure — note it, never
  touch it; a `sqlite3.dll` lock crash is transient — rerun);
- `flutter gen-l10n` run and `frontend/anta/untranslated.txt` equal to `{}`
  whenever an ARB changed;
- §4.1 (must not change) re-read against `git diff`.

**Never run `flutter test` while a QA `flutter run` is up** (two Flutter
processes race on `build/native_assets`): `tool\qa\qa.cmd kill-run` first —
the app stays installed and running on the emulator, `qa relaunch` brings the
agent back in two seconds.

Slice 6 is the device pass on the Pixel emulator through the harness, never
`adb` by hand: after any `lib` change `tool\qa\qa.cmd run --fresh --seed
tool/qa/fixtures/calendar.json`, then `$env:ANTA_QA_VIA = 'agent'` and
`tool\qa\qa.cmd flows calendar` (the ten saved flows plus the two new ones,
green before anything else is looked at), then the matrix `qa set theme=dark
locale=de text-scale=2.0` with every screen of §3 shot, `qa errors` clean,
`qa set theme=light locale=system text-scale=off` at the end. Then the
independent review (§6, slice 6) by a fresh `fable-max` subagent briefed with
this record and the diff, and the docs of slice 6. **Do not commit** — the
owner reviews and commits; Tier 2 starts on a clean tree.

## 1. Why

Eight calendar sheets speak the editor's language today; the eight surfaces
of this tier are the ones every migrated sheet opens, so the seam is in the
app's most-used flows: the editor opens the time pad and the Dates sheet, the
Look sheet opens the icon picker, the detail loop opens the description
sheet, a day long-press opens the template picker, the alert editor and the
settings row open the sound sheet, the month title opens the month/year
wheels, and the Upcoming agenda's filter button opens the twin of the Filters
sheet the owner just had rebuilt.

The agenda filters sheet (`agenda_filters_sheet.dart`, 652 lines) is the
Filters sheet's twin in the old coat: on the QA seed it is **40 tappable
controls** in one scroll (six period chips, three layer chips, a three-way
`SegmentedButton`, six priority chips, ten category chips, three more
segmented controls, a `SwitchListTile`, a Reset text button in the header and
a pinned Apply bar) — the 2026-09-27 Filters record's §1, word for word. The
device shots of 2026-09-27 (`build/qa/shots/20260927_1404*_today_agenda_
filters_*.png`) are the "today" boards on the canvas.

The seven chrome-only sheets each hand-roll the chrome the language retired:
the stock 48 dp drag band on the plain surface, a centred `titleLarge` title,
icon buttons flanking it, a `FilledButton` in the header or a Cancel / Apply
bar at the bottom, six different height factors (0.7, 0.85, 0.86, 0.92, or
none). Four of them (the agenda sheet, the month/year picker, the template
picker, the icon picker) are not in `sheet_bottom_clearance_test.dart`, the
one test that has ever caught the app's most-repeated defect.

## 2. Decisions (owner, delegated 2026-09-27 — the recommended option stands)

| # | Decision | Reason · rejected alternatives | Who |
| --- | --- | --- | --- |
| D1 | **The agenda filters sheet takes the Filters sheet's shape and grammar**: the sub-sheet (content-tall, clamped at `FormMetrics.sheetHeightFactor`, `pageGround`, radius `sheetRadius`, `showDragHandle: false`, the route's own drag), ✕ · "Filters" · `FormHeaderTextButton(Apply)`; draft-and-Apply kept — Apply pops the draft, ✕ / drag / back / barrier pop `null`, no guard (no typed text; the panel owns the query). `AgendaFiltersSheet.show(context, filters:) → Future<UpcomingAgendaFilters?>` unchanged. | It is the Filters sheet's twin (same enum, same picker, same check-list sheet); two grammars for two filter sheets is the seam the owner named. | lead, delegated |
| D2 | **Eleven rows in five groups**: an unlabelled first group (Period · Start from selected day), **EVENTS** (Events · Categories · Priority), **ALSO SHOW** (Holidays · Fasting), **DISPLAY** (Event rows · Fasting rows · Holiday rows), and the actions group (Reset filters). 666 dp of content (11 × 48 + three labels + four gaps + six hairlines) plus the body padding against the 0.92 clamp: on a 390 × 844 phone at text scale 1 the top level scrolls by exactly the bottom clearance — 40 dp with a three-button bar, 16 dp with gesture navigation — so at rest only the Reset row's lower edge is under the fold; on the 427 dp emulator and a 412 × 915 phone it fits whole; at 360 × 780 the Reset row is below the fold. (The Filters sheet's 731 dp has the same clearance arithmetic; its record's "never scrolls" omitted the bar.) | The Filters sheet's order (what narrows, then what is drawn in addition), with the window first because it is the agenda's own axis and the anchor switch belongs to the window it moves. *Rejected:* A — an Events **switch** in a SHOW group gating a separate Repeat menu (twelve rows, ≈ 720 dp, scrolls on every phone, two vocabularies for one enum); C — labelled chip rows (the wall the Filters record rejected as B). | lead, delegated |
| D3 | **Period is one `FormMenuRow`** over six choices — `7 days`, `30 days`, `90 days`, `Rest of year`, `This year`, `Custom range…` — reading back `AgendaFiltersSheet.periodModeLabel` or, while a range is pinned, `AgendaListView.rangeLabel`. Picking a preset writes `periodMode` / `rangeDays` with `clearCustomRange: true` (today's chips); picking `Custom range…` opens today's `showDateRangePicker` (`_pickCustomRange`, bounds and the `now()` read untouched) — a cancelled pick changes nothing, a pick writes `customStart` / `customEnd`; the check sits on `Custom range…` while a range is pinned. The menu is at least `menuWidth` wide and grows to `menuMaxWidth` (Filters D24) — a range label needs it. | Six mutually exclusive words are a menu's grammar (Filters D1). The Dates sheet has no range mode (§5) and building one is a feature, not chrome — deferred (§8). *Rejected:* a chip row (two lines of six chips); a sub-sheet of radio rows (a second surface for six words). | lead, delegated |
| D4 | **Events is one `FormMenuRow` over the whole `AgendaEventType` axis** — `All`, `Recurring`, `One-time`, `No events` — with `CalendarFilterSummary.eventTypeLabel` / `eventTypeIcon` (the sheet's private `_eventTypeLabel` copy goes). While the value is `none`, the Categories and Priority rows draw at 38 % and are inert (today they vanish). `_lastEventType` is retired: there is no toggle left to remember across. | The model is one axis "so it can never encode the contradictory neither state" (`upcoming_agenda_filters.dart:5–9`); the row says so. *Rejected:* the switch of D2's alternative A. | lead, delegated |
| D5 | **Categories and Priority are the Filters sheet's rows and sub-sheets**: a `FormPickerRow` each, reading back through `CalendarFilterSummary.namesReadBack` (`All` / `Any` while empty), opening `CategoryPickerSheet.pickMulti` with today's **allowlist** inversion (an empty allowlist opens with every offered row checked; an answer covering the offered set collapses back to the empty set; an empty answer is stored) and `FilterCheckListSheet` with the five priorities (ids `filter-list-priority-1…5`, the shared sheet's). `CategoryFilterTile` leaves this sheet and stays in the tree for the overview page (Tier 4 deletes it). `upcomingClearCategories` ("Show all categories") retires — the picker's Select all and the row's read-back cover it. | D1; one picker, one check-list sheet, one read-back rule. | lead, delegated |
| D6 | **The three display axes are `FormMenuRow`s** with the values' own icons; the layers are `FormSwitchRow`s. **Fasting (the switch) and Fasting rows (the menu) draw at 38 % with their stored values while `FastingCalendar.isEnabled` is false** — never omitted (Filters D8). `agenda_filters_sheet_test.dart`'s "absent while inert" case becomes "present and inert". | The language's disabled-never-hidden; a control that appears between two openings moves everything under it. | lead, delegated |
| D7 | **Reset filters is the last action row** (`calendarFilterReset`, `restart_alt_rounded`), 38 % while the draft equals `const UpcomingAgendaFilters()` with the query ignored, resetting to exactly today's value (`const UpcomingAgendaFilters().copyWith(query: _draft.query)`) and keeping the sheet open. `upcomingFiltersReset` ("Reset") retires. | Filters D3. | lead, delegated |
| D8 | **The panel is untouched but for one id**: `agenda-filter-open` on the tune `IconButton`; the summary chips, the badge (it counts chips), the search field, `periodModeLabel` (still a static on the sheet, the chip reads it) all stay. `CalendarFilterSummary.eventTypeIcon(none)` is aligned to the chip's `event_busy_rounded` so "no events" has one glyph. | The chips are the strip's grammar (roadmap §3, Tier 4). | lead, delegated |
| D9 | **Ids** (§3.10): `agenda-filter-*` on every row, menu item and the chrome; the two sub-sheets keep `filter-list-*` / `category-pick-*`; a new flow `10_agenda_filters.txt`. | Filters D18. | lead, delegated |
| D10 | **Three shapes for the seven chrome-only sheets, none of them new**: the **sub-sheet** (content-tall clamped at 0.92, route drag, unguarded) for the time pad, the month/year picker, the template picker and the sound sheet; the **form sheet's box without its guard** (`FractionallySizedBox(FormMetrics.sheetHeightFactor)`, `pageGround`, route drag) for the Dates sheet and the icon picker, whose bodies *fill* — a month grid, a year matrix, a list of dates, a grid of four hundred icons under a live search; the **form sheet** (fixed box, own drag, the dirty guard through one `_leave()`) for the description sheet, which has typed text and a docked bar. | "Constant-height sub-sheets — nothing moves under the finger" outranks content-tall for a filler: a content-tall Dates sheet would change height between Month / Year / List, a content-tall icon grid would jump on every keystroke. The fixed factor is the one the rule allows. *Rejected:* a fourth factor; content-tall fillers. | lead, delegated |
| D11 | **The Dates sheet's header becomes `FormSheetHeader`**: ✕ (`date-picker-cancel`, tooltip `cancel`) · `datePickerMultiTitle` / `datePickerSingleTitle` · `FormHeaderTextButton(save, date-picker-save)` in multi mode (disabled while the selection is empty and `!allowEmpty`), an empty trailing slot in single mode (pick-on-tap). **Today leaves the header** and becomes a fixed 48 dp slot after the title in the month grid's own header row (`headerTitleBuilder`) and in the year view's ‹ year › row — `AgendaPeriodNav`'s grammar, `today_rounded`, tooltip `datePickerToday`, id `date-picker-today`, `_jumpToToday` unchanged; the list view has no Today. The summary row (count · span … Clear), the Month / Year / List `SegmentedButton`, the grid, the `YearMonthTile` matrix, the list and the repeat footer (its inline Cancel / Apply pair included) are content and stay. Height moves from 0.86 to the box of D10. | The header has one leading icon and one trailing action; Today is a navigation control, and the language's navigation row already has its slot. | lead, delegated |
| D12 | **The time pad keeps its Done in the header** as `FormHeaderTextButton(timePadDone, time-pad-done)` beside ✕ (`time-pad-cancel`); the readout, the caption band and the keypad (its `FilledButton` keys included) are the pad's content. The roadmap's "confirm below the fold" question is moot: the pad has no confirm key of its own — the keys that complete an entry pop by themselves, Done serves a partial one. | Nothing to except from "no bottom bar". | lead, delegated |
| D13 | **The month/year picker**: ✕ · `monthYearPickerTitle` · `FormHeaderTextButton(apply)`; the wheels / typed entry inside `AnimatedSize` unchanged; under them one `FormRowGroup(trailingGap: false)` of `FormActionRow(today_rounded, datePickerToday)` and `FormSwitchRow(keyboard_rounded, monthYearPickerTypedEntry "Type the date", value: _typing)`. The tonal toggle with its two flipping tooltips, the Today · Cancel · Apply bar and the route-level `Padding(viewInsets)` go; the clearance moves to the scroll view's padding. | A switch names the mode without a label that flips under the finger (Filters D13's reasoning); Today is an action. | lead, delegated |
| D14 | **The description sheet becomes a form sheet with the editor's guard**: ✕ (`description-close`, tooltip `cancel`) · `eventDescription` · `FormHeaderTextButton(eventDescriptionDone, description-done`, disabled past the limit); `_leave()` asks with the editor's dialog (`unsavedChanges` / `keepEditing` / `discardChanges`) **only when the text differs from `initialText`**, serving ✕, back, the system back, the barrier and the sheet's own drag; Done never asks. The event title moves from the centred two-line header into the **status band's first line** (muted, one line, ellipsized) above the scope caption / over-limit line, the counter staying right, the band's minimum height unchanged. The docked markdown bar keeps the clearance. | Typed text leaves silently today — the one lost-text path left in the calendar; the language's form shape exists for exactly this. | lead, delegated |
| D15 | **The form sheet's drag-and-guard chrome is hoisted out of the editor into `FormSheetFrame`** (`lib/widgets/form_rows.dart`): `PopScope(canPop: false)` → `onLeave`, the `GestureDetector` over the handle and header, `_dragOffset` / snap-back animation / the dismiss threshold (velocity 700, a quarter of the height), the `Material(pageGround, radius)`. The editor migrates to it in the same slice with its "leaving with unsaved changes" suite unchanged; the description sheet is the second reader. | The `ui-revamp` skill: chrome lives where the next surface can use it, never as a copy inside one screen — the day-old lesson of the Filters record. | lead, delegated |
| D16 | **The template picker**: content-tall; ✕ (`template-pick-close`) · `addFromTemplate` · empty trailing (pick-on-tap); one `FormRowGroup(trailingGap: false)`: a `FormPickerRow(leading: EventAvatar(iconFor, colorFor), label: name, caption: templateSummary, showChevron: false, identifier: template-pick-<id>)` per template, then `FormActionRow(alarm_add_rounded, quickAlarmRow, quick-alarm-row)`, then `FormActionRow(edit_calendar_rounded, templateBlankEvent, template-pick-blank)`. Height 0.7 → content-tall. | Roadmap Tier 1 item 2; the quick-alarm row keeps its id (the Quick Settings tile pass targets it). | lead, delegated |
| D17 | **The icon picker**: the fixed box (D10); ✕ (`icon-pick-close`) · `pickIcon` · empty trailing (pick-on-tap); a **pinned** `FormRowGroup(trailingGap: false)` holding one `FormSearchRow(hint: searchIcons, clearTooltip: clearSearch, identifier: icon-pick-search)` between the header and the grid; the grid's section labels become `FormSectionLabel`s; the tiles, the "Recently used" section, the ranking and the `Divider`-free layout stay; the no-match state is `FormCaption(noIconsFound)` under the search group — the "Clear search" `TextButton` goes (the row's ✕ clears). `SettingsSearchField` is no longer read here. | A search field that scrolls away with its results is unreachable while the results change; pinned, it never moves under the finger. | lead, delegated |
| D18 | **The sound sheet**: content-tall; ✕ (`sound-close`) · `alertsSound` · empty trailing (pick-on-tap); one group of `FormCheckRow(exclusive: true)`s — `Use the app setting` (`settings_suggest_outlined`, only while `allowInherit`, `sound-inherit`), `Phone's default alarm` (`phone_android_rounded`, `sound-phone-default`), `Choose from phone` (`library_music_outlined`, `sound-from-phone`, `caption:` the phone's name for the stored sound while one is stored, `onChanged: _picking ? null : _pickFromPhone`). The phone-picker row stays **absent** where the platform has no picker (`supportsSoundPicker` is a capability of the device, not a state that changes under the finger). `useSafeArea: true` added. The `system:default` / content-URI values, `labelFor`, the gateway calls and the two callers' switches are untouched. | Roadmap Tier 1; `FormCheckRow(exclusive:)` is the radio shape with a caption slot the sublabel needs. | lead, delegated |
| D19 | **Bottom clearance** — `max(viewInsets.bottom, viewPadding.bottom)` on the scroll view's padding, or on the fixed footer where one sits below the scroll view (the Dates sheet's repeat footer, the description sheet's bar); the header always the first `Column` child. The four sheets missing from `test/widgets/sheet_bottom_clearance_test.dart` (the agenda sheet, the month/year picker, the template picker, the icon picker) join it; the cases already there stay green. | The rule that has shipped four defects. | lead, delegated |
| D20 | **Copy** (§3.9): three new keys, one retitle, eight retirements — each retirement after `grep -rn <key> lib test tool`. | §3.9. | lead, delegated |
| D21 | **Three primitive additions**, each with its `form_rows_test.dart` case: `FormPickerRow.leading` (a 40 dp widget replacing the glyph — the title row's 56 dp shape, divider indent `dividerIndentTitle`), `FormMenuRow.onSelected` nullable (`null` = 38 % and inert, the row's node `enabled: false`, no menu opens), and `FormSheetFrame` (D15). | Each is the language meeting a case the existing rows did not draw. | lead, delegated |
| D22 | **Slice 1's four amendments to D15 / D21** (accepted): `FormSheetFrame` lives in its own `lib/widgets/form_sheet_frame.dart`, exported from `form_rows.dart` (the `form_menu_item.dart` precedent), and takes `body: List<Widget>` — the column's remaining children, so a docked bar sits under the scroll view exactly as before; **`FormPickerRow.enabled`** (default `true`) is a fourth primitive change — the row's node cannot be marked `enabled: false` from outside its own `MergeSemantics`, so the flag lives inside it as `FormCheckRow`'s does, and a disabled menu row is drawn through it; slice 2's Categories / Priority rows dim through `enabled: eventType != none` (an `onTap: null` alone draws a read row, not a dimmed one); `FormMetrics.rowLeadingSize` (40) names the leading box; the frame keeps a local in-flight flag so a drag that ends mid-leave snaps back while the editor's own `_leaving` latch keeps re-entrancy. | The language's own rules (a number named first, a node's flag inside its merge, one copy of an anatomy) meeting the hoist. | implementer, 2026-09-27 |
| D23 | **The description sheet's status band reserves lines from its static inputs only** — three while both a subject and a scope caption exist, else two — and **over the limit the explanation replaces the whole band text**, subject included, for as long as the text is over budget. Amends D14's "band minimum height unchanged" and slice 4's three-lines-with-a-subject rule. | The review found slice 4's rule left two empty lines above the event name on a one-time event (no caption): 34 dp of dead space under the header at 1×, 67 at 2×. A reservation computed from the subject and the caption never changes at runtime, and the over-limit message is the more urgent line — it already took the caption's slot; taking the subject's too keeps the editor still without reserving air for a line that is almost never shown. | lead, 2026-09-27 (review round) |
| D24 | **Fix round after the device pass and the review** (all on Tier 1 surfaces, none deferred): the Dates sheet's weekday row takes the calendar page's `daysOfWeekStyle` (its labels clipped at 200 %), its month title may wrap to two lines rather than drop the year, and `table_calendar`'s header padding is zero so the ‹ title [today] › row is 48 dp like `AgendaPeriodNav`; the time pad's caption band takes two lines at scale instead of ellipsizing; the month/year picker's wheel labels scale down to fit their column and its typed entry occupies the wheels' height so switching modes never resizes the sheet; `FormMetrics.sheetDismissFraction` names the quarter-height threshold; the frame's drag surface is excluded from semantics (it read as a scrollable) and the time pad's `Focus` root no longer absorbs the header's title; the Look sheet's ✕, Icon and Colour rows gain ids so flow 11 stops counting labels; the `periodModeLabel` comment and six reused keys' `@` descriptions stop naming chips. **Accepted, not defects:** a header title ellipsizes at 200 % beside a long action or, past ~20 characters, even alone ("Datum w…", "Aus Vorlage hinzufüg…") — the one-line 48 dp header is the language's, the editor's own title does the same, and a two-line header is a language decision for the owner (§8); menu items are `FormMetrics.menuRowHeight` 44 dp (Filters D12), not 48 — §7.2 corrected; the description band's scope caption clamps at two lines by §3.6. | The owner's brief: nothing left half-done, no defect deferred; each fix is on a Tier 1 surface and inside the chrome or a body the record marked "unchanged" only because nobody had looked at it at 200 %. | lead, 2026-09-27 (fix round) |
| D25 | **The fix round's own amendments** (accepted): the Dates sheet's month title sits in a box measured over the year's twelve `yMMMM` titles at the text's width (`_monthTitleHeight`), so paging from "September 2026" (two lines at 200 %) to "Juli 2026" (one) never moves the grid — static per scale, the rule D24 asked for; `table_calendar`'s chevron margins are zero beside the zero header padding (each chevron is 48 dp like `AgendaPeriodNav`'s, and the 32 dp they give back is what "September" needs to wrap at the space on a 360 dp phone); the Look sheet's `look-color` is a plain `Semantics(identifier:)` container over the swatch strip, not a merge (merging would fold eighteen swatches into one node — `AutomationId`'s own container case); the weekday labels of the grid and the Dates sheet come from one `CalendarDaysOfWeek` helper (`lib/utils/calendar_days_of_week.dart`, the page's inline style hoisted); four more named numbers — `FormMetrics.periodTitleMaxLines` (2), `timePadCaptionLines` (2), `statusLineFactor` (1.4, the band's line box), `sheetDismissFraction` (0.25) — and the time pad's caption band measures its two lines with a `TextPainter` rather than multiplying, so it matches the style's real line box. | Each is the language's own rule (a number named first, nothing moving at runtime, one copy of a style) meeting a case the fix list did not draw. | implementer, 2026-09-27 (fix round) |

## 3. The spec

### 3.1 Geometry and tokens

Every number is an existing `FormMetrics` / `RowMetrics` constant.

- **Sub-sheet** (the agenda sheet, the time pad, the month/year picker, the
  template picker, the sound sheet): `showModalBottomSheet(isScrollControlled:
  true, useSafeArea: true, showDragHandle: false, backgroundColor:
  colorScheme.pageGround, shape: RoundedRectangleBorder(top radius
  FormMetrics.sheetRadius))` → `ConstrainedBox(maxHeight:
  MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor)` →
  `Column(mainAxisSize: min)` of `FormSheetHandle`, `FormSheetHeader`,
  `Flexible(SingleChildScrollView(controller:, padding: EdgeInsets.fromLTRB(
  RowMetrics.groupInset, FormMetrics.bodyTop, RowMetrics.groupInset,
  FormMetrics.bodyBottom + clearance)))`. Copy `EventLookSheet.show` /
  `CalendarFilterSheet.show`. The header's hairline is a `ValueNotifier<bool>`
  fed by the scroll controller, never `setState`.
- **Fixed box, unguarded** (the Dates sheet, the icon picker): the same
  route flags, `builder: FractionallySizedBox(heightFactor:
  FormMetrics.sheetHeightFactor)` → `Column(crossAxisAlignment: stretch)` of
  `FormSheetHandle`, `FormSheetHeader`, the sheet's own body (`Expanded`), an
  optional fixed footer. Route drag, no `PopScope`.
- **Form sheet** (the description sheet, the editor): `EventEditorSheet.show`'s
  route (`isScrollControlled: true, showDragHandle: false, enableDrag: false,
  backgroundColor: Colors.transparent, elevation: 0`) →
  `FractionallySizedBox(FormMetrics.sheetHeightFactor)` → `FormSheetFrame`
  (§3.8) holding the handle, the header, the body and the footer.
- **Header.** `FormSheetHeader(leadingIcon: Icons.close_rounded,
  leadingTooltip: l10n.cancel, leadingIdentifier:, onLeading:, title:,
  scrolled:, trailingInset: FormMetrics.headerActionInset, trailing:)`; the
  trailing is a `FormHeaderTextButton` or `const SizedBox.shrink()`.
- **Groups and rows**: `FormRowGroup`, `FormSectionLabel`, `FormPickerRow`,
  `FormSwitchRow`, `FormActionRow`, `FormMenuRow`, `FormCheckRow`,
  `FormSearchRow`, `FormCaption` — the `calendar-ui` table.

### 3.2 The agenda filters sheet (`AgendaFiltersSheet`), top to bottom

Header: ✕ (`agenda-filter-close`) · `upcomingFilters` "Filters" ·
`FormHeaderTextButton(label: l10n.apply, identifier: agenda-filter-apply)`,
always enabled (a no-op Apply pops the unchanged draft). Body scroll view
`Semantics(identifier: agenda-filter-sheet)`.

**Group 1** (no label):

1. **Period** — `FormMenuRow<_PeriodChoice>(glyph: Icons.date_range_rounded,
   label: upcomingPeriod, value:, selected:, identifier:
   agenda-filter-period, items:)`. `_PeriodChoice` is a private enum
   `{days7, days30, days90, restOfYear, wholeYear, custom}` derived from the
   draft (`hasCustomRange` → `custom`; else `periodMode`; `rollingDays` →
   the preset matching `rangeDays`, and a stored `rangeDays` outside
   `rangePresets` reads back through `upcomingPeriodDays(rangeDays)` with no
   item checked). Items, in order, with ids `agenda-filter-period-7` / `-30`
   / `-90` / `-rest-of-year` / `-this-year` / `-custom`: the three presets
   (`upcomingPeriodDays(n)`, `schedule_rounded`), `upcomingPeriodRestOfYear`
   and `upcomingPeriodWholeYear` (`calendar_today_rounded`),
   `upcomingPeriodCustom` "Custom range…" (`edit_calendar_rounded`). Value:
   `AgendaListView.rangeLabel(localeName, customStart, customEnd)` while
   pinned, else `AgendaFiltersSheet.periodModeLabel(l10n, periodMode,
   rangeDays)`. `onSelected`: a preset → `_update(_draft.copyWith(periodMode:
   rollingDays, rangeDays: n, clearCustomRange: true))`; a year mode →
   `copyWith(periodMode: mode, clearCustomRange: true)`; `custom` →
   `_pickCustomRange()` (today's method, unchanged), which writes both dates
   or nothing.
2. **Start from selected day** — `FormSwitchRow(glyph:
   Icons.my_location_rounded, label: upcomingFollowSelectedDay, value:
   followSelectedDay, identifier: agenda-filter-follow)`.

**EVENTS** (`calendarFilterSectionEvents`):

3. **Events** — `FormMenuRow<AgendaEventType>(glyph: Icons.event_rounded,
   label: upcomingShowEvents "Events", value:
   CalendarFilterSummary.eventTypeLabel(l10n, eventType), selected:
   eventType, menuWidth: FormMetrics.menuWidth, identifier:
   agenda-filter-events, items: [all, recurring, oneTime, none] with
   eventTypeIcon / eventTypeLabel and ids agenda-filter-events-all /
   -recurring / -one-time / -none)`.
4. **Categories** — `FormPickerRow(glyph: Icons.label_outlined, label:
   calendarCategories, value:, identifier: agenda-filter-categories, onTap:
   eventType == none ? null : _pickCategories)`. Value: `categoryIds.isEmpty`
   → `calendarFilterCategoriesAll` "All"; else the selected categories'
   labels in `visiblePlus(categoryIds)` order through `namesReadBack`; a
   selection whose ids no longer exist → `calendarFilterNoCategories`. Tap →
   today's `_pickCategories(categories)` (the allowlist inversion of D5)
   behind `_guarded`.
5. **Priority** — `FormPickerRow(glyph: Icons.flag_outlined, label:
   upcomingPriority, value:, identifier: agenda-filter-priority, onTap:
   eventType == none ? null : _pickPriorities)`. Value: empty →
   `upcomingPriorityAny`; else `EventPriorities.labelOf` ascending through
   `namesReadBack`. Tap → `FilterCheckListSheet.show(title: upcomingPriority,
   items: 1…5 with EventPriorities.iconFor / labelOf, identifier:
   SemanticsIds.filterListRow('priority-$p'), selected:)`; a non-null answer
   becomes `priorities` (an empty answer is "Any").

**ALSO SHOW** (`calendarFilterSectionAlsoShow`):

6. **Holidays** — `FormSwitchRow(glyph: CalendarFilterSummary.holidayIcon,
   label: upcomingShowHolidays, value: showHolidays, identifier:
   agenda-filter-holidays)`.
7. **Fasting** — `FormSwitchRow(glyph: CalendarFilterSummary.fastingIcon,
   label: upcomingShowFasting, value: showFasting, onChanged:
   FastingCalendar.isEnabled ? … : null, identifier: agenda-filter-fasting)`.

**DISPLAY** (`upcomingSectionDisplay`):

8. **Event rows** — `FormMenuRow<AgendaEventDisplay>(glyph:
   Icons.view_agenda_outlined, label: upcomingEventDisplayTitle, identifier:
   agenda-filter-event-rows, items: everyOccurrence
   (`upcomingEventDisplayEveryOccurrence`, `view_agenda_outlined`,
   `agenda-filter-event-rows-every`), perEvent (`…PerEvent`,
   `repeat_one_rounded`, `-per-event`), summary (`…Summary`,
   `summarize_outlined`, `-summary`))`.
9. **Fasting rows** — `FormMenuRow<AgendaFastingDisplay>(glyph: fastingIcon,
   label: upcomingFastingDisplayTitle, identifier:
   agenda-filter-fasting-rows, onSelected: FastingCalendar.isEnabled ? … :
   null, items: everyDay (`view_agenda_outlined`, `-every-day`), periods
   (`date_range_rounded`, `-periods`), summary (`summarize_outlined`,
   `-summary`))`.
10. **Holiday rows** — `FormMenuRow<AgendaHolidayDisplay>(glyph: holidayIcon,
    label: upcomingHolidayDisplayTitle, identifier:
    agenda-filter-holiday-rows, items: everyDay (`-every-day`), summary
    (`-summary`))`.

**Actions group** (no label, `trailingGap: false`):

11. **Reset filters** — `FormActionRow(glyph: Icons.restart_alt_rounded,
    label: calendarFilterReset, identifier: agenda-filter-reset, onTap:
    _isDefault ? null : _reset)` where `_isDefault` = `_draft.copyWith(query:
    '') == const UpcomingAgendaFilters()` and `_reset` is today's (query kept,
    sheet stays open).

The sheet keeps `_guarded` for its sub-routes (the picker, the check-list
sheet, the range picker) exactly as `CalendarFilterSheet` does.

**States on the canvas**: default (every value at its word, Reset at 38 %);
active (Period "90 days", Events "Recurring", Categories "Gym, Cardio +1
more", Priority "Highest, High", Holidays on, Fasting at 38 %, Fasting rows
at 38 %, Reset enabled); Events = "No events" (Categories and Priority at
38 %); the Period menu open; the German 200 % stress board.

### 3.3 The Dates sheet (`CalendarDatePickerSheet`)

The fixed box (D10). `Column(stretch)`: `FormSheetHandle` · `FormSheetHeader(
✕ date-picker-cancel · title · multi ? FormHeaderTextButton(save,
date-picker-save, onPressed: _selection.isEmpty && !allowEmpty ? null :
_answer({..._selection})) : SizedBox.shrink())` · multi: `_buildSummary` and
the `SegmentedButton<CalendarDatePickerView>` (unchanged) · `Expanded(body)`
· multi: `_buildFooter(…, bottomClearance)` (unchanged). Single mode keeps
the clearance on the month scroll view's bottom padding. The month view's
`headerTitleBuilder` returns a `Row` of the tappable title (unchanged, opens
`_openMonthYearJump`) and a 48 dp `IconButton(today_rounded, tooltip:
datePickerToday, onPressed: _jumpToToday)` under `AutomationId(
date-picker-today)`; the year view's ‹ year › row gets the same button after
the year. `_answer`, `_popped`, `_jumpToToday`, `_onDaySelected`,
`_openMonthYearJump`, the repeat panel and every static stay as they are.

### 3.4 The time pad (`TimePadSheet`)

The sub-sheet. `Focus(autofocus, onKeyEvent)` stays the root. `Column(min)`:
`FormSheetHandle` · `FormSheetHeader(✕ time-pad-cancel (tooltip cancel) ·
widget.title · FormHeaderTextButton(timePadDone, time-pad-done, onPressed:
entry.canFinish ? finish : null))` · `Flexible(SingleChildScrollView(…))` with
the readout, the caption band and the keypad unchanged, padding `(groupInset,
bodyTop, groupInset, bodyBottom + clearance)`.

### 3.5 The month/year picker (`MonthYearPickerSheet`)

The sub-sheet; the route-level `Padding(viewInsets)` and the `SafeArea` go.
`Column(min)`: `FormSheetHandle` · `FormSheetHeader(✕ month-year-close ·
monthYearPickerTitle · FormHeaderTextButton(apply, month-year-apply,
onPressed: () => _confirm(l10n)))` · `Flexible(SingleChildScrollView(padding
with clearance))` holding the `AnimatedSize` (wheels or typed entry,
unchanged, the typed field still `autofocus: true`) and, below it, one
`FormRowGroup(trailingGap: false)` of `FormActionRow(Icons.today_rounded,
datePickerToday, onTap: _goToCurrent, identifier: month-year-today)` and
`FormSwitchRow(glyph: Icons.keyboard_rounded, label:
monthYearPickerTypedEntry, value: _typing, onChanged: (_) => _toggleTyping(),
identifier: month-year-typed)`. `_confirm`, `_submitTyped`, `_bounded`, the
error captions (`monthYearPickerInvalid` / `monthYearPickerRange`) and the
wheels stay.

### 3.6 The description sheet (`EventDescriptionSheet`)

The form sheet through `FormSheetFrame` (§3.8). Header: ✕
(`description-close`, tooltip `cancel`, `onLeading: _leave`) ·
`eventDescription` · `ListenableBuilder(_revision) → FormHeaderTextButton(
eventDescriptionDone, description-done, onPressed: _withinLimit(_length) ?
_confirm : null)`. Below the header the status band keeps its
`ConstrainedBox(minHeight: statusBandHeight)`: `Row(Expanded(Column[if
(subject != null) Text(subject, bodySmall onSurfaceVariant, maxLines 1,
ellipsis), if (message != null) Text(message, …)]), SizedBox(12),
counter)`. Then `Expanded(ModernEditorWrapper)` and the bar with the
clearance — unchanged. `_isDirty` = `_controller.text != widget.initialText`;
`_leave()` = the editor's (`_leaving` latch, `_confirmLeave` with
`unsavedChanges` / `keepEditing` / `discardChanges`, pops `null`); `_confirm`
pops the text without asking. Money stays disabled by omission; `loadText`
seeding, the `_revision` relay and the bar's shortcut filtering stay.

### 3.7 The template picker, the icon picker, the sound sheet

Per D16, D17, D18. The icon picker's `Column(stretch)`: `FormSheetHandle` ·
`FormSheetHeader(✕ icon-pick-close · pickIcon · SizedBox.shrink())` ·
`Padding(horizontal: RowMetrics.groupInset, top: FormMetrics.bodyTop)` →
`FormRowGroup(trailingGap: false, children: [FormSearchRow(controller:
_searchController, hint: searchIcons, clearTooltip: clearSearch, onChanged:
_onQueryChanged, identifier: icon-pick-search)])` · `Expanded(groups |
results | FormCaption(noIconsFound, padding: FormMetrics.groupCaptionPadding))`
with the list views' bottom padding `bodyBottom + clearance`.
`_IconTile`, `_recent`, `_buildWrap`, the ranking and `_pick` stay.

### 3.8 The primitives (`lib/widgets/form_rows.dart`)

**`FormPickerRow.leading`** — `Widget? leading`; when set, the glyph slot is
the leading widget in a 40 dp box (`EventAvatar`), the row's min height is
`FormMetrics.titleRowMinHeight` and `dividerIndent` defaults to
`FormMetrics.dividerIndentTitle`; everything else (label · value, caption,
chevron, trailing button, one node) unchanged.

**`FormMenuRow.onSelected`** — `ValueChanged<T>? onSelected`; `null` draws
the row at `FormMetrics.disabledOpacity`, removes the ink and the tap, and
marks the node `enabled: false`; the menu never opens.

**`FormSheetFrame`** — the form sheet's shell, moved out of
`event_editor_sheet.dart` with its constants (`_dismissVelocity` 700,
`_snapBackDuration` 150 ms → `FormMetrics.sheetDismissVelocity`,
`FormMetrics.sheetSnapBackDuration`):

```dart
class FormSheetFrame extends StatefulWidget {
  const FormSheetFrame({
    super.key,
    required this.chrome,     // FormSheetHandle + FormSheetHeader (the drag surface)
    required this.body,       // the Expanded scroll view and any fixed footer
    required this.onLeave,    // ✕, back, system back, barrier, a dirty drag
    required this.isClean,    // () => bool; a clean drag pops through onDismiss
    required this.onDismiss,  // pops the route's "cancelled" result
  });
}
```

It owns `PopScope(canPop: false, onPopInvokedWithResult: … onLeave())`, the
`ValueListenableBuilder<double>` / `Transform.translate` over `_dragOffset`,
the `Material(color: pageGround, clipBehavior: antiAlias, top radius
sheetRadius)` with the `GlobalKey` the threshold reads, the `GestureDetector(
behavior: opaque, onVerticalDrag…)` over `chrome`, and the snap-back
`AnimationController` (`SingleTickerProviderStateMixin`). `_onDragEnd`:
`velocity > dismissVelocity || offset > height / 4` → `isClean() ?
onDismiss() : (snap back, then onLeave())`; else snap back. The editor keeps
`_leave`, `_confirmLeave`, `_popDiscarding`, `_isDirty` and passes them in;
its `_dragOffset` / `_snapBack` / `_onDrag*` / `_animateSnapBack` /
`_onSnapBackTick` / `_sheetKey` go. `test/widgets/event_editor_redesign_test.
dart`'s "leaving with unsaved changes" group (fling on `FormSheetHandle`, a
short drag snaps back, back, barrier) passes unchanged.

### 3.9 Copy and l10n

Load the `l10n` skill; every key in `app_en.arb`, `app_de.arb`, `app_ro.arb`
together, then `flutter gen-l10n`, then `untranslated.txt` equal to `{}`.

**New**

| Key | en | de | ro |
| --- | --- | --- | --- |
| `upcomingPeriod` | Period | Zeitraum | Perioadă |
| `monthYearPickerTypedEntry` | Type the date | Datum eintippen | Tastează data |

**Retitled** (same key, same meaning)

| Key | was | en | de | ro |
| --- | --- | --- | --- | --- |
| `upcomingPeriodCustom` | Custom | Custom range… | Eigener Zeitraum… | Interval personalizat… |

**Reused as is**: `upcomingFilters`, `apply`, `cancel`, `save`,
`eventDescriptionDone`, `calendarFilterSectionEvents`,
`calendarFilterSectionAlsoShow`, `upcomingSectionDisplay`,
`upcomingPeriodDays`, `upcomingPeriodRestOfYear`, `upcomingPeriodWholeYear`,
`upcomingFollowSelectedDay`, `upcomingShowEvents`, `upcomingEventTypeAll` /
`Recurring` / `OneTime`, `upcomingEventsHidden`, `calendarCategories`,
`calendarFilterCategoriesAll`, `calendarFilterNoCategories`,
`upcomingPriority`, `upcomingPriorityAny`, `upcomingShowHolidays`,
`upcomingShowFasting`, the nine `upcoming*Display*` item and title keys,
`calendarFilterReset`, `datePickerMultiTitle`, `datePickerSingleTitle`,
`datePickerToday`, `timePadDone`, `monthYearPickerTitle`, `eventDescription`,
`unsavedChanges`, `keepEditing`, `discardChanges`, `addFromTemplate`,
`quickAlarmRow`, `templateBlankEvent`, `pickIcon`, `searchIcons`,
`clearSearch`, `noIconsFound`, `iconGroupRecent`, `alertsSound`,
`alertSoundUseAppSetting`, `alertSoundPhoneDefault`,
`alertSoundChooseFromPhone`.

**Retired, each after `grep -rn <key> lib test tool`** (slice 5):
`upcomingFiltersReset`, `upcomingSectionPeriod`, `upcomingSectionShow`,
`upcomingClearRange`, `upcomingClearCategories`,
`monthYearPickerManualEntry`, `monthYearPickerWheelEntry`. (`close` stays —
nine other readers; `categoriesAllSelected` / `categoriesNSelected` stay with
`CategoryFilterTile` until Tier 4.)

### 3.10 Semantics ids (`lib/constants/semantics_ids.dart`, after `filterPresetDelete`)

```
agendaFilterOpen = 'agenda-filter-open'
agendaFilterSheet = 'agenda-filter-sheet'   agendaFilterClose = 'agenda-filter-close'   agendaFilterApply = 'agenda-filter-apply'
agendaFilterPeriod = 'agenda-filter-period'
agendaFilterPeriod7 / agendaFilterPeriod30 / agendaFilterPeriod90 = 'agenda-filter-period-7' / '-30' / '-90'
agendaFilterPeriodRestOfYear = 'agenda-filter-period-rest-of-year'   agendaFilterPeriodThisYear = 'agenda-filter-period-this-year'   agendaFilterPeriodCustom = 'agenda-filter-period-custom'
agendaFilterFollow = 'agenda-filter-follow'
agendaFilterEvents = 'agenda-filter-events'   agendaFilterEventsAll / -Recurring / -OneTime / -None = 'agenda-filter-events-all' / '-recurring' / '-one-time' / '-none'
agendaFilterCategories = 'agenda-filter-categories'   agendaFilterPriority = 'agenda-filter-priority'
agendaFilterHolidays = 'agenda-filter-holidays'   agendaFilterFasting = 'agenda-filter-fasting'
agendaFilterEventRows = 'agenda-filter-event-rows'   (+ '-every', '-per-event', '-summary')
agendaFilterFastingRows = 'agenda-filter-fasting-rows'   (+ '-every-day', '-periods', '-summary')
agendaFilterHolidayRows = 'agenda-filter-holiday-rows'   (+ '-every-day', '-summary')
agendaFilterReset = 'agenda-filter-reset'
datePickerToday = 'date-picker-today'
monthYearClose / monthYearApply / monthYearToday / monthYearTyped = 'month-year-close' / '-apply' / '-today' / '-typed'
descriptionClose = 'description-close'   descriptionDone = 'description-done'
templatePickClose = 'template-pick-close'   templatePickBlank = 'template-pick-blank'   static String templatePickRow(String id) => 'template-pick-$id'
iconPickClose = 'icon-pick-close'   iconPickSearch = 'icon-pick-search'
soundClose = 'sound-close'   soundInherit = 'sound-inherit'   soundPhoneDefault = 'sound-phone-default'   soundFromPhone = 'sound-from-phone'
```

Kebab-case, never renamed. `date-picker-cancel` / `date-picker-save`,
`time-pad-*` and `quick-alarm-row` keep their values.

## 4. Behaviour

### 4.1 Must not change

- **The agenda model.** `UpcomingAgendaFilters` keeps every field with its
  default: `periodMode` `rollingDays`, `rangeDays` 30, `priorities` `{}`
  (= every priority), `customStart` / `customEnd` null, `query` `''`,
  `showHolidays` / `showFasting` false, `eventDisplay` `everyOccurrence`,
  `fastingDisplay` `periods`, `holidayDisplay` `everyDay`,
  `followSelectedDay` false, `eventType` `all`, `categoryIds` `{}`
  (= every category); `rangePresets` `[7, 30, 90]`, `presetWindow`,
  `restrictiveFilterCount`, `withoutElapsedRange`, `copyWith(clearCustomRange:)`,
  the four codecs; the thirteen `SettingsKeys.calendarUpcoming*` keys and
  `SettingsService.getUpcomingAgendaFilters` / `saveUpcomingAgendaFilters`
  (one `setValues` transaction); `test/models/upcoming_agenda_filters_test.
  dart` and the three `test/services/upcoming_agenda_*_display_test.dart`
  pass unchanged.
- **The funnel.** `AgendaFiltersSheet.show(context, filters:) →
  Future<UpcomingAgendaFilters?>` — the draft on Apply, `null` on every other
  exit; the panel's `_openFilters` / `_openFiltersSheet` (the live query
  carried over the result), `_onFiltersChanged`, the 500 ms query-only
  persistence debounce, `_persist`, the anchor re-sync on `followSelectedDay`.
- **The panel's chrome.** The search field, the summary chips (one per
  narrowing axis, their icons and labels, the `if / else if` window chain,
  the ✕ that undoes one axis), the `Badge.count(chips.length)`, the tune
  icon and its `isSelected`, `upcomingRemoveFilter`, the anchor chip;
  `AgendaFiltersSheet.periodModeLabel` (the chip reads it).
- **The picker and the check-list sheet.** `CategoryPickerSheet.pickMulti`
  never collapses an empty answer; the agenda's inversion (`_pickCategories`:
  an empty allowlist opens with every offered row checked; an answer covering
  the offered set collapses to the empty set; an empty answer is stored as
  the empty set — today's doc comment at `agenda_filters_sheet.dart:112–133`
  moves with the method); `FilterCheckListSheet.show`; `CalendarCategories.
  visiblePlus(categoryIds)` as the offered rows; a hidden id inside the
  allowlist still listed.
- **The range picker.** `_pickCustomRange`'s `showDateRangePicker`, its bounds
  (2000-01-01 … 2100-12-31), its `DateTime.now()` read (the calendar-events
  skill's "leave the three surviving `now()` reads alone"), `EventAgenda.
  dateOnly` on both ends.
- **Reset's result**: `const UpcomingAgendaFilters().copyWith(query:
  _draft.query)`.
- **The overview page**: `CategoryFilterTile`, `_CategoryAvatarCluster`,
  `calendar_overview_page.dart:725–740` and `:587–611` untouched.
- **The seven sheets' contracts.** `CalendarDatePickerSheet.pickSingle` /
  `pickMulti` / `summaryLabel` / `datesValue` (signatures, `allowEmpty`,
  `initialView`, an empty multi result → `null` unless `allowEmpty`, the
  `_popped` latch, single mode popping on a day tap and on the month/year
  Apply); `TimePadSheet.pick` and `TimePadCaptions` (every `TimePadEntry`
  rule, the keypad ids, the 1.4 text-scale clamp on the keypad, the hardware
  keyboard, the pops on the last digit / `:00` / `:30` / AM / PM);
  `MonthYearPickerSheet.show` (the wheels, `_bounded` clamping, typed entry's
  parse and its two error captions, `_goToCurrent`); `EventDescriptionSheet.
  show` (Done pops the text, `null` otherwise; the limit and the grandfather
  rule; `loadText` seeding; no money; the `_revision` relay; the bar's
  utilities and counter-bound filtering); `EventTemplatePickerSheet.show` and
  the three `EventTemplateChoice` results, `quick-alarm-row` above the blank
  row, the quick-alarm row present with no templates; `IconPickerSheet.show`
  (the pop on tap, `recordRecentIconKey`, the "Recently used" section, the
  ranking and `matchesSettingsQuery`, exactly one `TextField`, results in
  `Wrap`s); `AlertSoundSheet.show` and `labelFor`, `AlertSoundPicked` /
  `AlertSoundPickerMissing` / `null`, the `system:default` and content-URI
  values, `_pickFromPhone`'s four outcomes, `_resolveTitle`, the row absent
  without `supportsSoundPicker`, "Use the app setting" only while
  `allowInherit`; the phone-volume rule of `docs/event-alerts-*`.
- **The seven sheets' callers** (§5) — no signature changes:
  `event_editor_sheet.dart`, `event_repeat_sheet.dart`,
  `fasting_schedule_sheet.dart`, `calendar_page.dart`,
  `event_detail_sheet.dart`, `alert_editor_sheet.dart`,
  `event_template_editor_sheet.dart`, `quick_alarm_sheet.dart`,
  `calendar_overview_page.dart`, `agenda_day_list_sheet.dart`,
  `event_look_sheet.dart`, `category_editor_sheet.dart`,
  `fasting_style_sheet.dart`, `calendar_settings_page.dart`.
- **The editor's behaviour** across the `FormSheetFrame` hoist: every case of
  `event_editor_redesign_test.dart` and the six older editor suites passes
  unchanged.
- **Data.** Nothing in this tier touches persistence, backup, CRDT fields or
  the alert planner / scheduler.

### 4.2 Deliberately changes

| Today | After |
| --- | --- |
| Agenda sheet: stock drag band, `titleMedium` header with a Reset text button, chips / segmented buttons / a switch tile, a pinned Apply bar | The sub-sheet shape, ✕ · Filters · Apply, eleven rows in five groups, Reset the last row (D1–D7) |
| Priority and Categories sections absent while events are hidden; Fasting chip and Fasting rows control absent while inert | Present and inert at 38 % (D4, D6) |
| Category chips up to twelve, a `CategoryFilterTile` past that, a "Show all categories" button | One picker row reading "All" / the names / "+N more"; the shared picker (D5) |
| Reset always enabled | Dimmed while the draft is the default (D7) |
| Dates sheet: 0.86, centred `titleLarge`, Today icon in the header, `FilledButton` Save | The 0.92 box, `FormSheetHeader`, Today in the month / year navigation row, Save a header text button (D10, D11) |
| Time pad: stock handle, centred title, `FilledButton` Done | The sub-sheet, Done a header text button (D12) |
| Month/year picker: title + tonal toggle, Today · Cancel · Apply bar, `Padding(viewInsets)` | The sub-sheet, Apply in the header, Today and "Type the date" as rows (D13) |
| Description sheet: stock handle, a two-line centred header, `FilledButton` Done, **no guard** | The form sheet on `FormSheetFrame`, the guard, the subject in the status band, Done a header text button (D14, D15) |
| Template picker: 0.7, centred title, `ListTile`s with `CircleAvatar`s | Content-tall, picker rows with `EventAvatar`, two action rows (D16) |
| Icon picker: 0.85, centred title, `SettingsSearchField` + `Divider`, "Clear search" button in the empty state | The 0.92 box, a pinned `FormSearchRow`, `FormSectionLabel`s, a caption (D17) |
| Sound sheet: stock handle, `titleLarge` title, `ListTile`s with drawn radios, no `useSafeArea` | The sub-sheet, exclusive check rows with a caption, `useSafeArea` (D18) |
| No ids on the agenda sheet, the panel's tune button, the month/year picker, the description sheet, the template rows, the icon picker, the sound sheet | §3.10 (D9) |

## 5. Facts from the tree (as of 2026-09-27; re-grep before editing)

The two explorer facts sheets of this session hold every line number; the
seven-sheet one is at `<scratchpad>/tier1-facts-seven-sheets.md` for the
implementing agents. The entry points:

- `lib/widgets/agenda_filters_sheet.dart` (652): `show` :47–58, `periodModeLabel`
  :35–45 (keep), `_lastEventType` :70–72 (**delete**), `_reset` :78–83 (keep),
  `_setEventsShown` :85–90 (**delete**), `_togglePriority` / `_toggleCategory`
  :92–110 (**delete**), `_pickCategories` :134–146 (keep with its comment),
  `_pickCustomRange` :151–171 (keep), `_eventTypeLabel` :173–180 (**delete**,
  use `CalendarFilterSummary.eventTypeLabel`), the three display label
  switches :182–216 (keep), `build` :218–292 (**replace**), `_buildPeriod`
  :294–359, `_buildLayers` :369–439, `_buildPriorities` :441–469,
  `_buildCategories` :471–532, `_buildDisplay` :534–579, `_displayControl`
  :585–631, `_SectionLabel` :634–652 (**all delete**).
- `lib/widgets/upcoming_agenda_view.dart`: `_openFiltersSheet` :1051–1060,
  the summary chips :1072–1166 (`periodModeLabel` :1093; the `none` chip icon
  `event_busy_rounded` :1129 region), the tune `IconButton` :1226–1236 — add
  `AutomationId(SemanticsIds.agendaFilterOpen)` around the `IconButton`, nothing
  else.
- `lib/utils/calendar_filter_summary.dart`: `eventTypeIcon` :54–60 (align
  `none` → `event_busy_rounded`), `eventTypeLabel` :65–72, `namesReadBack`
  :282–286, the icon constants :39–52.
- `lib/widgets/calendar_filter_sheet.dart`: the shape and the row code to copy
  — `show` :53–77, `_guarded` :174–182, `_pickCategories` :268–293 (the
  denylist one; the agenda's inversion differs), `_pickPriorities` :295–317,
  `_priorityValue` :417–424, `build` :444–672.
- `lib/widgets/calendar_date_picker_sheet.dart` (1019): `_show` :183–210
  (`showDragHandle: true` :198), `_jumpToToday` :252–262, `_answer` :285–289,
  `build` :353–470 (`FractionallySizedBox(0.86)` :395; the header `Row`
  :400–443 — **replace**; `_buildSummary` :484–513 and the `SegmentedButton`
  :446–464 keep), `_buildMonth` :515–608 (`headerTitleBuilder` :553–589),
  `_buildYear` :613–717 (the ‹ year › row :640–669), `_buildFooter` :820–844.
- `lib/widgets/time_pad_sheet.dart` (634): `pick` :62–81, `build` :192–303
  (the header `Row` :221–256 — **replace**; the body :257–300 keep).
- `lib/widgets/month_year_picker_sheet.dart` (620): `show` :38–65 (the
  `Padding(viewInsets)` :50–56 — **delete**), `_confirm` :159–165,
  `_toggleTyping`, `_goToCurrent`, `build` :356–436 (the header `Row`
  :374–396 and the bottom `Row` :411–432 — **replace**; `AnimatedSize`
  :402–409 keep).
- `lib/widgets/event_description_sheet.dart` (526): `show` :96–123 (literal
  `0.92` :112), `_revision` :164, `_confirm` :298, `_buildBar` :332–362,
  `build` :364–525 (the header `Row` :395–447 — **replace**; the band
  :451–497 — rework per §3.6; the editor :504–518 and the bar :519–522 keep).
- `lib/widgets/event_editor_sheet.dart`: `show` :213–243, the constants
  :270–271, the fields :330–337, `_leave` :1862–1872, `_popDiscarding`
  :1874–1876, the drag handlers :1878–1928, `build` :2690–2760 (`PopScope`
  :2697, `Transform.translate` :2703–2706, `Material` :2707–2715,
  `GestureDetector` :2719–2724) — the `FormSheetFrame` hoist.
- `lib/widgets/event_template_picker_sheet.dart` (142): `show` :43–54,
  `build` :57–141 — **replace** the body.
- `lib/widgets/icon_picker_sheet.dart` (406): `show` :42–57, `build` :214–248
  (the title :223–230, `SettingsSearchField` :231–238, `Divider` :239 —
  **replace**), `_buildGroups` :255–274, `_buildSection` :276–302,
  `_buildEmptyState` :327–352 (**replace** with the caption).
- `lib/widgets/alert_sound_sheet.dart` (277): `show` :67–79, `build`
  :176–234 (**replace** the chrome; keep `_choose`, `_pickFromPhone`,
  `_resolveTitle`), `_SoundOptionTile` :242–277 (**delete**).
- `lib/widgets/form_rows.dart` (1443): `FormSheetHeader` :128–221,
  `FormHeaderTextButton` :227–260, `FormPickerRow` :420–548, `FormCheckRow`
  :789–962, `FormSearchRow` :1250–1339, `FormMenuRow` :1365–1443.
  `lib/constants/form_metrics.dart` (125): add `sheetDismissVelocity`,
  `sheetSnapBackDuration`. `lib/constants/semantics_ids.dart` (219): insert
  §3.10 after :129.
- **Tests** — `test/widgets/agenda_filters_sheet_test.dart` (14 cases, all
  text finders; the assertions on the popped draft stay, the finders move to
  ids and menu items; case 1 flips per D6); `test/widgets/category_filter_
  sheets_test.dart` 'agenda filters sheet' :740–1024 (`scrollToCategories`
  drags to `CategoryFilterTile` — now the row by id; 'a short set keeps its
  chips' :750 and 'the clear button appears only with a selection' :768 are
  rewritten for the row and the picker; the seven picker cases keep their
  assertions); `test/widgets/upcoming_agenda_view_test.dart` (the chips —
  unchanged, must stay green); `test/widgets/calendar_date_picker_views_test.
  dart` (`save()` :86 = `widgetWithText(FilledButton, 'Save')` → by id;
  :213 / :268 `onPressed` null checks on the text button; `tapText('Cancel')`
  :256 is the repeat panel's, stays); `test/widgets/event_editor_redesign_
  test.dart` :459, :550, :1358 (`widgetWithText(FilledButton, 'Save').last`
  → `find.bySemanticsIdentifier(SemanticsIds.datePickerSave)` — with a text
  button `.last` would hit the editor's own Save); `test/widgets/time_pad_
  sheet_test.dart` (all by id — `onPressedOf` :81–85 reads the `FilledButton`
  under a digit id, unchanged); `test/widgets/event_description_sheet_test.
  dart` (`doneButton()` :117 → by id; the six `byIcon(close_rounded)` taps
  after an edit now meet the dialog — tap "Discard changes"; 'close returns
  null, discarding the edit' :132 and 'cancel is never disabled, even over
  budget' :251 go through the dialog; the heading cases :299–325 assert the
  subject in the band under the header); `test/widgets/event_template_
  picker_sheet_test.dart` (text finders, stay); `test/widgets/icon_picker_
  sheet_test.dart` (`enterText(find.byType(TextField))` :41 — one field;
  `results()` :48 over `Wrap`s — the search group adds none; 'an empty
  result offers a way back' :153 clears through the row's ✕ by tooltip
  `clearSearch`); `test/widgets/alert_sound_sheet_test.dart` (row texts,
  stay); `test/widgets/event_look_sheet_test.dart` :278–299 (the picker
  through the Look sheet, `enterText(find.byType(TextField))`, stays);
  `test/widgets/calendar_overview_page_test.dart` :246–260
  (`find.text('Apply')` on the month/year sheet — stays, the header's
  text button reads "Apply"); `test/widgets/agenda_day_list_sheet_test.dart`
  :963–971; `test/widgets/quick_alarm_sheet_test.dart` (time pad ids);
  `test/widgets/sheet_bottom_clearance_test.dart` (the time pad :505, the
  sound sheet :526, the description sheet :540–576 — its "first `Column`
  fills the box" assertion meets the frame, the date picker :578 and :710
  stay; gains four).
- **Flows**: `03_dates.txt` and `07_detail.txt` (`date-picker-save` /
  `-cancel`, "Year" / "Month" labels) stay valid; `02_editor_sheets.txt`
  (the Look sheet) unchanged; new `10_agenda_filters.txt` and
  `11_tier1_sheets.txt` (§6, slice 6).
- **Docs to update** (slice 6): `docs/calendar-events-feature.md` — the
  agenda filter IA paragraphs :2391–2437 and :3914–3932, the `CategoryFilterTile`
  bullets :5450 / :5488, the 2026-09-25 Dates-sheet addendum :5051, the
  2026-09-24 time-pad addendum :4918, the 2026-08-31 description addendum;
  `COPILOT_CONTEXT.md` :77–96 (the agenda filters and `CategoryFilterTile`
  sentences); `.claude/skills/calendar-events/SKILL.md` :86 (the tile's
  readers: the overview only), :126 (the filter IA line); `.claude/skills/
  calendar-ui/SKILL.md` :10 (the adoption count: sixteen sheets), the
  primitives table (`FormPickerRow.leading`, `FormMenuRow` disabled,
  `FormSheetFrame`), the sheet-chrome paragraph (the third shape sentence →
  D10's three), the ids paragraph; `docs/calendar-language-adoption-roadmap.md`
  §9 (Tier 1 → done) and its §2.1 note that the sound sheet's rows were
  `ListTile`s with drawn radios, not `RadioListTile`s.

## 6. Slices

### Slice 1 — Primitives, ids, copy

`FormPickerRow.leading`, `FormMenuRow.onSelected` nullable, `FormSheetFrame`
with the editor migrated onto it (§3.8), the two `FormMetrics` constants, the
`SemanticsIds` of §3.10, the ARB trio (§3.9's new and retitled keys; the
retirements wait for slice 5), `gen-l10n`. Tests: `form_rows_test.dart` gains
— a picker row with a leading widget is 56 dp with the title indent and one
node; a disabled menu row is faded, inert, `enabled: false`, opens nothing;
a `FormSheetFrame` pops through `onDismiss` on a clean fling and calls
`onLeave` on a dirty one and on back. The editor's whole suite green.

### Slice 2 — The agenda filters sheet

`AgendaFiltersSheet` rebuilt per §3.2 in the shape of §3.1; the panel's id;
`eventTypeIcon(none)` aligned. Tests: `agenda_filters_sheet_test.dart` — the
fourteen assertions kept with finders on ids and menu items (case 1 → present
and inert), plus: the Period menu's six items carry their ids and the current
one is checked; "Custom range…" leaves the draft alone when the picker is
dismissed; Events "No events" dims Categories and Priority; Reset is inert on
the default draft and enabled after a change; Apply pops the draft, ✕ /
barrier / back pop `null`; the Categories row reads "All" then "Gym, Cardio +1
more"; the German 200 % / 360 × 780 block. `category_filter_sheets_test.dart`
'agenda filters sheet' adapted (§5). `sheet_bottom_clearance_test.dart` gains
the sheet. `upcoming_agenda_view_test.dart` green unchanged.

### Slice 3 — Chrome-only pass A: the Dates sheet, the time pad, the month/year picker, the template picker

§3.3, §3.4, §3.5, D16. Tests: the suites of §5 adapted with assertions kept;
new cases — the Dates sheet's Save is disabled while empty and `!allowEmpty`
and its Today slot exists in the month and year views and not in the list;
the month/year picker's Apply pops the wheel date, the switch swaps in the
typed field, ✕ pops `null`; the template rows carry their ids and pop their
choice; the clearance test gains the month/year picker and the template
picker. The German 200 % block for each.

### Slice 4 — Chrome-only pass B: the description sheet, the icon picker, the sound sheet

§3.6, §3.7, D17, D18; load `markdown-engine` first. Tests: the description
suite — dirty ✕ asks, "Keep editing" stays, "Discard changes" pops `null`,
a clean ✕ pops silently, Done never asks, the subject sits in the band; the
icon picker — the search row carries its id, its ✕ restores the catalog, the
no-match caption; the sound sheet — the three rows' ids, the caption while a
URI is stored; the clearance test gains the icon picker.

### Slice 5 — Delete the old UI and the dead keys

Everything §5 marks **delete**; the retired keys of §3.9 after `grep -rn
<key> lib test tool` each; dead imports (`SettingsSearchField` in the icon
picker, `AppSpacing` where no longer read, `FilterChip` / `SegmentedButton`
readers). `dart analyze lib test` clean; the whole suite green;
`untranslated.txt` `{}`.

### Slice 6 — Device pass, review, docs

- After `qa run --fresh --seed tool/qa/fixtures/calendar.json`, two new flows
  (`$env:ANTA_QA_VIA = 'agent'`; every target verified with `qa look` first;
  a flow starts and ends on the calendar page in Day mode):

  ```
  # tool/qa/flows/calendar/10_agenda_filters.txt
  # The Upcoming agenda's filter sheet (docs/calendar-language-tier-1-roadmap.md):
  # every row by id, the Period menu, the Priority sub-sheet, "No events"
  # dimming the event rows, Apply, then Reset; the panel back on Day.
  tap "Upcoming"
  wait id:agenda-filter-open
  tap id:agenda-filter-open
  wait id:agenda-filter-apply
  expect id:agenda-filter-period id:agenda-filter-follow id:agenda-filter-events id:agenda-filter-categories id:agenda-filter-priority id:agenda-filter-holidays id:agenda-filter-fasting id:agenda-filter-event-rows id:agenda-filter-fasting-rows id:agenda-filter-holiday-rows
  shot 10_agenda_filters
  tap id:agenda-filter-period
  wait id:agenda-filter-period-90
  shot 10_period_menu
  tap id:agenda-filter-period-90
  wait id:agenda-filter-apply
  expect "90 days"
  tap id:agenda-filter-priority
  wait id:filter-list-done
  tap id:filter-list-priority-1
  tap id:filter-list-done
  wait id:agenda-filter-apply
  expect "Highest"
  tap id:agenda-filter-events
  wait id:agenda-filter-events-none
  tap id:agenda-filter-events-none
  wait id:agenda-filter-apply
  shot 10_no_events
  tap id:agenda-filter-events
  wait id:agenda-filter-events-all
  tap id:agenda-filter-events-all
  wait id:agenda-filter-apply
  scroll-to id:agenda-filter-reset --in id:agenda-filter-sheet
  shot 10_display
  tap id:agenda-filter-apply
  wait id:agenda-filter-open
  shot 10_agenda_filtered
  tap id:agenda-filter-open
  wait id:agenda-filter-apply
  scroll-to id:agenda-filter-reset --in id:agenda-filter-sheet
  tap id:agenda-filter-reset
  tap id:agenda-filter-apply
  wait id:agenda-filter-open
  tap "Day"
  wait id:calendar-add-event
  errors
  ```

  ```
  # tool/qa/flows/calendar/11_tier1_sheets.txt
  # The chrome-only sheets of Tier 1: the time pad and the description sheet
  # from the editor, the icon picker from the Look sheet, the template picker
  # from a long press, the month/year wheels from the grid title, the sound
  # sheet from the alert editor. Each is opened, shot and left through its ✕.
  tap id:event-row-qa-cal-lift
  wait id:event-detail-edit
  tap id:event-detail-edit
  wait id:event-starts
  tap id:event-starts
  wait id:time-pad-done
  shot 11_time_pad
  tap id:time-pad-cancel
  wait id:event-close
  tap "Open full editor"
  wait id:description-done
  shot 11_description
  tap id:description-close
  wait id:event-close
  tap id:event-look
  wait id:look-done
  tap "Icon"
  wait id:icon-pick-search
  shot 11_icon_picker
  tap id:icon-pick-close
  wait id:look-done
  tap id:look-done
  wait id:event-close
  scroll-to id:event-alert-add --in id:event-form
  tap id:event-alert-add
  wait id:alert-sheet-save
  tap "Alarm sound"
  wait id:sound-phone-default
  shot 11_sound
  tap id:sound-close
  wait id:alert-sheet-save
  key back
  wait id:event-close
  tap id:event-close
  wait id:event-detail-close
  tap id:event-detail-close
  wait id:calendar-add-event
  longpress "{{longdate+2}}"
  wait id:quick-alarm-row
  shot 11_template_picker
  tap id:template-pick-close
  wait id:calendar-add-event
  errors
  ```

  The month/year wheels are shot from the calendar's grid title (its label is
  the current month name — find it with `qa look`, `tap "#N"`, `wait
  id:month-year-apply`, `shot 11_month_year`, `tap id:month-year-close`) —
  append those steps once the title's node is known; if the alert editor's
  sound row label differs from "Alarm sound" in the dump, use what the dump
  shows. `qa flows calendar` twelve for twelve.
- The matrix: `qa set theme=dark locale=de text-scale=2.0`, then every sheet
  of §3 shot (the agenda sheet with its Period menu open, the Dates sheet in
  Month and List, the time pad, the month/year picker in both modes, the
  description sheet, the template picker, the icon picker with a query, the
  sound sheet) beside the canvas boards; `qa set theme=light locale=system
  text-scale=off`; the 360 × 780 and 412 × 915 sizes through the widget
  suites (the emulator is 427 dp wide). `qa errors` clean.
- Independent review by a fresh `fable-max` subagent briefed with this record
  and the diff: confirmed defects only; fix; rerun the gate.
- Docs in the same slice (§5's list): an addendum "## Addendum (2026-09-27):
  Tier 1 of the language adoption — the agenda filters sheet and seven
  chrome-only sheets" in `docs/calendar-events-feature.md` (the history, the
  decisions' why, every deviation from this record); `COPILOT_CONTEXT.md`;
  the two skills' rule lines; `docs/calendar-language-adoption-roadmap.md`
  §9. Narrative stays in the docs.

## 7. Definition of done

1. **Round-trip.** For every draft the old agenda sheet could express, the
   new sheet's Apply pops an equal `UpcomingAgendaFilters` (the rewritten
   suite compares popped drafts against constructor calls); the thirteen
   persisted keys are written by the untouched service; every chrome-only
   sheet pops exactly what it popped before for the same taps.
2. **One-handed on 360.** Every control a 48 dp target: rows, the Today
   slot, the search row's ✕, Done / Apply / Save and ✕ (menu items are the
   language's `FormMetrics.menuRowHeight` 44 dp, Filters D12); every header
   reachable without scrolling.
3. **Leaving.** ✕, back, the system back, the barrier and drag pop `null` on
   every sub-sheet and on the two fixed boxes; the description sheet asks
   on every one of those when dirty and leaves silently when clean; Done /
   Apply / Save pop the draft and never ask.
4. **Light and dark; en, de, ro; text scale 1.3 and 2.0.** No clipped label,
   no overflow; the Period value "1. Mai – 15. Mai 2026" wraps under its
   label at 200 % German; "Ab ausgewähltem Tag" (`upcomingFollowSelectedDay`
   as `app_de.arb` reads it) and "Datum eintippen" whole beside their
   switches; the German 200 % / 360 block in every suite.
5. **Keyboard.** The icon picker's typed query raises the keyboard without
   its header or its search row moving (the fixed box); the month/year
   picker rises with the keyboard as a content-tall sheet does (exactly what
   its old route-level `Padding(viewInsets)` did), its header staying on
   screen under the clamp; the description sheet's bar sits above the
   keyboard; every sheet's bottom padding at least the navigation bar (the
   clearance test, four new cases, the old ones green).
6. **Nothing moves under the finger.** Fasting and Fasting rows at 38 % while
   inert; Categories and Priority at 38 % under "No events"; Reset dims,
   never vanishes; the icon picker's search row stays put while results
   change; the Dates sheet's height is the same in Month, Year and List.
7. **Strings.** §3.9 in the three ARBs; `untranslated.txt` `{}`; the retired
   keys absent from `lib`, `test`, `tool`.
8. **Semantics.** Every icon-only button has a tooltip; every row one node;
   every id of §3.10 on its control (the `look` dump shows them); the menus'
   items are radio nodes with ids.
9. **Suites.** The model, service, panel and chip suites pass unchanged; the
   eight sheets' suites pass with finders moved and assertions kept; the new
   cases of §6 exist; `qa flows calendar` twelve for twelve through the
   agent; `qa errors` clean after the matrix.
10. **Docs** in the same change (§5's list; this record's §9 ledger).

## 8. Deferred

- **A range mode for the Dates sheet** (start + end on the grid) to replace
  Material's `showDateRangePicker` in the agenda sheet — a feature, not
  chrome; the range picker is the one Material dialog left in the calendar.
- **`CategoryFilterTile` / `_CategoryAvatarCluster` deletion** — with the
  overview page in Tier 4.
- **The agenda's summary chips opening their own axis' menu** instead of the
  whole sheet — the Filters record's open question, unchanged.
- **A shared header subtitle** (a muted second line inside the 48 dp header)
  — considered for the description sheet's subject and rejected: one title
  per header; the band already had the slot.
- **The Dates sheet's month navigation as an `AgendaPeriodNav`** (replacing
  `TableCalendar`'s own header) — the today slot is enough for the language;
  a nav swap is a grid change.
- **A two-line `FormSheetHeader` at large text scales.** At 200 % a title
  beside a long trailing action ellipsizes ("Datum w…" beside
  "Übernehmen"), and a title past ~20 characters ellipsizes even with an
  empty trailing slot ("Aus Vorlage hinzufüg…"); the editor's own title
  ("Ereignis be…") has done so since the redesign. The 48 dp one-line header
  is a language decision; letting it grow to two lines at ≥ 1.5× is the
  owner's call, and would touch every sheet at once.
- **`YearMonthTile` labels at 200 %** ("Sept.…") — the shared tile's own
  ellipsis, seen on the Dates sheet's year view and the overview alike.
- **Outside Tier 1, seen on the device pass:** the alert editor's title
  wraps mid-word at 200 % German (Tier 2); the editor's scope-chip reset
  button ellipsizes to "T…" (the editor); the description editor's body
  text ignores the text scale (re_editor draws at its own size — the
  markdown engine).

## 9. Ledger

| Slice | Status |
| --- | --- |
| Canvas ("Agenda Filters Mocks") | done 2026-09-27 — https://claude.ai/artifact/FGLdxuNj5a3ATaDCpiaKYo, eleven boards; the direction sticky carries the clearance arithmetic that corrected D2 |
| 1 — primitives, ids, copy | done 2026-09-27 — `FormPickerRow.leading` (+ `enabled`), `FormMenuRow.onSelected` nullable, `FormSheetFrame` (new `lib/widgets/form_sheet_frame.dart`, exported from `form_rows.dart`) with the editor migrated onto it, `FormMetrics.sheetDismissVelocity` / `sheetSnapBackDuration` / `rowLeadingSize`, the §3.10 ids, `upcomingPeriod` + `monthYearPickerTypedEntry` + the `upcomingPeriodCustom` retitle, eight new `form_rows_test.dart` cases; gate: `dart analyze lib test` clean, `flutter test` 6062 passed / 7 skipped / 1 failed (the known Windows-only `host_devices_test` case), `untranslated.txt` `{}`; deviations: `FormSheetFrame.body` is a `List<Widget>` (the column's remaining children, so the editor's docked bar stays a sibling of its scroll view rather than a nested column); `FormPickerRow.enabled` (default true) added because the disabled flag has to sit inside the row's one merged node — an outer `Semantics` around the row would have nested two `MergeSemantics` and split the id from the flag; `FormMetrics.rowLeadingSize` named for the 40 dp box; the frame keeps a local in-flight flag so a drag ending during an awaited `onLeave` snaps back, while the editor's `_leaving` latch stays where it was. |
| 2 — the agenda filters sheet | done 2026-09-27 — `AgendaFiltersSheet` rebuilt in the sub-sheet shape (✕ · Filters · Apply; eleven rows in five groups; a `_PeriodChoice` menu with today's `_pickCustomRange` behind "Custom range…"; Events over the whole `AgendaEventType` axis; Categories and Priority as picker rows over the shared picker and `FilterCheckListSheet`, dimmed under "No events" through `FormPickerRow.enabled`; the Fasting switch and the Fasting rows menu inert at 38 % while no tradition is configured; Reset filters the last action row, inert on the default draft with the query ignored, keeping the sheet open); `agenda-filter-open` on the panel's tune button; `eventTypeIcon(none)` → `event_busy_rounded`; `upcomingPeriodCustom`'s en description reworded from a chip to a menu item. Tests: `agenda_filters_sheet_test.dart` rewritten on ids (37 cases — the fourteen assertions kept; the Period menu's six items and checked state, a pinned range checking "Custom range…", a stored 14-day window checking nothing; the range dialog dismissed and confirmed through Material's day semantics; "No events" dimming Categories and Priority and "All" restoring them; Reset inert / enabled / keeping the sheet and the query; Apply, ✕, the barrier and the system back; the Categories and Priority read-backs; the German 200 % / 360 × 780 block with the Period menu opened; 360 × 780 and 412 × 915), `category_filter_sheets_test.dart` 'agenda filters sheet' adapted (two cases rewritten for the row and the picker, seven kept on the row's id), `sheet_bottom_clearance_test.dart` gains the sheet, `upcoming_agenda_view_test.dart` green unchanged; gate: `dart analyze lib test` clean, `flutter test` 6086 passed / 7 skipped / 1 failed (the known Windows-only `host_devices_test` case), `untranslated.txt` `{}`; deviations: the Period row is a `FormMenuRow<_PeriodChoice?>` — nullable so a stored `rangeDays` outside the presets checks no item, as §3.2 asks, without a sentinel enum value; `_PeriodChoice` carries its `mode` / `days` as enum fields, with an `initState` assertion that its day presets equal `UpcomingAgendaFilters.rangePresets`; the Holiday rows items wear the same glyphs as the fasting items for the same words (§3.2 named none); `_pickCategories`'s doc comment says "row" where it said "tile" and drops its sentence about un-checking chips below the threshold (both named the deleted UI); Apply pops `priorities` / `categoryIds` `Set.unmodifiable`'d as the Filters sheet does; no device pass (slice 6). |
| 3 — Dates sheet, time pad, month/year, template picker | done 2026-09-27 — chrome only, every entry point, result and caller of §4.1 untouched. The Dates sheet takes the fixed box (`FractionallySizedBox(FormMetrics.sheetHeightFactor)` in `_show`'s builder, `pageGround`, `sheetRadius`, route drag) with `FormSheetHandle` · `FormSheetHeader(✕ date-picker-cancel · title · FormHeaderTextButton(Save, date-picker-save) in multi mode, disabled while empty and `!allowEmpty`, an empty slot in single mode)`; Today leaves the header for a fixed `AgendaPeriodNav.slot` after the title in the grid's `headerTitleBuilder` row and after the year in the year view's ‹ year › row (`date-picker-today`, one `_todaySlot` helper, none in the list view); the summary row, the segmented button, the grid, the tiles, the list, the repeat footer and the clearance split are as they were. The time pad, the month/year picker and the template picker take the sub-sheet (`ConstrainedBox` at the factor, route drag, the header's hairline on a scroll notifier): the pad's Done is `FormHeaderTextButton(time-pad-done)` beside ✕ (`time-pad-cancel`), its body padded `(groupInset, bodyTop, groupInset, bodyBottom + clearance)`, readout / caption band / keypad untouched; the month/year picker loses the route-level `Padding(viewInsets)`, the `SafeArea`, the tonal toggle and the Today · Cancel · Apply bar for ✕ (`month-year-close`) · title · Apply (`month-year-apply`) and one group under the `AnimatedSize` of `FormActionRow(Today, month-year-today)` + `FormSwitchRow("Type the date", month-year-typed)`, the clearance on the scroll view's padding (`monthYearPickerManualEntry` / `WheelEntry` no longer read; slice 5 retires them); the template picker is content-tall with `FormPickerRow(leading: EventAvatar, caption: templateSummary, template-pick-<id>)` per template, then the quick-alarm and blank `FormActionRow`s (`quick-alarm-row` kept, `template-pick-blank`). Tests: `calendar_date_picker_views_test.dart` finders moved to ids (+ Save live while empty with `allowEmpty`, the header and ✕, single mode without Save, the Today slot in Month and Year and absent in List with a jump from each, German 200 % / 360 × 780); `event_editor_redesign_test.dart`'s three picker Saves by id; `time_pad_sheet_test.dart` (+ Done a header text button disabled on a 12-hour lone "0", German 200 % / 360 × 780); new `month_year_picker_sheet_test.dart` (ten cases: Apply pops the wheel date, the switch swaps modes both ways with the field seeded and selected, a typed date pops, an unreadable one and an out-of-range year keep the sheet with their captions, Today moves the wheels and leaves typed mode, ✕ / barrier / system back pop `null`, German 200 % / 360 × 780 in both modes); `event_template_picker_sheet_test.dart` (+ rows by id popping their template in order above the two action rows, the blank row's id, ✕ pops `null`, German 200 % / 360 × 780); `sheet_bottom_clearance_test.dart` gains the month/year picker (nav bar, and the tall-keyboard header case) and the template picker; `form_rows_test.dart` gains the leading-and-caption row. Gate: `dart analyze lib test` clean; `flutter test` 6111 passed / 7 skipped / 1 failed (the known Windows-only `host_devices_test` case); no ARB changed, `untranslated.txt` `{}`. Deviations: (1) `FormPickerRow` with `leading` **and** `caption` now takes the check row's two-line shape — the caption joins the label in one column, clamped at two lines, the row 62 dp with the avatar centred against both lines — because the glyph shape left the avatar on the label line with the caption hanging 18 px below its centre; `FormCaption` gained an optional `maxLines` for it; the glyph-and-caption shape (the editor's next occurrences) is unchanged. (2) The template picker became a `StatefulWidget` for the hairline notifier §3.1 gives every sub-sheet. (3) The month/year picker separates the wheels from the rows group by `RowMetrics.groupGap` (§3.5 named no number). (4) No device pass (slice 6). |
| 4 — description sheet, icon picker, sound sheet | done 2026-09-27 — chrome and the description guard; every entry point, result and caller of §4.1 untouched (`EventDescriptionSheet.show` / `IconPickerSheet.show` / `AlertSoundSheet.show` and their results, `loadText` seeding, the `_revision` relay, money by omission, `_buildBar` and its clearance, `_pick` / `recordRecentIconKey` / the ranking, `_choose` / `_pickFromPhone` / `_resolveTitle` / `labelFor` and the gateway calls). The description sheet is a form sheet on `FormSheetFrame` in the editor's route (`enableDrag: false`, transparent, the frame paints the ground) at `FormMetrics.sheetHeightFactor`: ✕ (`description-close`, tooltip cancel, `onLeading: _leave`) · Description · `FormHeaderTextButton(Done, description-done)` under the `_revision` relay, disabled past the limit; `_isDirty` / `_leaving` / `_confirmLeave` / `_leave` as the editor's, `_confirm` never asking, `onDismiss` popping `null`; the subject moved into the status band's first line (muted, one line, ellipsized) above the caption / over-limit line, the counter still right. **The discard dialog is shared**: `AppDialogs.confirmDiscard(context)` (new, `lib/widgets/app_dialogs.dart` — `form_rows.dart` stays free of the localizations) builds the editor's `AlertDialog` verbatim (title `unsavedChanges`, `TextButton(keepEditing)` → false, `FilledButton.tonal(discardChanges)` → true) and `EventEditorSheet._confirmLeave` now calls it; the editor's suite is green unchanged. The icon picker takes the fixed box (`FractionallySizedBox(sheetHeightFactor)`, `pageGround`, `sheetRadius`, route drag) with `FormSheetHandle` · `FormSheetHeader(✕ icon-pick-close · Choose icon · empty)`, a pinned `FormRowGroup(trailingGap: false)` of one `FormSearchRow(icon-pick-search, clearTooltip: clearSearch)` between the header and the grid, `FormSectionLabel`s over the wraps with `RowMetrics.groupGap` between sections, the list views padded `(groupInset, groupGap, groupInset, bodyBottom + clearance)`, the no-match state one `FormCaption(noIconsFound, groupCaptionPadding)` under the search group; `SettingsSearchField`, the `Divider`, `_buildEmptyState` and `_clearQuery` (nothing called it — the row's ✕ clears and reports itself) are gone. The sound sheet is a content-tall sub-sheet (`ConstrainedBox` at the factor, `useSafeArea: true`, route drag, the header's hairline on a scroll notifier): ✕ (`sound-close`) · Alarm sound · empty, one `FormRowGroup(trailingGap: false)` of `FormCheckRow(exclusive: true)`s — `sound-inherit` (only while `allowInherit`), `sound-phone-default`, `sound-from-phone` (absent without `supportsSoundPicker`, `caption:` the phone's name while a URI is stored, inert while `_picking`); `_SoundOptionTile` and the `AppSpacing` import are gone, its "reserved the moment a picked sound is stored" comment now on the caption. Tests: `event_description_sheet_test.dart` rewritten on ids (21 cases — every assertion kept; Done never asks; a dirty ✕ shows "Unsaved changes", Keep editing keeps the sheet and the text, Discard changes pops `null`; a clean ✕, the system back, the barrier and a fling on the handle pop `null` silently and ask when dirty; typing back to the original is not dirty; the six edited-then-closed cases leave through the dialog; the subject sits in the band below the header and outside it, a long name never squeezes the title (measured against the unconstrained paragraph), an untitled event reserves no empty line; German 200 % / 360 × 780 crossing the limit with the editor still, leaving through the German dialog); `icon_picker_sheet_test.dart` (the section headings found through a `FormSectionLabel` predicate — the label uppercases; the no-match case clears through the row's ✕ by tooltip and asserts no "Clear search" button; + the id on the one `TextField`, the header with no text button and ✕ popping `null`, the search row's rect unchanged across a query, a no-match and a clear, German 200 % / 360 × 780); `alert_sound_sheet_test.dart` (+ the three ids as radio nodes with the stored one checked and no `ListTile`, the caption inside the phone row's node only while a URI is stored, ✕ popping `null` with no text button, German 200 % / 360 × 780 with every row ≥ 48 dp); `sheet_bottom_clearance_test.dart` gains the icon picker (the grid's list padding ≥ the nav bar with the search group above it) and its tall-keyboard header case; the description and sound cases pass unchanged (the frame's outer `Column` is still the sheet's first). `event_look_sheet_test.dart` and `event_editor_redesign_test.dart` green unchanged. Gate: `dart analyze lib test` clean; `flutter test` `01:43 +6130 ~7 -1` (the known Windows-only `host_devices_test` case); no ARB changed, `untranslated.txt` `{}`. Deviations: (1) the band reserves the subject's line — `statusLineHeight × (subject == null ? 2 : 3)` — where D14 said "minimum height unchanged": the reservation exists so the two-line over-limit message never moves the editor, and a permanent subject line inside a two-line reservation would have left it one line to grow into (the German case pins it). (2) `_isDirty` compares against the text the controller holds after `loadText`, not `widget.initialText` — a line ending the load normalises must not make an untouched sheet ask. (3) The band's inset is `RowMetrics.groupInset + RowMetrics.sectionLabelInset` (the old 20, now named, keeping the text on the editor's 16 dp behind its 4 dp inset), its bottom air `RowMetrics.sectionLabelBottomPadding` (6, was 4), the message-to-counter gap `RowMetrics.gap` (14, was 12). (4) The icon picker's header carries no `scrolled` hairline — it sits over the pinned search group, not over the grid — and the air between a section label and its wrap is the label's own 6 dp (the 8 dp `SizedBox` went with the old label). (5) No device pass (slice 6). |
| 5 — delete the old UI and the dead keys | done 2026-09-27 — slices 2–4 had already deleted every builder §5 marks; the seven keys of §3.9 retired from the three ARBs after `grep -rn` found no reader (en with their `@` blocks), `gen-l10n`, `untranslated.txt` `{}`, `dart analyze lib test` clean, `flutter test` `+6130 ~7 -1` (the known Windows case) |
| 6 — device pass, review, docs | fix round done 2026-09-27 (D24, on the device pass and the review's findings; every entry point, result and caller of §4.1 untouched) — the Dates sheet's weekday row takes the calendar page's height and style through a hoisted `CalendarDaysOfWeek` (new `lib/utils/calendar_days_of_week.dart`; the page reads it too, its inline `dowStyle` gone); its month title wraps to `FormMetrics.periodTitleMaxLines` (2) centred, in a box measured over the year's twelve titles (`_monthTitleHeight`, a `LayoutBuilder` at the text's own constraints) so the row is one height for the whole year rather than growing between "Juli" and "September"; `HeaderStyle(headerPadding: zero)` **and** both chevron margins zero, so ‹ title [today] › is `AgendaPeriodNav`'s 48 dp row in width as well (the 32 dp the margins gave back is what "September" needs on one line at 200 % on 360 dp); the time pad's caption band is `FormMetrics.timePadCaptionLines` (2) lines of `bodyMedium` measured through `TextPainter.preferredLineHeight` at the ambient scale, `maxLines` 2, still centred and a live region; `_WheelLabel` sits in a `FittedBox(scaleDown)`; the typed entry fills the wheels' box (`_itemExtent × _wheelRows`, field at the top) so the swap never resizes the sheet; `FormMetrics.sheetDismissFraction` (0.25) read by the frame; the frame's drag `GestureDetector` is `excludeFromSemantics` and the pad's root `Focus` `includeSemantics: false`; `look-close` / `look-icon` / `look-color` (the colour id a container node above the swatches — a merge would fold eighteen buttons into one) and flow 11 taps `id:look-icon`; the `periodModeLabel` doc, six en `@` descriptions, `FormSearchRow`'s and `sheetHeightFactor`'s docs reworded; D23's band — `statusLineHeight × (subject && caption ? 3 : 2)`, over the limit only the message (the subject hidden with the caption), `FormMetrics.statusLineFactor` naming the band's 1.4. Tests: `time_pad_sheet_test.dart` (+ the title its own node with no focus flag; the German 360 case pins a two-line band with the caption inside it, a 600 dp case the whole two-line wrap), `event_description_sheet_test.dart` (the German case now asserts the message alone on two lines with the subject and caption gone and the editor's rect unmoved, both back under the limit; + two lines for a subject alone and three with a caption, the band the header's neighbour; + the title a text node without scroll actions), `month_year_picker_sheet_test.dart` (the German case + the selected month in a scale-down box inside its wheel, the header and the `AnimatedSize` box unmoved across the swap and under the error caption, the caption inside the box), `calendar_date_picker_views_test.dart` (+ the 48 dp row on a wide surface, the two-line title with its year and the row's height constant across months at 200 %; the German 360 case pins `maxLines` / `softWrap` and the weekday style — the test font's em-square glyphs are twice Roboto's width, so the wrap itself is asserted at 600 dp), `event_look_sheet_test.dart` (+ the three ids: the icon row one tappable node, the colour node with swatch children). Gate: `dart analyze lib test` clean; `flutter test` `01:42 +6137 ~7 -1` (the known Windows-only `host_devices_test` case); `gen-l10n` (en descriptions only), `untranslated.txt` `{}`. Device: `qa run --fresh --seed calendar.json`, `flows calendar` 12/12; at dark / de / 2.0 the Dates sheet's Month view (labels whole, "September / 2026", the Today slot 144 px = 48 dp at 1×), the lift time pad ("Endet um 19:30 · 1 Std. 30 / Min." on two lines in a 240 px band), the month/year picker in both modes (header and rows at the same y), the description sheet (subject + two-line scope caption filling a three-line band, the title a plain node), the Look sheet's three ids in the dump, the editor's title a `View`, `qa errors` clean; matrix restored, the app left up. Not done here: the independent review and the docs pass of this slice; `agenda_month_grid.dart` (Tier 2–3) still carries the package's default weekday style. |
