# The calendar guide page, and the newcomer review (2026-10-29)

**Status: BUILT 2026-10-29, uncommitted at the time of writing (Fable 5.1
lead; five Opus `general-purpose` researchers, one `implementer` with one
fix pass, one `reviewer`, one `design-reviewer`, one `qa-runner`). The gate
is green: `dart analyze lib test` clean, `flutter gen-l10n` with
`untranslated.txt` `{}`, `flutter test` +10800 ~10 −1 (the one red the
documented Windows-only `host_devices_test` case), `qa pass calendar
-d emulator-5556` 27/27 on the first run, `qa errors` clean; the guide's
screenshot in en 1.0, de 2.0 and ro 1.0 shows the quotes, the dashes and ș/ț
as glyphs.** The owner is handing ANTA to his wife, who has never used a
calendar app, and asked for a page that explains the calendar, reached from
the calendar's menu, plus the functionality changes a first-time user needs
and an honest read of whether the calendar is well made. §2 is the page as
built (decisions D1–D12), §3 the five researchers' walkthrough-driven audit
(N1–N157, verbatim, each CONFIRMED or PLAUSIBLE), §4 the proposals ranked
for the owner, §5 the questions only the owner can answer. Nothing in §3 or
§4 was built in this change: the guide describes the app as it is, traps
included, and the two lines that describe a trap (D9, D11) are to be
retired with the fix.

## Contents

- §0 How to run this
- §1 The ask, and what was researched
- §2 The guide page — decisions D1–D12, the must-not-change list
- §3 The newcomer review — the ledger, by area (A–E)
- §4 Proposals for the owner, ranked
- §5 Questions for the owner
- §6 Deferred

## 0. How to run this

The page was built in one slice from
`frontend/anta` on Windows: a Fable 5.1 lead wrote the content spec (every
key in en/de/ro with its placeholder map) and this record; five Opus 5.5
`general-purpose` researchers (read-only, one area each: the calendar
page, events, the overview, settings, alerts) wrote the walkthroughs the
content was taken from and the audits of §3; one `implementer` (Opus 5.5)
built the slice from the spec; one `reviewer` (code), one `design-reviewer`
(look, in a fresh context) and one `qa-runner` (`qa pass calendar
-d emulator-5556`, 27 flows) closed it. A follow-up that builds a §4
proposal is its own slice: one `implementer`, one `reviewer`, the suite,
and the calendar pass when a screen changes.

The gate for the page: `dart analyze lib test`, `flutter gen-l10n` with
`untranslated.txt` empty, the whole `flutter test` suite, then the device
pass. Skills: `calendar-events`, `calendar-ui`, `ui-language`, `l10n`.

## 1. The ask, and what was researched

The owner (2026-10-29): add an entry to the calendar's menu and a route
with a simple page that helps a newcomer understand how the calendar works;
research the whole calendar for what she will use and how; while
researching, check whether the functionality is good and well made; then
propose functionality changes for a first-time calendar user.

The calendar page has no drawer — its menu is the ⋮ (Alerts · Export ·
divider · Calendar settings) — so the entry went there (D1). Five
researchers read the code, the ARB, the saved device flows and the feature
doc by section, and each returned a walkthrough in the app's own words, a
vocabulary table (where one word means two things), an audit for a
non-technical first-time user, and questions for the owner. Their reports
are the raw material of §2's content and §3's ledger. One thing they found
about the docs: `docs/calendar-events-feature.md` §3.2, §3.3 and the v26,
v28 and v37 addenda describe editor rows that have since moved or gone
(N58); the code was the truth for the guide.

## 2. The guide page — decisions D1–D12

The defaults the lead chose, lettered so the owner can reverse any of them
in one line.

- **D1 — Where it lives.** A row in the calendar's ⋮ menu, below the
  divider and before "Calendar settings", which stays last (the rule the
  menu's `///` states: every ⋮ in the app ends with its Settings row). The
  overview shares that menu, so the row shows there too. Nothing in the
  drawer: the drawer's Calendar group is for destinations she returns to;
  the guide is read once and found again from the place it explains.
- **D2 — One name.** The row and the page share one string, "How the
  calendar works" (`calendarGuideTitle`): she taps a name and lands on a
  page with that name. The glyph is `Icons.help_outline_rounded`, the one
  "?" every phone user knows.
- **D3 — The idiom.** A settings-kit page (`SettingsAppBar` ·
  `SettingsSearchField` · `SettingsSectionList`), composed as
  `calendar_appearance_page.dart` composes its kit, minus the preview, the
  folding, the footer and the loading state: the page reads no service. The
  kit brings the search ("Search the guide"), the section cards with their
  tinted icon chips, light and dark, and the chrome Calendar settings has,
  so the page sits beside Calendar settings looking like family. No folding
  (a folded section is one more thing to explain) and no footer.
- **D4 — Rows are read, never pressed.** Each row is a glyph, a title and
  a paragraph in a `MergeSemantics` (TalkBack reads one node per row), with
  no ink, no tap and no chevron: a guide row that opened the thing it
  describes would read as "tap to read more" and then leave the page.
- **D5 — The guide quotes the app, it never retypes it.** Every label the
  text names — Save, All day, Repeat, Add alert, Calendar settings, Holiday
  set, Week starts on … — is an ARB placeholder filled at runtime with the
  app's own string (`“{save}”` ← `l10n.save`), in every language. A label
  rename reaches the guide for free; the compiler catches a label retyped
  in place of its placeholder, and
  `test/l10n/calendar_guide_placeholders_test.dart` catches a translation
  that drops one (every `{name}` declared in `en` must appear in the `de`
  and `ro` value). The snooze word is `alarmSnoozeMinutes` with the default
  length; because the snooze and the silence lengths are settings, the
  prose around them names no minutes. The quotes are the language's: en
  “…”, de „…“, ro „…”. The reviewer's rule for the content: a sentence
  never retypes a label even outside quotes ("there is no Save button" is
  "there is no “{save}” button").
- **D6 — The content.** Six sections, 31 rows, in the order a first week
  unfolds: the calendar screen (the month, the bars, the panel, the
  formats) · events (add, time, categories, repeat, read/change/delete,
  notes, nothing-saved-until-Save, attendance, templates) · reminders and
  alarms (nothing rings unless you ask, reminder vs alarm, permissions, when
  it goes off, open ANTA now and then, the quick alarm, the Alerts hub) ·
  finding things (search, the overview, filters hide-never-delete) · make it
  yours (where the settings are, holidays, week start, categories,
  language/dark mode/text size) · good to know (opening the calendar, going
  back, the rest of ANTA). An intro paragraph above the first card says how
  to come back. The overview gets one row — the overview researcher's
  verdict was "an expert page, one paragraph" (§3 C). Presence tracking and
  templates get one row each at the end of Events, because she will meet
  the Track presence switch the first time an event repeats and the
  template picker the first time she holds the + button too long.
- **D7 — The text roles.** Title: the kit's 14 / 500. Paragraph: 14 / 400
  `onSurfaceVariant`, line height 1.4 (`SettingsEntry.descriptionStyle`
  over the kit's 12 px caption, which is for one-liners). Glyph: 24 px
  `primary`, as the calendar settings page's leading icons; decorative
  (`ExcludeSemantics`). The section icons are the Material glyph nearest the
  idea; a row's glyph is the icon the app itself uses for the thing where
  one exists (today, alarm, the funnel, public holidays).
- **D8 — The route.** `AppNavigator.toCalendarGuide` is a stamped push
  (`NavDestinationKind.calendarGuide`, appended last — the first twelve
  names are persisted), so a relaunch lands back on the guide like any
  sub-page, and `reopensDrawerOnPop` stays false (reached from a feature,
  not the drawer). The calendar page does not reload on return: the guide
  changes nothing.
- **D9 — The honest row.** "Open ANTA now and then" tells her that a
  daily reminder needs the app opened every day or two. That is the alert
  horizon (`kAlertHorizon.perAlert` 2; re-planned only at launch, resume
  and after an alarm rings — N125, §4 P16). The row goes when the gap
  closes.
- **D10 — Vocabulary follows the app, per language.** English: alert
  (umbrella), reminder, alarm. German: Erinnerungen (the umbrella "Alerts"),
  Mitteilung (the Reminder tier), Alarm. Romanian: Alerte, Notificare,
  Alarmă. The section title in German is therefore "Erinnerungen und
  Alarme", not "Erinnerungen und Wecker".
- **D11 — The recovery lines.** Two sentences describe a trap rather than
  a feature, because she will hit it: "If the days ever shrink to one or
  two rows, you swiped up on them — pick Month from that menu again" (the
  vertical format swipe, N3) and the all-day caveat under Reminder or alarm
  (N126). Each is retired with its fix (§4 P4, P7).
- **D12 — Ids and the flow.** `calendar-guide-open` on the ⋮ row,
  `calendar-guide` on the list, `calendar-guide-<slug>` on every row (the
  slugs are in the content spec and the page). The device pass gains
  `26_guide.txt` (open the menu, open the guide, two rows present, back),
  and `08_header.txt` expects the new row. Suites:
  `test/widgets/calendar_guide_page_test.dart` (every title, the search in
  en and on a German placeholder word, the live labels in en and de, de/ro
  at 2.0 on both phone sizes in both themes, the ids, rows are not
  buttons), `test/l10n/calendar_guide_placeholders_test.dart`, the updated
  `calendar_header_menus_test.dart` and the seven new keys sorted in
  `test/l10n/reminder_word_test.dart`. The flow scrolls inside the list
  (`--in id:calendar-guide --max 40`) before each expect, because the kit's
  `ListView` builds only what is near the viewport.

**Must not change (for whoever touches the page):** the ⋮ order with
Calendar settings last; the placeholders — never retype a label into the
guide text; the row ids; the settings kit and `form_rows.dart` (the page
adds no primitive and no `FormMetrics` number); the enum's existing order.
A label the guide should start quoting gets a placeholder, not a retyped
word. A new row gets a slug, an icon and the three languages in one change.

## 3. The newcomer review — the ledger

Five read-only researchers, one area each, 2026-10-29, on `ea4b6f6f`. Each
item is the researcher's own line: `[severity] [CONFIRMED | PLAUSIBLE]
file:line — what happens — what a newcomer expects — the smallest fix`.
CONFIRMED means seen in code, a test or the ARB; PLAUSIBLE means inferred.
Severity is the researcher's; §4 is the lead's ranking across areas, so an
item's weight for the owner is its §4 place, not its letter here. Nothing
here was built; the ids are `N1`–`N157` across the five areas. The
researchers' full walkthroughs (the taps and labels the guide was written
from) are not reproduced; the guide itself is their record.

The 2026-10-26 calendar review (`docs/calendar-review-2026-10-26.md`,
C1–C171) looked at correctness; this one looked at a first-time user, and
its findings are new — the overlap is small (the Weekend bar, the filter
chips default, the doc drift).

### 3.A — The calendar page (N1–N31)

- **N1** [major] [CONFIRMED] day_summary_panel.dart:323, day_timeline_view.dart:192/254, agenda_list_view.dart:948-1030, agenda_day_list_rows.dart:561 — Tapping an event does three different things:
   - Day panel and Timeline: open the detail sheet.
   - Upcoming card: only moves the grid selection, so nothing visible happens (literally nothing while the panel is expanded).
   - Day list row: closes the sheet.

   A newcomer expects a tap to open the event everywhere. Fix: an Upcoming card tap calls `onShowEvent(event, day)` as the day panel does (select the day too).
- **N2** [major] [CONFIRMED] calendar_page.dart:1393-1437/2155, calendar_add_fab.dart:276-279 — Templates and "Alarm…" are reachable only by a long press (on a grid day or on +). There is no visible affordance, and the + tooltip is manual, so a long press gives no hint. "Set an alarm" will never be found. Fix: tapping + opens a chooser (Event · Alarm… · templates), or "Alarm…" goes in the ⋮.
- **N3** [major] [CONFIRMED] calendar_page.dart:2162 + table_calendar.dart:338-350 — A vertical swipe on the grid changes Month → 2 weeks → Week. Swiping up "to scroll" shrinks the calendar, with no clue how to undo it. Fix: `availableGestures: AvailableGestures.horizontalSwipe` (the title menu keeps the formats).
- **N4** [major] [CONFIRMED] calendar_appearance.dart:300, calendar_page.dart:862-906 — Filters (and a picked saved filter) are saved across restarts and hide events. With the chip row off by default, the only cue is a small badge number. "My events disappeared." Fix: default `showFilterChips` to true, or a one-line "Filtered · Show everything" bar above the grid.
- **N5** [major] [CONFIRMED] calendar_bottom_panel.dart:463-470, upcoming_agenda_filters.dart:186-187 vs calendar_grid_filters.dart:129-130 — The two "Filters" sheets disagree:
   - The grid's Filters reach the grid, Day and Timeline; Upcoming honours only the hidden categories (e.g. Priority "Highest" on the grid still lists every priority in Upcoming).
   - Upcoming has its own sheet with the same row names and other defaults (Holidays on vs off), so a holiday on the grid is absent from Upcoming.

   Fix: name the scopes ("Calendar filters" / "Upcoming filters") and turn Upcoming's Holidays on by default.
- **N6** [major] [CONFIRMED] calendar_bottom_panel.dart (`_syncAnchor`), upcoming_agenda_filters.dart:191 — In Upcoming mode a grid day tap changes nothing in the panel (only the + label). Fix: default "Start from selected day" on, or switch the panel to Day on a grid tap.
- **N7** [major] [CONFIRMED] public_holiday_service.dart:34, public_holidays.dart:362-368 — The holiday set defaults to "Christian (Western)" whatever the locale. In Romania that means Western Easter and no Romanian national days. Fix: seed the set from the locale on first run (ro → Romania, de → Germany), or ask once.
- **N8** [major] [CONFIRMED] calendar_bottom_panel.dart:506 (`_labelsFit`), calendar_add_fab.dart (`fabLabelMaxTextScale` 1.5) — With enlarged phone text (English ≥ 1.2, German ≥ 1.1) Day / Timeline / Upcoming become three bare icons; the + loses its label at 1.5. Fix: let the bar take two lines, or keep labels to 1.3+.
- **N9** [minor] [CONFIRMED] day_bars_resolver.dart:27-44, calendar_day_bars.dart:91-94, day_summary_panel.dart:116 — Every Sat/Sun:
   - carries a "Weekend" bar that looks like an event and takes one of the 3 slots: 3 events show 2 bars + "+2", the weekend counted inside the +2;
   - the panel lists a "Weekend" row and counts it ("1 entry" on an empty Sunday).

   Fix: no weekend bar or row by default (the weekend highlight setting exists), or leave the weekend out of the count and the overflow.
- **N10** [minor] [CONFIRMED] day_summary_panel.dart:162 — The empty day says "No events for this day" with no next step. Fix: add "Tap + to add an event".
- **N11** [minor] [CONFIRMED] agenda_list_view.dart:837-838, upcoming_agenda_view.dart:1361 — An empty Upcoming always says "Try a longer period or a lower priority", even on an empty calendar with nothing filtered. Fix: a hint chosen by the cause.
- **N12** [minor] [CONFIRMED] day_summary_panel.dart:~210-225 — The presence toggle is an unlabelled glyph (event_busy / event_available) that acts at once, with no Undo and no message, so an accidental tap is invisible. Fix: snackbar with Undo, or a labelled chip.
- **N13** [minor] [CONFIRMED] calendar_page.dart:2033-2037, 1941-1960 — "Go to today" is an unlabelled 36 dp glyph; the chevrons are 40 dp and announce no label (table_calendar's `CustomIconButton` has none). Fix: a 48 dp "Today" text button; chevron icons with `Semantics` labels.
- **N14** [minor] [CONFIRMED] calendar_header_menus.dart:126-216 — Month / 2 weeks / Week and Overview live only behind the small ▾ beside "Calendar". Fix: explain in the guide, or add a visible format control.
- **N15** [minor] [CONFIRMED] calendar_bloc.dart:830-837 — The format is not saved but the panel mode is: someone who prefers Week re-picks it every launch. Fix: save the format with the panel mode.
- **N16** [minor] [CONFIRMED] calendar_add_fab.dart:305 — The + reads "Nov 3" (no verb, no year), which reads like a date display. Fix: "Add · Nov 3", or keep "Add event".
- **N17** [minor] [CONFIRMED] calendar_filter_sheet.dart:371-413 — Labels assume knowledge: "Tracked", "Counted", "Not ended", "Timed", "With money", "Linked note". Fix: plainer words or a caption per row.
- **N18** [minor] [CONFIRMED] calendar_filter_sheet.dart:520-531 (record D4) — A saved filter picked inside Filters only loads the draft, and a swipe-down then drops it silently; the same pick from the bar applies at once. Fix: apply on pick in both places, or ask when a changed draft is dismissed.
- **N19** [minor] [CONFIRMED] calendar_page.dart:995-1021 — The Saved filters button is in the bar for someone with no saved filters; it opens "No filter ✓" over a dimmed row. Fix: hide it until a first preset exists (the Filters sheet keeps its row).
- **N20** [minor] [CONFIRMED] calendar_day_cell.dart:313-317 — Once another day is selected, today is only a 16 % wash, hard to spot. Fix: default the today style to `ring`.
- **N21** [minor] [CONFIRMED] calendar_bottom_panel.dart:704-711 — "Expand panel" (unfold glyph, no label) hides the whole grid; the way back is the same glyph. Fix: a label, or cover it in the guide.
- **N22** [minor] [CONFIRMED] calendar_page.dart:2085 — The month total reads "Δ +12.00" with no label or tooltip. Fix: "Net" / a tooltip such as "Money this month".
- **N23** [minor] [CONFIRMED] calendar_header_menus.dart:276 — "Export events (.ics)" is jargon. Fix: "Share calendar file" with a caption, or move it into settings.
- **N24** [minor] [CONFIRMED] calendar_page.dart:1123-1128 — A load failure shows the raw error text with no retry. Fix: a friendly message and a Retry button.
- **N25** [minor] [CONFIRMED] upcoming_agenda_view.dart:1085-1180 — Upcoming's chips never mention the switched-off Holidays or Fasting, nor the hidden categories it inherits, so "why is X missing" has no answer there. Fix: an inherited-categories chip.
- **N26** [minor] [CONFIRMED doc] docs/calendar-events-feature.md ~6874 (Tier 3 deferred) — Open bug: the day list's Upcoming year tile reads "Nov 2026 · 0" when the window ends on the 1st.
- **N27** [minor] [CONFIRMED doc] filter-sheet addendum, "Follow-ups" — Open bug: a category denylist holding only deleted-category ids shows badge 1 while hiding nothing.
- **N28** [polish] [CONFIRMED] agenda_day_list_sheet.dart:592 — The day list ✕ says "Cancel" though nothing is cancelled. Fix: `l10n.close`.
- **N29** [polish] [CONFIRMED] `removeHolidayConfirm` — "Calendar Settings" (capital S) vs the menu's "Calendar settings"; the restore lives under Calendar settings → Removed holidays.
- **N30** [polish] [PLAUSIBLE] calendar_page.dart:2157 — Paging the month keeps the old selection: the panel still says "Thursday, October 29" under a November grid, and + still adds on October 29.
- **N31** [polish] [CONFIRMED] Doc drift:
    - agenda_filters_sheet.dart:259-268 uses `CalendarDatePickerSheet.pickRange` with a floor of 2000; the skill and the Tier 1 addendum still say `showDateRangePicker`, and `CalendarBounds` is 1900.
    - §6.1 says table_calendar 3.2.0; 3.2.1 is resolved.

### 3.B — Events: the editor, its sheets, the detail sheet, templates (N32–N59)

- **N32** [major] [CONFIRMED] models/calendar_event.dart:21 + ed:747 — Every new event is filed under **Gym** (a dumbbell). This also happens when Gym is hidden. She would expect "Other", or the category she used last. Smallest fix: default to `kFallbackCategoryId` ('other'), or remember the last category picked.
- **N33** [major] [CONFIRMED] ed:1712–1880 / flow:201 — Every edit applies to **all occurrences**. Moving or retiming one session moves the whole series, and nothing asks "this day or all days?". She would expect "change just this one". Smallest fix: when a repeating event opened from a day changes its time or date, ask "This day only / All days" ("This day only" = skip the day and create a one-time copy).
- **N34** [major] [CONFIRMED] ed:1921–1945 — Delete on a repeating event erases every occurrence. The dialog says only "Delete "{title}"? This cannot be undone." and never points to Skip. She would expect to remove one day. Smallest fix: for repeating events, add "This deletes every occurrence. To remove one day, use Skip this day." (or offer the two choices).
- **N35** [major] [CONFIRMED] ed:2697–2737 — "Track presence", "Assume present / Assume absent", "Count occurrences", "Day rail" and "Separate description per day" carry **no explanation**. The v37 hint lines ("Days count as missed until you mark them present.") were dropped in the redesign; no ARB key is left, but docs v37 still describes them. A newcomer needs one line of what each does. Smallest fix: a `FormCaption` under each switch (3 ARB pairs per language), or hide the group behind "More options".
- **N36** [major] [CONFIRMED] det:585–785 — The detail sheet has **no Delete**. Deleting means Edit → scrolling past Alerts, Details and Save as template → "Delete event". She would expect a trash icon where she reads the event. Smallest fix: a "Delete event" action row at the bottom of the detail sheet, routed through the same confirmation.
- **N37** [major] [CONFIRMED] docs §3 rule table + event_repeat_sheet.dart (no caption) — "Monthly" from the 31st skips 30-day months and February silently, and "Yearly" from Feb 29 skips three years in four. For bills and rent she would expect the last day of the month. Smallest fix: a caption in the Repeat sheet when the start day is past the 28th ("Months without a 31st are skipped"); later, an "on the last day" option.
- **N38** [major] [CONFIRMED] calendar_page.dart:1223/1309 — Templates and the quick alarm are reachable only by **long press** (on a day cell or the add button), with no hint anywhere. Template management is buried in ⋮ → Calendar settings → scroll. She would expect a visible "From template" choice. Smallest fix: a "From template…" row inside the editor, or a one-time hint snackbar the first time the add button is tapped.
- **N39** [minor] [CONFIRMED] ed:1592–1603 — Picking Birthday turns on "Count from 0". If she enters the next birthday rather than the birth date, the event shows "0 years", then "1 year". She would expect the age, or nothing. Smallest fix: when Birthday is picked, add a caption "Set the start date to the birth date to show the age" under Count occurrences.
- **N40** [minor] [CONFIRMED] ed:1103 / ed:2943 — With an empty title, Save is just grey; there is no message. Smallest fix: a red caption "Add a title to save" under the title once she has tried, or a tap on the disabled Save that focuses the title.
- **N41** [minor] [CONFIRMED] ed:752 / ed:260 — New events are all-day. An appointment needs All day off, then Starts (preset 9:00), then the time pad. She would expect a time to be asked for. Smallest fix: open timed events with the start at the next full hour, or ask the owner (Q5).
- **N42** [minor] [CONFIRMED] category_picker_sheet.dart:268 — A tap on "Category" opens a sheet titled **"Type"**. Smallest fix: use `eventCategory` as the single-mode title.
- **N43** [minor] [CONFIRMED] calendar_date_picker_sheet.dart:546 — Skipped days, Add date and Dates all open a sheet titled "Pick dates", so the user cannot tell they are choosing days to **cancel**. In the Skipped days picker any day can be picked, including days the event never falls on, and they count in "{n} days skipped" (ed:1262). Smallest fix: pass a title ("Days to skip"), and mark or limit the picker to the event's own days.
- **N44** [minor] [CONFIRMED] ARB 7403 / 7419 — "Ends" means an end time in When and an end date in Repeat. Smallest fix: rename the Repeat row to "Repeat until" / "Until".
- **N45** [minor] [CONFIRMED] det:896 vs ed:2753 — The caption says "per-day descriptions", but the switch is "Separate description per day", and it sits in the editor's Occurrences group, which the caption does not name. Smallest fix: reuse the switch's words in the caption ("Turn on Separate description per day in Edit").
- **N46** [minor] [CONFIRMED] flow:279–333, flow:188–198 — On the detail sheet, the description quick edit, "Add date" and "Dates" **save at once**, with no undo. The same actions in the editor wait for Save. Smallest fix: an Undo snackbar after these writes, or at least a "Saved" confirmation.
- **N47** [minor] [CONFIRMED] calendar_date_picker_sheet.dart:245 / event_repeat_sheet.dart:120 — Sub-sheets close on a drag or a tap outside and throw away their draft silently. In the Dates sheet that can be dozens of picks. Smallest fix: give the multi-date sheet the `confirmDiscard` guard when the selection changed.
- **N48** [minor] [CONFIRMED] flow:489 — Deleting shows no Undo, although Skip and template-add both offer one. Smallest fix: "Event deleted · Undo" (a soft delete already exists in the data).
- **N49** [minor] [CONFIRMED] event_template_picker_sheet.dart:160–175 — With no templates, the long-press picker shows only "Alarm…" and "Blank event", with no word on what templates are. Smallest fix: a caption line, `noEventTemplatesDesc`.
- **N50** [minor] [CONFIRMED] ed:2739–2751 — The Day rail menu "Auto / Always / Never" uses words a newcomer cannot read. Smallest fix: a caption, or move it to the calendar settings.
- **N51** [minor] [CONFIRMED] ed:3011–3030 — Priority's effect (order within a day, which events get the day-cell bars) is unexplained, and Normal is the only default. Smallest fix: one caption line, or hide the row behind an option.
- **N52** [polish] [CONFIRMED] event_repeat_sheet.dart:483 — The weekday circles always start on Monday, while the Dates sheet follows the week-start setting (calendar_date_picker_sheet.dart:470). Smallest fix: start the circles from `appearance.weekStart`.
- **N53** [polish] [CONFIRMED] event_repeat_sheet.dart:386 — On the "Repeat every" stepper, − reads "More frequent" and + reads "Less frequent". Smallest fix: "Fewer" / "More", the Dates sheet's words.
- **N54** [polish] [PLAUSIBLE] time_pad_sheet.dart:189 — The time pad closes by itself after the second minute digit; a newcomer may think it crashed. Smallest fix: none needed beyond the guide saying so; or a 300 ms highlight before closing.
- **N55** [polish] [CONFIRMED] snackbar `eventOccurrenceSkipped` = "Occurrence skipped" uses the jargon word where the button said "Skip this day". Smallest fix: "Day skipped".
- **N56** [polish] [CONFIRMED] — There is no "Duplicate event" (no ARB key). Smallest fix: a "Duplicate" action row in the editor's Actions group.
- **N57** [polish] [CONFIRMED] lib/services/recurrence_formatter.dart:26 — Dead code: `RecurrenceFormatter.scopeAlwaysLabel` has no callers in lib/ or test/, so `recurrenceScopeAlways` ("Always") and `recurrenceScopeEveryYear` ("Every year") are unused strings.
- **N58** [polish] [CONFIRMED] docs/calendar-events-feature.md — These doc sections are out of date; **do not write the guide from them**:
   - §3.2 says the "Ends on" picker is in the editor; it is now "Ends" in the Repeat sheet.
   - §3.3 describes "From this date on / Every year / Always" chips under Occurrences; it is now the "Also before the start date" switch in Repeat.
   - The v26 addendum puts presence "at the end of the When section".
   - The v28 addendum puts the per-day switch "in Details above the description".
   - The v37 addendum describes a SegmentedButton with hint lines.
   - The code is the truth in each case.
- **N59** [polish] [PLAUSIBLE] calendar_page.dart:1419 — A template-made event bypasses the settings-default alert that the editor seeds. This is harmless while the default ships as "none", but it is inconsistent (flag for the alerts researcher).

### 3.C — The overview page (N60–N90)

- **N60** [major] [CONFIRMED] `page:1935-1952`, `page:2038-2048`, `page:3254`
   - What happens: in Month mode the title "October 2026 ▾" opens This year / Last 12 months / … Every pick, This year included, throws the page into List and saves List as the mode for the next visit.
   - Expected: a month picker that keeps Month mode.
   - Smallest fix: in Month mode the title opens the jump picker (the day list's), or a pick keeps the mode.
- **N61** [major] [CONFIRMED] `page:1569-1571` (`_selectMode`), `page:549-553`, `page:812-814`
   - What happens: Year mode opens on the *first year of the period*. After "Last 12 months" the Year chip shows last year; after "All time" it shows the first event year. This also holds on the next open when the period saved is a preset.
   - Expected: Year always shows this year.
   - Smallest fix: open Year on today's year unless the period is a year period.
- **N62** [major] [CONFIRMED] `page:1643` (`_openMonth`), no `PopScope` in `page`
   - What happens: a tile tap drills into Month; back then leaves the whole Overview. The day list sheet has "Back to months" for the same drill-down.
   - Expected: back returns to the tiles.
   - Smallest fix: remember "came from a tile" and pop Month → Year first.
- **N63** [major] [CONFIRMED] `lib/models/overview_period.dart` `resolve`
   - What happens: "All time", "Last 12 months" and "Last 90 days" end today, so next week's appointment is never listed. "This year" does run to 31 Dec.
   - Expected: All time means everything.
   - Smallest fix: rename (e.g. "Everything so far") or extend All time to the last occurrence.
- **N64** [major] [CONFIRMED] `overview_options_sheet.dart:174,239-268`
   - What happens: the page lands in Year mode, where the sheet's Order, Rows and Missed only are all greyed out with no reason given. The title "List options" also hides that Categories filters the tiles.
   - Expected: controls that work, or a reason.
   - Smallest fix: a caption "Order, Rows and Missed only apply to the List" and a neutral title ("Options").
- **N65** [major] [CONFIRMED] `page:3017`, `lib/widgets/list_scrubber.dart:121`
   - What happens: the invisible 48 dp scrubber lane lies over the rows' presence button. A drag that starts on the button scrubs, and TalkBack reaches the lane first (roadmap §2.9 "left"). The code comment "which carry no control" is stale since D31.
   - Expected: the button behaves like a button.
   - Smallest fix: narrow the lane to the gutter and thumb, or inset the presence slot in List mode.
- **N66** [minor] [CONFIRMED] `list_scrubber.dart:121` — The scrubber shows nothing at rest; its thumb appears only while scrubbing. Expected: a visible handle. Fix: show the thumb on scroll, and name the lane in the guide.
- **N67** [minor] [CONFIRMED] `agenda_day_list_rows.dart:304-309`, `agenda_year_grid.dart:269`
   - What happens: "14 entries · 2 missed" means 16 occurrences, and a tile shows 14 — missed ones are not "entries".
   - Expected: the total.
   - Fix: "14 kept · 2 missed", or "16 entries (2 missed)".
- **N68** [minor] [CONFIRMED] `page:1266-1294` — Under Missed only the totals read "Gym 3" with no "missed" word. Expected: to be told what is counted. Fix: a "{label} {count} missed" template while Missed only is on.
- **N69** [minor] [CONFIRMED] `agenda_day_list_rows.dart:540-548` (shared with the day panel)
    - What happens: a present row carries a calendar-with-✕ glyph (the action "Mark as missed"), which reads as "this was missed".
    - Expected: the glyph shows the state.
    - Fix: explain in the guide, or draw a state toggle.
- **N70** [minor] [CONFIRMED] `page:2304`, flow `23_overview_list.txt` comment
    - What happens: a presence press has no undo. Under Missed only, "Mark as present" removes the row from the list instantly.
    - Expected: a way back.
    - Fix: an undo snackbar.
- **N71** [minor] [CONFIRMED by record] roadmap §2.8 (`isMissed` has no wall clock) — events set to assume absence count every *future* unmarked day as missed (tiles, headers, "N missed" under This year). Expected: the future is not missed yet. Fix: count past days only in summaries.
- **N72** [minor] [CONFIRMED] `page:2298` — under the Hidden missed display (Settings → Appearance) the presence button appears only on Month mode's picked day; List never shows it. Fix: say so in the guide.
- **N73** [minor] [CONFIRMED] `overview_period.dart` `menuChoice` — in Year mode scrolled to 2025, or Month mode on another year, the Period menu checks "Custom range…". Expected: nothing checked, or the year. Fix: check no item there.
- **N74** [minor] [CONFIRMED] `page:2987`, `page:3152` — Under a search with no match the page says "Nothing in this period"/"Nothing this month", which reads as "no events at all". Fix: "No matches for "{query}"".
- **N75** [minor] [CONFIRMED] `event_search_query.dart:197-235`
    - What happens: "2025", "today", "tomorrow" and "29/10" are not dates; "mar" also finds "Mark".
    - Expected: these find the obvious dates.
    - Fix: guide examples; a year token would be the cheapest grammar add.
- **N76** [minor] [CONFIRMED] `page:2850-2885` — Typing a search in Year mode only thins the dots; there is no list of results. Expected: results. Fix: a typed query switches to List, or a caption.
- **N77** [minor] [CONFIRMED] `page:2466-2510`, `page:2650-2666`
    - What happens: the search button that closes the row folds away with the keyboard, and the row's ✕ only clears. So closing takes keyboard-back and then the button.
    - Fix: a close affordance in the row.
- **N78** [minor] [CONFIRMED] `overview_view_sheet.dart:305` — "Update to current list" overwrites a view with no confirm and no message. Fix: a message with undo.
- **N79** [minor] [CONFIRMED] `overview_view_sheet.dart:463-530`; flow 24
    - What happens: an empty "Saved views" sheet shows only "Save the current list", and nothing says what a view keeps. A view never keeps the search text or the mode, and applying one always lands in List.
    - Fix: a caption under the save row.
- **N80** [minor] [CONFIRMED by record] roadmap §2.9 "left" — The bookmarks and tune buttons' "selected" state never shows in the AppBar (only the tune badge does), so nothing tells the user a saved view is active. Fix: a dot or tint.
- **N81** [minor] [CONFIRMED] `page:628-632` — Export on the Overview's ⋮ exports every event, not the categories, period or search shown. Fix: label it "Export all events (.ics)", or export the shown set.
- **N82** [minor] [CONFIRMED] `page:2766`, `page:2775`
    - What happens: the List nav's today glyph means "Back to {period}", which can be a period without today (a saved 2024 view).
    - Fix: a "restore" glyph, or the tooltip as visible text.
- **N83** [minor] [CONFIRMED] no FAB or add action in `page`; `agenda_year_grid.dart:269`
    - What happens: a fresh install opens on twelve tiles of grey "0", with no hint and no way to add an event here.
    - Fix: an empty-state caption pointing to the Calendar.
- **N84** [minor] [PLAUSIBLE] `lib/utils/event_agenda.dart:505`
    - What happens: one *retroactive* series pulls the year scroll and "All time" back to 1900. All time under Oldest first can then hit the 20 000-entry cap before reaching today.
    - Fix: start All time at the first real occurrence.
- **N85** [minor] [PLAUSIBLE] `page:1681` (`_scrollMonthToTop`) — after a day is picked in Month mode the scroll jumps to the top, so on a small phone that day's rows can sit under the grid (flow 25 scrolls to reach them). Fix: scroll the picked day's rows into view.
- **N86** [polish] [CONFIRMED] `page` contains 0 holiday or fasting references — public holidays and fasting never appear on the Overview, unlike the calendar grid. Fix: say so in the guide.
- **N87** [polish] [CONFIRMED] The day list sheet (shared rows, nav and tiles) disagrees with the Overview in three ways. Its chips run List · Month · Year against the Overview's Year · Month · List (`page:2676` vs `lib/models/agenda_day_list_mode.dart:1`). Its nav title opens "Pick a date" (`monthYearPickerTitle`) where the Overview's opens the Period menu. Its ✕ tooltip is `cancel` = "Cancel" where the Overview's sheets say "Close" (`lib/widgets/agenda_day_list_sheet.dart:592`). Fix: one order, one title behaviour (see 1), `close`.
- **N88** [polish] [CONFIRMED] `page:2164-2170`, `overview_view_sheet.dart:527` — "Save the current list" is offered from Year and Month modes, where no list is shown; it saves the year in view. Fix: wording ("Save this view").
- **N89** [polish] [CONFIRMED] `lib/services/settings_service.dart` (overview settings) — Missed only silently resets on every visit, while Order, Rows and Categories persist. Fix: persist it, or note it.
- **N90** [polish] [CONFIRMED] `overview_period.dart` `menuValue` — the menu says "This year", while the nav title shows "2026". Fix: show "This year" in the title.

**First week?** No. This is an expert page: a log of what happened, attendance and saved setups. The guide can give it one paragraph: what Year, Month and List show, that a tile opens its month, that a row opens the event, and that the title is the period.

### 3.D — Calendar settings, appearance, categories, holidays, fasting, the palette (N91–N124)

- **N91** [major] [CONFIRMED] public_holidays.dart:24, :362 — a fresh install shows "Christian (Western)" whatever the language. A Romanian user gets Western Easter and Good Friday, Ascension, All Saints, 24 and 31 Dec, and no Orthodox Easter, 24 Jan, 1 Jun, 30 Nov or 1 Dec — she expects her country's holidays — pick the set from the locale on first run (ro → Romania, de → Germany) or ask once; the guide should say "pick your country".
- **N92** [major] [CONFIRMED in code; the legal fact is PLAUSIBLE] public_holidays.dart:551–590 — the Romania set has no 2 January (always a legal holiday) and no 6–7 January (legal since 2024) — she expects both days marked — add them (the January days guarded `if (year >= 2024)`) with their ARB trios; the owner should verify the dates.
- **N93** [major] [CONFIRMED] calendar_settings_page.dart:1247–1259, :1290–1385 — Reset says "reset all settings" but covers this page only, not Appearance. It silently sets the holiday set back to Christian (Western), restores every removed holiday, turns fasting off and erases the custom title, the description and up to 2×200 hand-typed dates; the dialog is not marked destructive — she expects to be told what goes, and to lose nothing she typed — list the effects in the dialog, pass `isDestructive: true`, and keep the holiday set and My practice out of the reset.
- **N94** [major] [CONFIRMED] calendar_categories.dart:30–81; category_editor_sheet.dart:540; calendar_categories_page.dart:647 — six of the nine built-ins are training-specific (Gym, Cardio, Rest, Competition, Measurement, Mobility), and built-ins can be neither renamed nor deleted, only hidden one at a time — she expects Work, Family, Health, Home… — let built-ins be renamed or pre-hide the training ones on her install; the guide should say "hide what you don't use, + to add".
- **N95** [major] [CONFIRMED] calendar_categories_page.dart:219, :596; doc §2.3 — "Hide" does not take the category's events off the calendar; it only stops offering the category. The grid filter, meanwhile, does hide events — she expects Hide = gone from the calendar — a caption on the page ("Hidden categories aren't offered for new events; their events stay on the calendar") and a snackbar on hide, or rename it Archive.
- **N96** [major] [CONFIRMED] app_en.arb:3530; calendar_appearance_page.dart:736 — the drawer promises "Week start", but "Week starts on" sits two levels down (Calendar settings → Appearance → Week) — she expects a first-week setting near the top — move it next to Holiday set, or change the description.
- **N97** [major] [CONFIRMED] backup_service.dart:226–290 — a backup restored on a new phone brings back fasting and your colours, but not the holiday set, the week start, appearance or the alert defaults, so she would be on Christian (Western) / Monday again — she expects her settings back — add those keys to the allowlist (additive, no version bump, per precedent); the feature doc's "Known gap" (:3527, "zero calendar_* entries") is stale.
- **N98** [minor] [CONFIRMED] calendar_settings_page.dart:324, :400 — you tap "Calendar settings" and land on a page titled "Calendar", whose first section is also "Calendar" — she expects the page she asked for — title it with the existing "Calendar settings" string and rename the section "Holidays".
- **N99** [minor] [CONFIRMED] calendar_settings_page.dart:402–411 — the Holiday set row never says what it changes, and its subtitle repeats the dropdown — she expects one line of explanation — a description such as "Public holidays shown on the calendar; also used by Workdays repeats".
- **N100** [minor] [CONFIRMED] calendar_settings_page.dart:497–520; public_holiday_service.dart:123 — switching the set silently throws away the old set's removed holidays — she expects them kept or a warning — confirm the switch while that list is not empty.
- **N101** [minor] [CONFIRMED] category_editor_sheet.dart:456–479; flow 18 — ✕, back or a swipe discards a typed name, icon and colour without asking, while the four neighbouring sheets save live and teach that no Save is needed — she expects her edits kept or a question — ask before discarding changes (the event editor's `_fingerprint` pattern).
- **N102** [minor] [CONFIRMED] calendar_categories_page.dart:223–256 — the delete confirm never says the category's alerts are deleted too — she expects to be told — add "Its alerts are removed." when it has alerts.
- **N103** [minor] [CONFIRMED] calendar_categories_page.dart:291, :340–360 — "Sort A–Z" overwrites the manual order at once, with no undo — she expects a way back — a snackbar with Undo.
- **N104** [minor] [CONFIRMED] calendar_categories_page.dart:592–597 — the eye icon shows the current state while its tooltip names the action, and a tap gives no feedback beyond 50 % dimming — she expects to see what happened — a snackbar with Undo.
- **N105** [minor] [CONFIRMED] app_drawer.dart:244–249; app_en.arb:3356 — the app "Appearance" row promises "Dark mode, colors and display" but offers only System / Light / Dark — she expects colours and display options — "Light, dark or follow the phone".
- **N106** [minor] [CONFIRMED] settings_keys.dart:6–7 — there is no app text size; the calendar follows the phone's font size — she expects a text-size control — say so in the guide.
- **N107** [minor] [CONFIRMED] calendar_appearance_page.dart:897–903 — a doc comment claims the settings page's reset "still covers everything"; it covers only Filter chips (calendar_settings_page.dart:1291–1297) — not user-facing — correct the comment.
- **N108** [minor] [CONFIRMED] docs/calendar-events-feature.md §4.5 and §2.3 — §4.5 still describes debounced inline text fields, which Tier 3 replaced with a dialog and a sheet that save on confirm; §2.3 says grid-filter hiding resets on every load, but filters have been saved since v35 — docs only — update both.
- **N109** [minor] [CONFIRMED] app_en.arb:1373–1377 — "Multi-day fasts" also covers single strict days and Cheesefare, and turning it off makes the weekly fast apply all year; the UI says neither — she expects the label to say what it does — add "Off: only your weekly fast days, all year" to the description.
- **N110** [minor] [CONFIRMED] fasting_schedule_sheet.dart:247–265 — the months' "None" unmarks every fast while the tradition switch stays on (the summary then reads "No months kept") — she expects fasting to stay visible — disable "None" for months, or explain it in the caption.
- **N111** [minor] [CONFIRMED] app_en.arb:1491 — "Days off" reads as days off work or vacation; it means dates you do not fast, and the summary calls them "exceptions", a third word — she expects the words to match — "Dates I don't fast".
- **N112** [minor] [PLAUSIBLE] settings_keys.dart:508 — Filter chips is off by default, so after filtering the grid there may be no trace on screen and events seem to vanish (depends on the header filter button's active state, the grid researcher's area) — she expects to see that a filter is on — chips on by default, or a line in the guide.
- **N113** [minor] [CONFIRMED] calendar_appearance_page.dart:225, :796 — two rows in different sections both change today's look ("Today highlight", "Highlight color") — she expects one place — put them together, or rename them "Today's style" / "Today and selected-day color".
- **N114** [polish] [CONFIRMED] category_editor_sheet.dart:573–580 — the Icon row always reads "Choose icon", even after a pick — she expects it to show her choice — "Change icon", or the icon's name.
- **N115** [polish] [CONFIRMED] calendar_icons.dart:10–33 — the icon picker opens on the gym groups (Strength, Cardio, Sports, Recovery…) — she expects everyday icons first — lead with People / Home / Work / Health.
- **N116** [polish] [CONFIRMED] app_en.arb:10 — the drawer's calendar row reads "Plan gym sessions and events" — she does not train — drop "gym".
- **N117** [polish] [CONFIRMED] public_holidays.dart:11–13; app_ro.arb — the dropdown is alphabetical only in English; in Romanian "România" comes before "Regatul Unit" — she expects alphabetical order — sort by the localized name, with None last.
- **N118** [polish] [CONFIRMED] calendar_settings_page.dart:537–545, :591–617, :625–641 — three cards hold a single row each, two of them titled the same as the card — fewer, fuller cards read faster — merge them.
- **N119** [polish] [CONFIRMED] calendar_settings_page.dart:678; fasting_style_sheet.dart:188 — the row says "Appearance" but its sheet is titled "Orthodox", and the summary "Subtle tint · After holidays" ("After events" is stored as `beforeHolidays`) reads oddly in a fasting context — she expects the row and sheet to match — label the row "Look on the calendar".
- **N120** [polish] [CONFIRMED] app_en.arb:3627, :3656, :3719 — the Day rail, the "Fasting half of the rail" and "Missed days" rows assume presence tracking ("tracked commitment", "Rail events leave the bottom markers") — she has never tracked presence — the guide calls the Appearance page optional.
- **N121** [polish] [CONFIRMED] app_en.arb:6488 — the notice row reads "A quiet notice 120 minutes before an alarm" — she expects "2 hours" — say "2 hours" (the alerts researcher's call).
- **N122** [polish] [CONFIRMED] app_en.arb:427 — the remove-holiday dialog points to "Calendar Settings", but the page is titled "Calendar" and the row is "Removed holidays" — she expects the names to match — name the page and row the dialog points to.
- **N123** [polish] [CONFIRMED] doc :4324–4335 — "+" in any swatch strip adds the colour to the shared palette for good, so experimenting quietly fills "Your colors" (24 at most) — she expects a one-off pick — say so where the strip is, or make the add explicit.
- **N124** [polish] [PLAUSIBLE] fasting_calendar.dart (doc §4.5) — Muslim and Jewish dates are computed by arithmetic (±1 day for Ramadan) and the UI never says so — she expects exact dates — one caption line under those traditions.

### 3.E — Alerts: the sheet, the hub, the ring, the quick alarm, permissions (N125–N157)

- **N125** [blocker] [CONFIRMED] `alert_constants.dart:33-37`, `main.dart:325/427/677`, `docs/category-alerts-and-digests-roadmap.md` D21 — **What happens:** a repeating **reminder** is armed for 2 occurrences only. It is re-armed only when ANTA launches or resumes. Its "Done" runs with no database (feature doc 2048-2051), so a daily reminder stops after day 2 unless she opens the app. Alarms re-arm when they ring. **She expects:** a daily reminder every day. **Fix:** a daily background reconcile, or a larger `perAlert` for reminders within the 48 cap. Until then, the guide says "open ANTA every day or two".
- **N126** [major] [CONFIRMED] `13_alert_sheet.txt:7`, `alert_editor_sheet.dart:210` — **What happens:** a new event is All day, so When offers only "On the day / The day before / A week before" at 09:00. A reminder for an 08:30 appointment fires after it. **She expects:** "30 min before". **Fix:** a caption on the all-day When row ("This event has no time — turn off All day to be reminded minutes before"); the guide covers it.
- **N127** [major] [CONFIRMED] `alarm_page.dart:207-219` — **What happens:** "Open event" on a remove-after alarm deletes the event, then opens an empty day. The only warning sits beside Stop. **She expects:** Open to show the event. **Fix:** Open keeps the event (Keep, then stop), or the caption names Open too.
- **N128** [major] [CONFIRMED] `alert_removal_notice.dart:47`, `calendar_page.dart:548-560`, ARB 6913 — **What happens:** the hint promises "Undo is offered right after". In fact Undo shows only on the calendar page within 5 min. A Stop from the lock screen or a heads-up in another app never shows Undo. **She expects:** to get it back. **Fix:** an "Event removed · Undo" notification, or keep the notice until the calendar opens; reword the hint.
- **N129** [major] [CONFIRMED] `quick_alarm_sheet.dart:84,90` — **What happens:** the quick alarm opens on Alarm with "Remove after it rings" on, so every quick alarm deletes its event on Stop. **She expects:** an alarm for an appointment that stays. **Fix:** default off, or leave it on and explain it in the guide.
- **N130** [major] [CONFIRMED] `lib/bloc/calendar/alert_skip_action.dart:5-9`, `settings_keys.dart:638` — **What happens:** a quiet "Alarm at {time}" notice comes 120 min before every alarm, on by default. Its "Skip" cancels that day of a repeating event in the calendar, or switches a one-time event's alert off. **She expects:** "skip this alarm only". **Fix:** relabel ("Skip this time", or "Cancel alarm"), or turn the notice off for her.
- **N131** [major] [CONFIRMED] `main.dart:715-736`, `lib/pages/onboarding_page.dart` (no alert or alarm strings) — **What happens:** "ANTA needs your permission — Without these, alarms and reminders stay silent." appears right after onboarding, before she has set anything. **She expects:** to be asked when she first sets a reminder. **Fix:** defer the launch check until the first alert exists; the after-save prompt already covers that moment.
- **N132** [major] [CONFIRMED] `alert_scheduler.dart:563-577,659-668`, ARB 7138 — **What happens:** the hub lists only the next 30 days. A reminder 6 weeks out leaves "No upcoming alerts" on screen. **She expects:** to see everything she set. **Fix:** list over a longer window (the countdown already looks 366 days ahead, feature doc 2082), or caption it "Next 30 days".
- **N133** [major] [CONFIRMED] `lib/services/session_chip.dart:119-150`, `lib/controllers/alert_ring_controller.dart:207-208` — **What happens:** every Stop posts an ongoing "Session in progress" notification. It counts up until "Done" when the event has no end, and is posted even for an event the Stop just removed. **She expects:** a stopped alarm leaves nothing behind. **Fix:** a setting (off for her), or post it only when the event has an end or a linked note.
- **N134** [major] [CONFIRMED] ARB 7094, `16_alert_defaults.txt`, feature doc 2035 — **What happens:** alerts are opt-in. New events get "No alert", and nothing on an event says it has no reminder. **She expects:** the calendar to remind her. **Fix:** set her two defaults before the handover, or show "No alert" as a value in the editor's Alerts group.
- **N135** [major] [PLAUSIBLE] `alerts_page.dart:752` — **What happens:** battery restriction has no banner and is offered only as "Recommended". On OEM skins (Samsung, Xiaomi) reminders can be delayed or dropped. **Fix:** a hub banner for battery, plus a guide line.
- **N136** [minor] [CONFIRMED] ARB 6909 vs 6913, `alert_gateway.dart:39-40` — **What happens:** the label says "after it rings", but only Stop removes: an unanswered ring and Snooze remove nothing. **Fix:** "Delete the event when I stop the alarm".
- **N137** [minor] [CONFIRMED] `event_editor_sheet.dart:2829-2838` — **What happens:** the editor's remove-after switch has no hint (the sheet's has one), and it appears or disappears as an Alarm is added or removed. **Fix:** give it the same subtitle.
- **N138** [minor] [CONFIRMED] `settings_service.dart:1812,1831`, `alert_editor_sheet.dart:173-175`, feature doc 1693-1696 — **What happens:** an all-day alert that "never chose a time" follows the All-day default's time. Setting a default of 18:00 later moves every older "On the day, 09:00" alert to 18:00. **Fix:** store the minute on Done.
- **N139** [minor] [CONFIRMED] `alerts_page.dart:220-262` — **What happens:** an inherited row's switch is the event's "Category alerts" flag, so one switch flips every inherited row of that event. Rows show the tier only as a glyph. **Fix:** caption the switch, and show the tier word.
- **N140** [minor] [CONFIRMED] `alerts_page.dart:300-307` — **What happens:** a hub row tap opens the event, not the alert. Changing the time takes detail → Edit → Alerts → the row → Done → Save. **Fix:** a tap that opens the alert sheet.
- **N141** [minor] [CONFIRMED] `alerts_page.dart:554-558` — **What happens:** "Cancel alarm" (which deletes the event) is a long press, with no visible affordance. **Fix:** a trailing menu.
- **N142** [minor] [CONFIRMED] `alerts_page.dart:462,632-690`, ARB 7142 — **What happens:** the hub opens with "Digests · Add digest". On an empty hub that is the only button, while the text says "Add a reminder or an alarm to an event" with no way there. **Fix:** move Digests below, and add a "Go to calendar" action.
- **N143** [minor] [CONFIRMED] ARB 6933/6937 — **What happens:** the hints use jargon ("the shade", "Focus", "alarm stream"). "until you stop or snooze it" is false, since the ring ends after "Silence after" (`settings_keys.dart:646`). **Fix:** plain words, e.g. "Rings like an alarm clock until you stop it (up to 10 min)".
- **N144** [minor] [CONFIRMED] ARB 7242 — **What happens:** the permission "Alarms & reminders" (exact timing) reads as the app's two tiers. **Fix:** "Exact timing (Alarms & reminders)".
- **N145** [minor] [CONFIRMED] ARB 6610 vs the presence "Missed" — **What happens:** "Missed" means two things. **Fix:** "Not answered" for alerts.
- **N146** [minor] [CONFIRMED] ARB 6893/6638/6354 — **What happens:** Done / Stop / "dismiss" are used for one act. **Fix:** align the words.
- **N147** [minor] [CONFIRMED] `alert_editor_sheet.dart:622-625` — **What happens:** "Alarm sound" is dimmed on a Reminder with no reason given. **Fix:** a caption, "Reminders use the phone's notification sound".
- **N148** [minor] [CONFIRMED] `16_alert_defaults.txt` (comments) — **What happens:** in the settings defaults, "Remove alert" means "no default", and Done on an untouched sheet saves "Reminder · 10 min before". **Fix:** label it "No default alert", and make an untouched Done save nothing.
- **N149** [minor] [CONFIRMED] `calendar_page.dart:1223,1309` — **What happens:** the quick alarm is reachable only by a long press, the tile or the shortcut. **Fix:** a visible entry (for example in ⋮), and a guide line.
- **N150** [minor] [CONFIRMED] category-alerts roadmap D7 — **What happens:** a new event in a category that has alerts also gets the settings default as its own alert, so two reminders can fire when their offsets differ. Category alerts sit 3 levels deep in settings. **Fix:** guide; optionally suppress the default when inherited alerts exist.
- **N151** [minor] [PLAUSIBLE] Android 14+ policy — **What happens:** a sideloaded or Play install may lack full-screen intent, so alarms appear as a banner on a locked phone. It is warned in the Type caption and a hub banner. **Fix:** a guide line pointing to Permissions.
- **N152** [minor] [CONFIRMED] ARB 6618 — **What happens:** the force-stop warning appears only under "Test alarm in 10 s". **Fix:** say it in the guide and in the Permissions page.
- **N153** [polish] [CONFIRMED] ARB 6488 — **What happens:** the caption reads "A quiet notice 120 minutes before…" and counts up to 1440 minutes. **Fix:** show hours.
- **N154** [polish] [CONFIRMED] `lib/widgets/digest_editor_sheet.dart:358-360` — **What happens:** "Every" reuses "Day/Week/Month", so it reads "Every Day". **Fix:** dedicated lower-case keys.
- **N155** [polish] [CONFIRMED] `event_editor_sheet.dart:2820, 2795-2799` — **What happens:** "Add alert" vanishes at 5 with no word, and the row ✕ removes an alert with no Undo (only discarding the editor brings it back).
- **N156** [polish] [CONFIRMED] `alert_editor_sheet.dart:476` vs `quick_alarm_sheet.dart:224` — **What happens:** the Alert sheet confirms with "Done" but stores nothing until the editor's "Save". The quick alarm says "Save".
- **N157** [polish] [CONFIRMED] `alerts_page.dart:381-383` vs `references/subsystems.md` ("The hub's ground stays `surface`") — **What happens:** the doc and the code disagree (it is not user-facing).

## 4. Proposals for the owner, ranked

The lead's ranking of what would help a first-time calendar user most,
per unit of work. S = under an hour for an implementer, M = a slice with
its own review, L = its own record. Each names its ledger ids. The
researchers' letter severities are overridden here where a newcomer's
first week weighs differently from a correctness reviewer's.

### 4.0 — Before the handover, on her phone (no code)

- **P0.1** Calendar settings → Holiday set: her country (Romania shows
  Orthodox Easter and the national days; the default is a generic Western
  Christian set) — N7, N91.
- **P0.2** Calendar settings → Alerts → Timed events / All-day events:
  set a default (for example Reminder · 30 min before, and The day before
  · 09:00), so every event she adds reminds her without her knowing the
  Alerts group exists — N134.
- **P0.3** Calendar settings → Categories: hide Gym, Cardio, Rest,
  Competition, Measurement and Mobility; create hers (Work, Family, Health,
  Home, Birthdays stays) — N94. Until P1 lands, every new event is still
  filed under Gym even when Gym is hidden (N32).
- **P0.4** Calendar settings → Alerts → Upcoming alarm notice: 0 (its
  "Skip" cancels a repeating event's day, N130), and Filter chips: on,
  so a filter that hides events is visible above the grid — N4, N112.
- **P0.5** Language, if the phone's is not hers; the week start is
  Monday already.

### 4.1 — Small changes with the biggest first-week effect (S each)

- **P1** New events default to "Other" (or the last category used), never
  Gym — N32. One constant plus the editor's seed.
- **P2** An Upcoming card tap opens the event (as the day panel's does)
  instead of only moving the grid selection — N1. The guide currently
  says the pencil edits it.
- **P3** Delete on the detail sheet, "Event deleted · Undo" after it (the
  data is already soft-deleted), and the delete dialog of a repeating
  event saying it removes every day and pointing at "Skip this day" —
  N34, N36, N48.
- **P4** `availableGestures: horizontalSwipe` on the grid: the vertical
  swipe that shrinks the month to two weeks or a week is the trap the
  guide's D11 line exists for — N3. Retire that line with it.
- **P5** A visible way to templates and the quick alarm: the + button
  opens a chooser (Event · Alarm… · templates) or "Alarm…" joins the ⋮;
  today both are an unmarked long press — N2, N38, N149.
- **P6** Defer the launch permission dialog ("ANTA needs your permission")
  until the first alert exists; the after-save prompt already covers that
  moment — N131.
- **P7** A reminder minutes before an all-day event is impossible and
  nothing says so: a caption on the all-day When row, and the editor's
  Alerts group showing "No alert" as a value so she sees an event has none
  — N126, N134. Retire the guide's all-day caveat with it.
- **P8** One caption under each Occurrences switch (Track presence, Count
  occurrences, Day rail, Separate description per day) and under Priority;
  the v37 hint lines were dropped in the redesign — N35, N50, N51.
- **P9** "Open event" on the ring screen of a remove-after alarm keeps
  the event (Keep, then stop) instead of deleting it; the quick alarm's
  "Remove after it rings" off by default, or explained — N127, N129.
- **P10** A seeded holiday set from the locale on first run (ro → Romania,
  de → Germany), and Romania's 2 January and 6–7 January (since 2024;
  the owner verifies the law) — N7, N91, N92.
- **P11** Monthly repeats from the 29th–31st: a caption in the Repeat
  sheet ("Months without a 31st are skipped"); later a last-day option —
  N37.
- **P12** The empty day panel says "Tap + to add an event"; an empty
  title says "Add a title to save" instead of a grey Save — N10, N40.
- **P13** Wording: the category picker titled "Category" not "Type"
  (N42); "Repeat until" for the Repeat sheet's "Ends" (N44); the drawer's
  "Plan gym sessions and events" without "gym" (N116); the settings page
  titled "Calendar settings" with its first section "Holidays" (N98);
  "Exact timing (Alarms & reminders)" for the permission (N144).
- **P14** Reset to defaults on Calendar settings: list what it wipes, mark
  it destructive, keep the holiday set and My practice out of it — N93.
- **P15** The backup carries the holiday set, week start, appearance and
  alert defaults — N97 (additive allowlist, no version bump).

### 4.2 — Medium

- **P16** The alert horizon: a repeating reminder is armed for two fires
  and re-planned only when the app opens, so a daily reminder stops after
  day two unless ANTA is opened — N125 (the roadmap's D21 left the
  background job out "because the owner opens the app daily"). Options:
  a larger `perAlert` for reminders inside the 48 cap (S, buys days), or
  the `workmanager` daily `reconcileAll` D21 priced (L, its own record).
  The guide's D9 row goes with it.
- **P17** Edit "this day only" on a repeating event (move or retime one
  session: skip the day plus a one-time copy) — N33.
- **P18** The Alerts hub: list more than 30 days or caption "Next 30 days";
  no "Session in progress" chip after a Stop unless the event has an end
  or a note (or a setting); a row tap that opens the alert, not the event
  — N132, N133, N140.
- **P19** The two Filters sheets: name their scopes ("Calendar filters" /
  "Upcoming filters"), Holidays on by default in Upcoming, and a grid tap
  in Upcoming mode that shows the day — N5, N6.
- **P20** Text scale: the panel's Day / Timeline / Upcoming labels vanish
  at 1.2 (en) and 1.1 (de); the + loses its label at 1.5 — N8.
- **P21** The overview: Year mode opens on this year; back from a tapped
  tile returns to the tiles; "All time" and the rolling periods include
  what is coming, or say they end today; the options sheet says Order, Rows
  and Missed only apply to the List — N61–N64.
- **P22** Presence from a row: an Undo snackbar, and a glyph that shows
  the state rather than the action — N12, N69, N70.
- **P23** The Weekend bar and row: not an entry, not one of the three bar
  slots — N9.
- **P24** Built-in categories renameable, or the training ones shipped
  hidden for a non-training install — N94; "Hide" captioned as archive
  (events stay on the calendar) — N95.

### 4.3 — Decide, do not build yet

- **P25** New events all-day or timed by default (today all-day; a timed
  event is three taps away and a reminder needs it) — N41, N126, §5 Q4.
- **P26** Whether presence tracking, counts, the day rail and per-day
  descriptions stay visible for her or go behind "More options" — N35,
  §5 Q3.
- **P27** Whether the overview stays in the drawer and the title menu for
  her — §5 Q6.

### 4.4 — The verdict

The calendar is well built underneath — the 2026-10-26 review closed 171
ids on it, every surface has its suite and its device flow, and the
researchers found no crash and few bugs (N58 doc drift, N57 dead code,
N107 a stale comment, N108 two stale doc sections). What a first-time user meets is a
different matter: the strongest features hide behind gestures nothing
announces (two long presses, a vertical swipe, a ▾ beside the title), the
defaults are a trainer's (Gym, six training categories, "Plan gym
sessions", presence vocabulary on the appearance page), one word means two
things in a dozen places (Alerts / Reminder / Alarm, Done / Stop, entries /
occurrences, Ends × 2, Filters × 2, Type / Category, Hide × 3, Appearance
× 3), destructive actions have no undo where creative ones do (delete,
presence, hide, Sort A–Z, Update to current list), and two functional gaps
would surprise anyone (the alert horizon P16, no edit-this-day-only P17).
The guide covers the first three for now; §4.1 is the short list that
would let the guide shrink.

## 5. Questions for the owner

1. Her phone (brand, Android version, sideloaded or Play) — it decides the
   full-screen-alarm and battery advice, and which banners she will see.
2. Her language, her country's holiday set, and whether she keeps a
   fasting practice (the guide says nothing about fasting; the feature is
   off by default).
3. Should presence tracking, counts, the day rail and per-day descriptions
   stay visible, or go behind an advanced switch (P26)?
4. New events: all-day or timed by default (P25)? Keep the time pad
   closing itself after the last digit?
5. Set her alert defaults before the handover (P0.2), or keep alerts
   opt-in? Keep the 120-minute notice and the session chip for her?
6. Should the overview stay reachable from the drawer and the title menu
   for her (P27)?
7. Which categories should she start with, and should the training
   built-ins be hidden on her install or made renameable (P0.3, P24)?
8. P16: raise `perAlert` for reminders now, or price D21's background job?

## 5b. The owner's answers (2026-10-29, after the first build)

- Q1: she uses Romanian and English; the holiday set is Romania; the
  phone is a Samsung Galaxy A-series (One UI — its battery optimisation is
  the aggressive kind, so the guide's permissions row should name
  "Unrestricted battery" for Samsung).
- Q2: alerts stay opt-in (P0.2 is the owner's choice on her phone, not a
  default).
- Q4 (hide presence tracking, counts, the day rail, per-day descriptions?):
  no — document them well instead. The guide gains rows for each.
- Q5: yes — raise `kAlertHorizon.perAlert` now (P16's short form); D21's
  background job stays out. Built the same day; see §7.
- And a change of direction: the page should be **hands-on** — "real
  components but no real functionality": each topic carries a live demo
  made of the app's own widgets that she can tap (a month that selects a
  day, the + button that opens the real editor, the alert sheet, a presence
  button), driven by throwaway demo state so nothing reaches her data.
  That is a rework on `ui-revamp`: §7 holds its record.

## 7. The hands-on rework (2026-10-29 →)

### 7.0 Built first: P16's short form (Q5)

`kAlertHorizon.perAlert` 2 → 10 (`lib/constants/alert_constants.dart`,
with the why on the field), `days` and `total` unchanged. The planner
(`lib/utils/alert_planner.dart`) takes up to `perAlert` fires per enabled
alert, sorts every candidate soonest-first and cuts at `total`, so the cap
already shares the budget by time; ten keeps a daily reminder going for
someone who opens the app every week or so (with n daily alerts the
unattended span is about 48 ÷ n days). The hub lists up to ten rows per
repeating alert. Four `alert_scheduler_test` cases that tell a two-fire
story (the sliding window after Stop, the skip/unskip move, the history
listing, the re-plan after a native snooze) pin `AlertHorizon(perAlert: 2,
days: 30, total: 48)` explicitly; the hub's "lists what is armed, soonest
first" case pins the shipped 10. The alerts fixtures arm 4 and 2 (every
alarmed event one-time, the birthday once inside 30 days), so no flow
changed. Gate: analyze clean, suite +10800 ~10 −1 (the Windows-only case),
`qa pass alerts` 5/5 and `qa pass alerts_pair` 1/1 on `emulator-5556`,
`qa errors` clean, the device left with no alarm armed. The guide's D9 row is softened
accordingly in the next content change ("about ten of each; open the app
every week or so").

### 7.1 The rework — status: PLAN (awaiting the owner's letters on D13–D18)

**Why.** The owner (2026-10-29): "make the documentation hands on with
components (real components but no real functionality, like clicking the
button in the docu page does something but no impact for the real app)".
A page of paragraphs teaches by reading; she learns by tapping.

**Facts from the tree** (one Opus researcher, read-only; the report's
`file:line` are the facts, repeated here where a slice needs them):

- A second real `CalendarBloc` cannot run over fake data: its handlers are
  library-private, `on<E>` cannot be registered twice, `emit` outside a
  handler is test-only, `_resolveAndReload` (`calendar_bloc.dart:748-789`)
  calls `getInstance()` on all nine services, and the presence, skip and
  description handlers write to the real singletons (`:1074/:1145/:1180/
  :1207/:1235`); every `forTesting` factory installs itself as the process
  singleton. A sibling `Bloc<CalendarPageEvent, CalendarPageState>
  implements CalendarBloc` is possible (four members to implement, sealed
  events so one `switch` covers them) but costs L and still cannot show a
  presence, skip or description change: those caches are only ever
  replaced whole (`event_presence.dart:57`), so a demo mark would wipe the
  owner's in-memory copy.
- Who reads the bloc: in `lib/widgets` only `calendar_bottom_panel.dart:436/
  474` and `category_editor_sheet.dart:411`; `event_sheets_flow.dart` reads
  it from the caller's context; everything in `calendar_page.dart` is
  private (the month grid is `_CalendarTable`, `:1679`). A
  `BlocProvider<CalendarBloc>` around a subtree shadows the real bloc for
  that subtree but never for a bottom sheet, which is built under the
  Navigator — so a demo flag must be passed through each `show(…)`.
- Write paths inside the components themselves: `CalendarBottomPanel`
  saves the panel mode, the agenda filters and the day-list mode
  (`:239/:288/:332/:347`), no flag; the editor writes through three sheets
  it opens — Save as template (`event_template_editor_sheet.dart:413-419`),
  the category picker's always-offered Create row
  (`category_picker_sheet.dart:199/:350` → `category_editor_sheet.dart:
  369-411`), Icon & colour's palette editing (`color_swatch_picker.dart:
  178-227`, the picker's mode `color_picker_sheet.dart:275`); the filter
  sheet writes saved filters (`calendar_filter_sheet.dart:223` and the
  preset sheet's create / rename / overwrite / delete / reorder); its own
  result is a draft. Safe as they are (callbacks or returned drafts only):
  `CalendarAddFab`, `CalendarViewMenu`, `CalendarOverflowMenu`,
  `DaySummaryPanel`, `AgendaDayListRowBuilder`, the day cells and
  `DayBarsResolver({providers})`, `EventDetailSheet`, `AlertEditorSheet`,
  `AlertOffsetSheet`, `QuickAlarmSheet` (the page saves,
  `calendar_page.dart:1443-1475`), `TimePadSheet`, the date picker, the
  repeat sheet. Pure: `HolidaySeeds.forYear`, `EventSearchQuery.parse`,
  `EventQueryMatcher` (reads per-day descriptions, which demo ids lack).
  `CalendarAppearancePreview` builds seven real cells from hand-made bar,
  rail and tint outputs and reads nothing global — the precedent for a
  demo grid. `AlarmPage` has no preview: its `controller` is
  `@visibleForTesting` (`alarm_page.dart:82`); tests fake it
  (`test/widgets/support/alarm_page_fakes.dart`). Nothing in `lib/` runs
  real widgets over an in-memory store; QA mode is a compile-time build.

**Decisions proposed (the recommended letter first; the owner's answer is
written beside each when it comes):**

- **D13 — Where the practice calendar lives.** A: an embedded card at the
  top of the guide — a demo bar (the title menu, the funnel, the ⋮), a
  demo month grid, the panel mode bar, a three-row panel, the + button —
  so the explanation and the thing it explains sit on one scroll. B: its
  own full-screen route opened from the guide's first card (the real
  proportions, one more screen). Recommended A.
- **D14 — What the demos are made of.** A: the real widgets on throwaway
  demo state, plus one `sandbox` parameter threaded through
  `EventEditorSheet.show`, `CategoryPickerSheet`, `EventLookSheet` /
  `ColorSwatchPicker` and `CalendarFilterSheet.show` that hides Save as
  template, Create category, palette editing and the saved-filter rows;
  the detail, alert, quick-alarm, repeat, dates and time sheets open as
  they are and their results feed the demo. B: a sibling bloc hosting the
  real panel and sheets flow (L; cannot show presence / skip / description
  changes). Recommended A.
- **D15 — Real navigation from the guide.** A: two action rows open the
  real Permissions page and the real Calendar settings page (they are where
  she must go; navigation is not data). B: none; the guide stays sealed.
  Recommended A.
- **D16 — The alarm screen.** A: a "Show me the alarm screen" row pushes
  the real `AlarmPage` with a demo payload and a public preview controller
  (Stop / Snooze / Keep only close it; no OS alarm, no lock-screen flags —
  those are the ring controller's). B: describe it only. Recommended A.
- **D17 — Demo data.** A: six sample events with `guide-demo-` ids, plain
  names (Dentist, Yoga, Rent, Mum's birthday, Book club, Flight), in her
  real categories and with her real holidays (reads only), reset every
  time the page opens; nothing persists. B: persist the demo between
  visits. Recommended A.
- **D18 — Scope.** A: every demo below, over four slices. B: the practice
  calendar card only (slices 0–1), then decide. Recommended A.

**The demos** (each a "Try it" card: the real widget on demo state over a
one-line live caption that says what just happened; costs S under an hour,
M a slice's share):

| # | Section · topic | The demo | Cost |
| --- | --- | --- | --- |
| 1 | The calendar screen · the practice calendar | demo bar (`CalendarViewMenu` → the grid's format or "would open the overview"; the funnel → the filter sheet in sandbox, its draft hides demo categories; `CalendarOverflowMenu` → "would open Alerts / share / settings", the guide row → "you are here"), a demo month grid (`TableCalendar` + `CalendarDayCell` + `DayBarsResolver`, horizontal swipe only), the panel mode bar (made public), `DaySummaryPanel` on the picked demo day (three rows, no inner scroll; Timeline → `DayTimelineView` if self-contained, Upcoming → demo rows through `AgendaDayListRowBuilder`), `CalendarAddFab` → the sandbox editor → the saved event joins the demo list; long press → the template picker (reads her templates) → a demo event | L (two slices) |
| 2 | Events · open, change, skip | a demo panel row → `EventDetailSheet` with demo callbacks (Edit → the sandbox editor; Skip → the day leaves the demo grid; no presence chips: the demo event is untracked) | S |
| 3 | Events · repeat | a `FormPickerRow` → `EventRepeatSheet` → the rule in words (`RecurrenceFormatter`) and the demo grid showing the occurrences | S |
| 4 | Events · attendance | a tracked demo row with the real presence button; a tap flips it and the caption counts the streak | S |
| 5 | Events · counting | `FormSwitchRow` + the two chips → "Day 1 · Day 2 · Day 3" / "0 years · 1 year" | S |
| 6 | Alerts · add an alert | a row → `AlertEditorSheet` → the alert row as the editor draws it, `EventAlert.describe` | S |
| 7 | Alerts · the alarm screen | D16's preview | M |
| 8 | Alerts · quick alarm | `QuickAlarmSheet` → "Alarm at 18:15, demo only" | S |
| 9 | Alerts · permissions | D15's action row | S |
| 10 | Finding · search | a search row over the demo events through `EventQueryMatcher`, the examples as chips | S |
| 11 | Make it yours · week start | a `SegmentedButton` Mon / Sat / Sun turning `CalendarAppearancePreview`'s header | S |
| 12 | Make it yours · holidays | a dropdown of the holiday sets → this year's dates from `HolidaySeeds.forYear` | S |
| 13 | Make it yours · categories | a demo category row with the eye; a tap hides it in the demo picker | S |
| 14 | Make it yours · settings | D15's action row | S |

**Must not change:** no demo writes — no `getInstance()` write, no
`SettingsService` setter, no preset, template, category or palette write
from any demo, proven by a test per demo that pumps it, drives every
affordance and asserts the fakes saw nothing; the real pages' behaviour
with `sandbox: false` is unchanged, byte for byte in their suites; the
`gym_notes` directory; the ARB placeholders rule (D5); the ⋮ order.

**Slices.** 0 — the sandbox seams: the `sandbox` parameter on the four
sheets, `PanelModeBar` public, the alarm preview controller, each with a
test that the flag hides the write paths; 1 — the practice calendar card
(demo state, the bar, the grid, the panel, the + button, the sheets wired)
in two halves (1a grid + panel + FAB + editor + templates; 1b the bar's
menus, the funnel, the mode bar's Timeline and Upcoming); 2 — demos 2–6,
8, 10; 3 — demos 7, 9, 11–14, the content additions of
`guide-content-2.md` (the six advanced-switch rows, the Samsung line, the
softened horizon row); 4 — the flow (`26_guide` walks the practice
calendar: pick a day, add an event, open it, skip, a filter, back),
`design-reviewer`, docs, the status line. One `implementer` and one
`reviewer` per slice; the `designer` draws the "Try it" card once, before
slice 1 (the stage, the caption role, the "Try it" label, the practice
calendar's banner "Nothing here is saved").

**Definition of done, beyond §4 of `ui-revamp`:** every demo tappable
one-handed at 360 wide; the practice calendar's grid swipes only
sideways; nothing in the page scrolls inside the page (the panel shows
three rows and "+N"); a demo reset on every open; de at 2.0 with no
clipped caption; TalkBack announces each stage's caption change (a live
region); `qa pass calendar` green with the extended `26_guide`.

## 6. Deferred

- **The settings kit, not this page** (the `design-reviewer`'s findings of
  2026-10-29, measured on this page but shared by every kit page; they are
  the open app-wide kit decision of `docs/ui-language-adoption-roadmap.md`
  and are not fixed here): the search field's hint at 0.6
  `onSurfaceVariant` on `surfaceContainerLow` is 3.05:1 in light (AA needs
  4.5) and its box is 38 dp tall (`settings_search_field.dart:54-75`); at
  text scale 2.0 the field's fixed height of 40 puts the hint 10 px above
  its top border (`:55`); its clear ✕ is 32 dp and unlabelled (`:79-93`);
  the kit's section titles carry no `headingLevel`, so TalkBack cannot jump
  section to section on a 31-row page (`settings_section_list.dart:296-310`);
  the "No matches" text at 0.5 `onSurface` is 3.26:1 (`:176-195`); the kit's
  id node wraps the row's merged node, so a flow that reads text by id reads
  nothing (`:404`); the `meetsGuideline` matchers stop at the search field,
  so they never reached the rows (the token arithmetic clears them:
  paragraph 8.13 / 9.56, title 14.85 / 12.57, intro 8.88 / 10.91, chip
  glyph 5.00 / 5.47, light / dark).
- **The menu, not this row:** at `de` 2.0 a two-line row ("So funktioniert
  / der Kalender") sits with no vertical padding against the next two-line
  row ("Kalendereinstell/ungen", which breaks mid-word); menu-wide, and
  older than this change (`calendar_header_menus.dart:288-296`,
  `FormMenuItemRow`).
- **This page, cosmetic (severity 1):** the 24 px glyph, which does not
  scale, sits 8 px above the first title line's centre at 2.0
  (`CrossAxisAlignment.start`); the glyphs mix filled and outlined because
  D7 takes the app's own icons; the intro fills about half of a 360 × 780
  screen at 2.0; the page's five literals (14, 1.4, 16, 12, 4) are the
  kit's own numbers where `rules/ui.md` would want names — the kit
  decision owns that too. The suite runs no `meetsGuideline` matcher (it
  would fail on the search field today) and asserts neither the paragraph
  style nor the glyph's exclusion.
- The two guide lines that describe a trap (D9, D11) are retired with
  P16, P4 and P7.
- The researchers' question lists beyond §5 are in their reports (the
  session's scratchpad); §5 keeps the ones that change what gets built.
