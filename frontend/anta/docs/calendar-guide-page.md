# The calendar guide page, and the newcomer review (2026-10-29)

**Status: the page and the horizon COMMITTED `00669602` (2026-10-29); the
hands-on rework of §7 IN PROGRESS — its status line is §7.1's (Fable 5.1
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
- §5 Questions for the owner · §5b the owner's answers (2026-10-29)
- §7 The hands-on rework: §7.0 the horizon fix · §7.1 decisions D13–D20
  and the structure (the status line lives there) · §7.2 slice specs ·
  §7.3 how to run this (the next session's prompt) · §7.4 the proposal
  the letters answered
- §8 The strings: the rework's content spec, en / de / ro
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

### 7.1 The rework — status: IN PROGRESS — slice 0 built and reviewed 2026-10-29 (eight seams; the review found nothing on persisted data, 16 items, nine closed in a fix pass — the review note under §7.2's slice 0; gate green, suite +10818 ~10 −1), uncommitted — the `designer` next, then slice 1

**The owner's letters (2026-10-29, in three replies):** "did we take
performance into account? can we make multiple pages?" → D13 was
re-proposed as a hub with pages; "should we have like also per-widget
pages? Like one only for creating/editing/deleting events, one for
creating/editing/deleting categories" → task pages; "and also one for
explaining how recurrent and one time events work (also the quirks of one
time events). Please add these and make it as easy and hands on as
possible" → the recommended letters stand for D13–D19 (D13 A as task
pages, D14 A, D15 A, D16 A, D17 A, D18 A, D19 A) and **D20** adds the page
"One-time and repeating events". The structure as decided:

```
⋮ → How the calendar works                 (the hub: intro, search across every page)
   › Practice calendar                     a calendar that saves nothing
   › The calendar screen                   the month, the bars, the panel, the menus
   HOW DO I…
   › Add, change or delete an event        the editor; nothing is saved until Save; delete; templates
   › One-time and repeating events         the two kinds, converting, the quirks of each
   › Get reminded                          alerts; reminder or alarm; permissions (Samsung); the ring; the quick alarm
   › Keep track of attendance              present / missed; assume absent; counting; the day rail; a note per day
   › Use categories                        what they are; create, change, hide, delete
   › Find an event                         search; filters hide, never delete; the overview
   › Set up the calendar                   holidays; week start; language, dark mode, text size
   › Good to know                          opening the calendar; going back; the rest of ANTA
```

Each task page: one line on what it is, the steps as rows, one "Try it"
sandbox built from the real widget for that task. The practice calendar is
its own full-height page (the real proportions, a banner "nothing here is
saved"); topic and practice pages are plain pushes (a relaunch lands on the
hub). Performance rules: each page builds only its own demos; demo state
lives in the page's `State` (it survives scrolling); every demo stage sits
under a `RepaintBoundary`; the practice grid keeps a per-day map of its six
events; nothing animates; the reviewer checks for per-frame work. The
content spec of the pages and demos is `guide-content-3.md` (the session's
scratchpad; the ARBs are its durable form).

**Slices as decided:** 0 — the sandbox seams (`sandbox` on
`EventEditorSheet.show`, `CategoryPickerSheet`, `EventLookSheet` /
`ColorSwatchPicker`, `CalendarFilterSheet.show`, `CategoryEditorSheet`;
`PanelModeBar` public; `AlarmPage.preview`), each with a no-write test;
1 — the hub, the ten pages with their rows (the 37 already written plus the
new page's), the hub search; 2 — the practice calendar page; 3 — the
"Try it" sandboxes page by page and the alarm preview row; 4 — the flows,
the `design-reviewer`, the docs, the status line. The `designer` draws the
"Try it" card and the hub row once, after slice 0 and before slice 1.

### 7.2 Slice specs

Each slice: one `implementer` (Opus 5.5, high), then one `reviewer`
(slices 0 and 1 may share one review), the gate (`dart analyze lib test`,
the whole `flutter test`, `gen-l10n` with `untranslated.txt` empty, the
must-not-change list re-read against the diff), a check-in with the
uncommitted count, no commit. `flutter test` runs one at a time: the
`designer`'s and `design-reviewer`'s renders are `flutter test` runs too,
so they never overlap an implementer or a `qa` build.

- **Slice 0 — the sandbox seams** (started 2026-10-29 in the planning
  session; if `grep -n "sandbox" lib/widgets/event_editor_sheet.dart` finds
  nothing, it did not land and runs first). `EventEditorSheet.show(…,
  sandbox: false)`: no Save as template, no Linked note, the category
  picker and the Icon & color sheet opened with `sandbox: true`.
  `CategoryPickerSheet`: no Create row. `EventLookSheet` /
  `ColorSwatchPicker`: the palette read-only (no +, no manage, no long-press
  menu; a custom colour either not offered or its picker mode not
  persisted). `CalendarFilterSheet.show`: no Saved filter row, no
  bookmark; the draft still returned. `CategoryEditorSheet`: Save validates
  but writes nothing and returns the would-be category. `_PanelModeBar` →
  public `PanelModeBar`. `AlarmPage.preview(payload)` (or a public preview
  controller): Stop / Snooze / Keep / Open event only close it, back
  closes it, nothing armed, no lock-screen state. `IconPickerSheet`: a
  `sandbox` flag that skips `recordRecentIconKey` (it writes on every
  pick; reachable from the sandboxed editor and category editor), threaded
  from `EventLookSheet` and `CategoryEditorSheet`; the editor's docked
  markdown bar checked for settings writes (the pin toggle). One test per
  seam that drives every affordance under `sandbox: true` and asserts the
  writing rows are absent and the fakes saw no write; every default-path
  suite unchanged. As built (2026-10-29): `EventEditorSheet.show(…,
  sandbox:)` at `event_editor_sheet.dart:238` (a sandboxed new event drops
  the whole Actions group; an existing one keeps Delete), `CategoryPickerSheet
  .pickSingle/pickMulti(sandbox:)`, `EventLookSheet.show(sandbox:)` →
  `ColorSwatchPicker(sandbox:)` (no add, no manage, no long-press menu, no
  custom colour), `CalendarFilterSheet.show(sandbox:)` (no Saved filter row,
  `_loadPresets` skipped, its picker sandboxed), `CategoryEditorSheet.show
  (sandbox:)` (Save pops `_wouldBeSaved()`, a fresh uuid, the alert drafts
  stay in the sheet), public `PanelModeBar` (`calendar_bottom_panel.dart:
  509`), `AlarmPage.preview({payload})` over a private
  `_PreviewRingController` (`alarm_page.dart:82`, `PopScope(canPop: true)`,
  no `RouteAware`, no gateway call).
  **Reviewed 2026-10-29** (one `reviewer`, 16 items, none on persisted
  data; nine closed by one `implementer`, gate green): `AlarmPage.preview`
  must be **pushed on its own page route** — `_close` pops `_route`, and a
  preview hosted off a page route now falls back to `Navigator.maybePop`
  (`alarm_page.dart:83`, :195); the icon picker's `sandbox` threading from
  the Look sheet and the category editor is proven (a seeded recent key
  other than the picked one stays alone after the pick, so dropping the
  argument fails the test); the editor's sandbox test drives Icon & color
  and asserts the recent icons and `CalendarPaletteService.customColors`
  unchanged; the category editor's test arms its write interceptor after
  the icon pick (the picker swallows a failed recent write); the preview
  tests assert `AlertKeepNotice.hasPending` false after every action; the
  sandboxed new-event editor's Details group drops its trailing gap (it is
  the last group there); `_wouldBeSaved()` takes `max(sortOrder) + 1` as
  `CategoryService.create` does; a sandboxed editor seeds `_noteId = null`
  (a demo event never points at a real note — an existing event's Save
  returns `noteId: null` in the sandbox; the guide never reads it). Left as
  found, by decision: the `uuid` import in the category editor; the
  sandboxed alert sound sheet's "from phone" still opens the system
  ringtone picker (nothing stored); the preview reuses the alarm ids, so a
  flow never waits on `alarm-*` while a preview is open;
  `icon_picker_sheet_test.dart` is LF in the working copy (autocrlf
  normalises the commit).
- **Slice 1 — the hub and the pages.** `CalendarGuidePage` becomes the hub
  (intro, the search field, the Practice calendar row, The calendar screen,
  the "How do I…" label, the task pages, Good to know — each row a
  settings-kit row with title + caption + chevron, tap → push). New
  `CalendarGuideTopicPage(topic)` (one widget, a `CalendarGuideTopic` enum
  with the page's title, lead, rows and, later, its demo builder): a
  settings-kit page without search, the lead as the list's `header`, the
  rows as today's `_GuideRow`s. Plain pushes for topic pages (no
  `NavDestinationKind`; a relaunch lands on the hub). The hub search
  (D19 A): a query filters every page's rows (title, description) and shows
  the matches inline, each row captioned with its page's name, the page
  list hidden while a query is live; `SettingsSectionList` can render that
  as one section per matching page. Strings: §8's tables 1–3 (the hub, the
  leads, the new rows) and `guide-content-2.md`'s rows (§8 too) into the
  three ARBs; the retired `calendarGuideCategories*` pair removed; the
  rows redistributed per §8 table 4. Tests: the hub lists its pages and
  pushes each; a topic page renders its lead and rows; the search finds a
  row on another page and names the page; `de` / `ro` at 2.0 on both phone
  sizes for the hub and the longest page; the placeholder-coverage test
  extended to every `calendarGuide*` key; the live-label test kept.
  `26_guide.txt` walks the hub → a page → back (the practice calendar
  joins in slice 4).
- **Slice 2 — the practice calendar page.** `CalendarGuidePracticePage`:
  `SettingsAppBar`-sized bar with the real `CalendarViewMenu` (the format
  choice changes the demo grid; Overview → the caption), the funnel (→
  `CalendarFilterSheet.show(sandbox: true)`, the draft applied to the demo
  grid, the badge counting its axes) and the real `CalendarOverflowMenu`
  (every row → a caption; the guide row → `calendarGuideYouAreHere`); the
  banner under the bar (`calendarGuidePracticeBanner`, `rowGroup` on
  `pageGround`, one line, never moves); a demo month grid — `TableCalendar`
  with `CalendarDayCell` + `CalendarDayBars` through `DayBarsResolver`
  (`CalendarAppearancePreview` is the precedent; `_CalendarTable` in
  `calendar_page.dart:1679` the model to mirror, horizontal swipe only,
  the real appearance and palette read once) over a `_GuideDemoCalendar`
  state object (the six events of §8 table 6, a per-day map, the picked
  day, the format, the filter draft, the caption); `PanelModeBar` and a
  panel that is `DaySummaryPanel` (Day), `DayTimelineView` (Timeline) and
  demo rows through `AgendaDayListRowBuilder` (Upcoming), each fed the
  demo day's events; `CalendarAddFab` → `EventEditorSheet.show(sandbox:
  true)` → the result joins the demo list (`calendarGuideDemoAdded`);
  long press → `EventTemplatePickerSheet` (reads her templates) → a demo
  event (`calendarGuideDemoTemplate`); a row tap → `EventDetailSheet` with
  demo callbacks (Edit → the sandbox editor → `calendarGuideDemoChanged`;
  Skip → `calendarGuideDemoSkipped`; the editor's Delete →
  `calendarGuideDemoDeleted`); the live caption under the bar (a live
  region) and `calendarGuideDemoReset`. Tests: pick a day, add through the
  editor, open, skip, delete, filter, format, each asserting the demo state
  and that no service saw a write (fakes); the page at `de` 2.0 on both
  sizes.
- **Slice 3 — the "Try it" cards on the task pages**, built to the
  designer's spec, one per page: screen (the two menus in a demo bar +
  `PanelModeBar` with the three captions); events (a three-row demo list +
  the real + button, editor, detail sheet, delete); kinds (a demo event
  card with Repeat → `EventRepeatSheet`, Add date → the multi-date picker,
  Skip this day, over a mini month showing its occurrences; captions
  `calendarGuideDemoOneDay` / `DemoRepeats` / `recurrenceSpecificDates` /
  `DemoSkipped`); alerts (Add alert → `AlertEditorSheet` →
  `calendarGuideDemoAlertSet`; the `calendarGuideShowAlarm` row →
  `AlarmPage.preview`; the quick alarm → `calendarGuideDemoHereOnly`; the
  `calendarGuideOpenPermissions` action row → the real page); attendance
  (a tracked demo row with the real presence button and the detail sheet's
  presence captions; the count switch + chips with the editor's example
  captions); categories (a demo category list of three with the eye, a ⋮
  with Edit / Delete, + → `CategoryEditorSheet(sandbox: true)`; lift the
  categories page's row card into a public widget if it separates cleanly,
  else build it from `FormRowGroup` + `EventAvatar`); finding (a search row
  over the six demo events through `EventSearchQuery.parse` +
  `EventQueryMatcher`, `calendarGuideDemoMatches`; the funnel over the kinds
  page's mini month); setup (a dropdown of the holiday sets →
  `HolidaySeeds.forYear` and `calendarGuideDemoHolidays` with the dates; a
  Mon / Sat / Sun `SegmentedButton` turning `CalendarAppearancePreview`;
  the `calendarGuideOpenSettings` action row). Each card: the "Try it"
  label, the lead-in (`calendarGuideTry*`), the stage under a
  `RepaintBoundary`, the caption (a live region, text changes, geometry
  never). Tests per card: every affordance driven, the caption asserted,
  no write seen.
- **Slice 4 — close.** `26_guide.txt` extended (hub → practice: pick a day,
  + → the editor → a title → Save → the row present; open it; the funnel;
  the ⋮ → a caption; back; a task page's card; back to the calendar);
  `08_header.txt` unchanged; the `design-reviewer` over the hub, a task
  page with its card and the practice page (its device-only bucket to the
  `qa-runner`); `qa pass calendar` and `qa pass alerts`; the docs: this
  record's status line, the feature doc's addendum, the `calendar-events`
  file map (the three pages), the `calendar-ui` ids catalogue
  (`calendar-guide-page-<topic>`, `calendar-guide-practice`, the practice
  page's `practice-*` ids for the flow), `rules/calendar.md`'s flow count.

**The designer's brief (before slice 1):** the look of three things, one
mock — the hub row (title, caption, chevron on the kit), the "Try it" card
(the label in the section-label role, the lead-in as a caption, the stage,
the live caption; how it sits between read rows without reading as a
button), and the practice page's banner and bar (the banner's one line,
its ground, the bar at `AppBarMetrics`). Render the current hub and a kit
page with real fonts first; return the spec with its defaults lettered;
the owner answers before slice 1 builds.

### 7.3 How to run this (the next session)

Run on Opus 5.5 at high. Paste:

> Continue the hands-on calendar guide in `frontend/anta`:
> `docs/calendar-guide-page.md` §7 is the record — read §7.1 (the
> decisions and the structure), §7.2 (the slice specs), §8 (the strings),
> and §2 (D1–D12, the page as first built); never the whole file. Load
> `calendar-events`, `calendar-ui`, `ui-language`, `l10n`, `delegation`,
> `ui-revamp`, `verify`. First `git status --short` and `git log -3`:
> everything of 2026-10-29 may still be uncommitted (the guide page, the
> alert horizon, the docs) — leave it as the owner left it. Then check
> whether slice 0 landed (`grep -n "sandbox" lib/widgets/event_editor_sheet.dart`;
> `PanelModeBar` public; `AlarmPage.preview`): if not, run slice 0 with
> one `implementer` from §7.2; if it landed but §7.1's status line does
> not say "slice 0 reviewed", run its `reviewer` first. Then the `designer` (§7.2's
> brief; one mock) and the owner's letters on its defaults; then slices 1,
> 2 and 3, each with one `implementer` and one `reviewer`, the gate after
> each, a check-in with the uncommitted count and a ready commit at each
> boundary; then slice 4 (`design-reviewer`, `qa-runner` for `qa pass
> calendar` and `qa pass alerts`, the docs). One `flutter test` at a time —
> the design agents render through it. Never commit. Update §7.1's status
> line at every boundary.

### 7.4 The proposal the letters answered, kept for the record

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

## 8. The strings — the content spec of the rework (the ARBs are the durable form once a slice lands them)

The first build's 71 keys are in the ARBs already (`calendarGuide*`); the tables below are the additions and changes, copied from the planning session's spec files on 2026-10-29. Conventions: `{placeholder}` ← an existing ARB key, declared `"type": "String"` in the en `@` block (plurals `int`, Romanian needs `few`); quotes en “…”, de „…“, ro „…”; a sentence never retypes a label.

### 8.1 Additions after the owner's answers (`guide-content-2.md`)


#### New rows — Events section

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuideAssumeTitle (row id `assume`, icon the editor's Assume absent glyph if it has one, else `Icons.event_busy_outlined`) | Present unless you say otherwise | Anwesend, solange du nichts anderes sagst | Prezent, dacă nu spui altfel | — |
| calendarGuideAssumeBody | With “{trackPresence}” on, every day counts as “{present}” until you mark it “{missed}”. “{assumeAbsent}” turns that around for things you rarely manage: a day counts as missed until you mark it present. | Mit „{trackPresence}“ gilt jeder Tag als „{present}“, bis du ihn als „{missed}“ markierst. „{assumeAbsent}“ dreht das um – für Dinge, die du selten schaffst: Ein Tag gilt als verpasst, bis du ihn als anwesend markierst. | Cu „{trackPresence}” pornit, fiecare zi contează ca „{present}” până o marchezi „{missed}”. „{assumeAbsent}” inversează regula pentru lucrurile pe care rar le reușești: o zi contează ca ratată până o marchezi ca prezentă. | trackPresence ← eventTrackPresence, present ← eventPresencePresent, missed ← eventPresenceMissed, assumeAbsent ← eventAssumeAbsent |
| calendarGuideCountTitle (row id `count`, icon `Icons.tag_rounded`) | Counting the days | Die Tage zählen | Numărarea zilelor | — |
| calendarGuideCountBody | In a repeating event, “{countOccurrences}” numbers its days. “{countFromOne}” gives Day 1, Day 2, Week 3; “{countFromZero}” counts what has passed, so a birthday reads 1 year, then 2 years. The number shows beside the event on its day. | Bei einem wiederholten Ereignis nummeriert „{countOccurrences}“ seine Tage. „{countFromOne}“ ergibt Tag 1, Tag 2, Woche 3; „{countFromZero}“ zählt, was vergangen ist – ein Geburtstag zeigt dann 1 Jahr, dann 2 Jahre. Die Zahl steht neben dem Ereignis an seinem Tag. | La un eveniment care se repetă, „{countOccurrences}” îi numerotează zilele. „{countFromOne}” dă Ziua 1, Ziua 2, Săptămâna 3; „{countFromZero}” numără ce a trecut, așa că o zi de naștere arată 1 an, apoi 2 ani. Numărul apare lângă eveniment în ziua lui. | countOccurrences ← eventCountOccurrences, countFromOne ← eventCountStyleNumbered, countFromZero ← eventCountStyleElapsed |
| calendarGuideRailTitle (row id `rail`, icon the appearance page's Day rail glyph if it has one, else `Icons.view_sidebar_outlined`) | What “{dayRail}” is | Was „{dayRail}“ ist | Ce este „{dayRail}” | dayRail ← eventShowInDayRail |
| calendarGuideRailBody | “{dayRail}” is a thin strip at the left edge of a day with one mark per tracked event, so a habit stays visible even on a busy day. It is off until you turn it on in “{settingsRow}”, under “{appearance}”; after that each event can choose “{railAuto}”, “{railAlways}” or “{railNever}”. | „{dayRail}“ ist ein schmaler Streifen am linken Rand eines Tages mit einer Marke je erfasstem Ereignis, damit eine Gewohnheit auch an einem vollen Tag sichtbar bleibt. Sie ist aus, bis du sie in „{settingsRow}“ unter „{appearance}“ einschaltest; danach kann jedes Ereignis „{railAuto}“, „{railAlways}“ oder „{railNever}“ wählen. | „{dayRail}” este o fâșie subțire la marginea stângă a unei zile, cu câte un semn pentru fiecare eveniment urmărit, ca un obicei să rămână vizibil chiar și într-o zi plină. Este oprită până o pornești în „{settingsRow}”, la „{appearance}”; după aceea fiecare eveniment poate alege „{railAuto}”, „{railAlways}” sau „{railNever}”. | dayRail ← eventShowInDayRail, settingsRow ← calendarSettingsRow, appearance ← calendarAppearanceSection, railAuto / railAlways / railNever ← the three values of the editor's Day rail menu ("Auto" / "Always" / "Never" — grep `eventShowInDayRail` in `event_editor_sheet.dart` for their keys) |
| calendarGuidePerDayTitle (row id `per-day`, icon `Icons.edit_calendar_outlined`) | A note for one day only | Eine Notiz nur für einen Tag | O notiță doar pentru o zi | — |
| calendarGuidePerDayBody | A repeating event shares one description across all its days. Turn on “{perDay}” and each day can carry its own: open the event on that day and, above the description, choose “{thisDay}” to write for that day alone or “{allDays}” for the shared text. | Ein wiederholtes Ereignis teilt eine Beschreibung über alle seine Tage. Schalte „{perDay}“ ein, und jeder Tag kann eine eigene tragen: Öffne das Ereignis an diesem Tag und wähle über der Beschreibung „{thisDay}“, um nur für diesen Tag zu schreiben, oder „{allDays}“ für den gemeinsamen Text. | Un eveniment care se repetă are o singură descriere pentru toate zilele lui. Pornește „{perDay}” și fiecare zi poate avea una proprie: deschide evenimentul în ziua aceea și, deasupra descrierii, alege „{thisDay}” ca să scrii doar pentru ziua aceea sau „{allDays}” pentru textul comun. | perDay ← eventPerOccurrenceDescriptions, thisDay ← eventDescriptionScopeThisDay, allDays ← eventDescriptionScopeAllDays |
| calendarGuideSkippedTitle (row id `skipped`, icon `Icons.event_busy_rounded`) | Days you skipped | Ausgelassene Tage | Zile sărite | — |
| calendarGuideSkippedBody | “{skip}” removes one day of a repeating event and leaves the others. The event's editing screen lists those days under “{skippedDays}”; untick a day there to bring it back. | „{skip}“ entfernt einen Tag eines wiederholten Ereignisses und lässt die anderen stehen. Der Bearbeitungsbildschirm des Ereignisses listet diese Tage unter „{skippedDays}“; nimm dort den Haken bei einem Tag weg, um ihn zurückzuholen. | „{skip}” elimină o singură zi a unui eveniment care se repetă și le lasă pe celelalte. Ecranul de editare al evenimentului listează acele zile la „{skippedDays}”; debifează acolo o zi ca s-o aduci înapoi. | skip ← eventSkipOccurrence, skippedDays ← eventSkippedDays |
| calendarGuidePriorityTitle (row id `priority`, icon the editor's Priority glyph, else `Icons.flag_outlined`) | Priority and the look | Priorität und Aussehen | Prioritatea și aspectul | — |
| calendarGuidePriorityBody | “{priority}” orders the events of a busy day and decides which of them get a bar on the month when there are more than three. “{iconColor}” gives one event its own icon or colour instead of its category's. | „{priority}“ ordnet die Ereignisse eines vollen Tages und entscheidet, welche davon einen Balken im Monat bekommen, wenn es mehr als drei sind. „{iconColor}“ gibt einem Ereignis ein eigenes Symbol oder eine eigene Farbe statt der seiner Kategorie. | „{priority}” ordonează evenimentele unei zile pline și decide care dintre ele primesc o bară în lună când sunt mai mult de trei. „{iconColor}” dă unui eveniment propria pictogramă sau culoare în locul celei a categoriei. | priority ← eventPriority, iconColor ← eventAppearance |

#### Changed row — Reminders and alarms

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuidePermissionsBody (replaces the current value; one new placeholder) | The first time, ANTA asks for permission to show notifications and to set alarms. Allow them, or nothing rings. On a Samsung phone also turn on “{battery}” there, or its battery saver can hold reminders back. If something stays silent later, open the main menu (three lines, top left), then “{permissions}”, and turn on what is missing. | Beim ersten Mal bittet ANTA um die Erlaubnis, Benachrichtigungen zu zeigen und Alarme zu stellen. Erlaube beides, sonst klingelt nichts. Auf einem Samsung-Telefon schalte dort auch „{battery}“ ein, sonst kann der Energiesparmodus Erinnerungen zurückhalten. Bleibt später etwas stumm, öffne das Hauptmenü (drei Striche, oben links), dann „{permissions}“, und schalte ein, was fehlt. | Prima dată, ANTA cere permisiunea de a afișa notificări și de a seta alarme. Acordă-le, altfel nimic nu sună. Pe un telefon Samsung pornește acolo și „{battery}”, altfel economisirea bateriei poate reține alertele. Dacă mai târziu ceva rămâne mut, deschide meniul principal (trei linii, stânga sus), apoi „{permissions}”, și pornește ce lipsește. | permissions ← permissionsTitle, battery ← alertsBattery |

#### Changed row — "Open ANTA now and then" (the horizon is ten fires per alert since 2026-10-29)

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuideOpenOftenBody (replaces the current value) | ANTA lines up the next reminders each time you open it — about ten of each. Open the app every week or so and they never run out. | ANTA bereitet die nächsten Erinnerungen jedes Mal vor, wenn du es öffnest – etwa zehn von jeder. Öffne die App etwa einmal pro Woche, und sie gehen nie aus. | ANTA pregătește următoarele alerte de fiecare dată când o deschizi – cam zece din fiecare. Deschide aplicația cam o dată pe săptămână și ele nu se termină niciodată. | — |

### 8.2 The hands-on pages and demos (`guide-content-3.md`)


#### 1. The hub (`CalendarGuidePage`, the ⋮ row's target; title stays `calendarGuideTitle`)

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuideIntro (replaces the current value) | A short tour of the calendar, one page per thing you will want to do. Each page has a “{tryIt}” corner where you can tap without changing anything real. You can come back here any time: on the calendar, tap the three-dot button at the top right, then “{title}”. | Ein kurzer Rundgang durch den Kalender, eine Seite pro Aufgabe. Jede Seite hat eine Ecke „{tryIt}“, in der du tippen kannst, ohne etwas Echtes zu verändern. Du kommst jederzeit hierher zurück: Tippe im Kalender oben rechts auf die drei Punkte und dann auf „{title}“. | Un scurt tur al calendarului, câte o pagină pentru fiecare lucru pe care vei vrea să-l faci. Fiecare pagină are un colț „{tryIt}” unde poți atinge fără să schimbi nimic real. Poți reveni aici oricând: în calendar, atinge butonul cu trei puncte din dreapta sus, apoi „{title}”. | tryIt ← calendarGuideTryIt, title ← calendarGuideTitle |
| calendarGuideTryIt | Try it | Probier es aus | Încearcă | — |
| calendarGuideHowDoI (the hub's label over the task pages) | How do I… | Wie mache ich … | Cum fac să… | — |
| calendarGuidePagePractice | Practice calendar | Übungskalender | Calendar de exercițiu | — |
| calendarGuidePagePracticeCaption | A calendar that saves nothing. Try everything here. | Ein Kalender, der nichts speichert. Probier hier alles aus. | Un calendar care nu salvează nimic. Încearcă totul aici. | — |
| (page title) calendarGuideSectionCalendar — reused | The calendar screen | Der Kalender | Ecranul calendarului | — |
| calendarGuidePageScreenCaption | The month, the bars, the panel, the menus | Der Monat, die Balken, der Bereich darunter, die Menüs | Luna, barele, panoul, meniurile | — |
| calendarGuidePageEvents | Add, change or delete an event | Ein Ereignis hinzufügen, ändern oder löschen | Adaugă, modifică sau șterge un eveniment | — |
| calendarGuidePageEventsCaption | The editor, saving, deleting, templates | Der Editor, Speichern, Löschen, Vorlagen | Editorul, salvarea, ștergerea, șabloanele | — |
| calendarGuidePageKinds | One-time and repeating events | Einmalige und wiederholte Ereignisse | Evenimente o singură dată și repetate | — |
| calendarGuidePageKindsCaption | How the two kinds differ, and the quirks of each | Wie sich die beiden Arten unterscheiden, und ihre Eigenheiten | Cum diferă cele două feluri și ciudățeniile fiecăruia | — |
| calendarGuidePageAlerts | Get reminded | Erinnert werden | Primește alerte | — |
| calendarGuidePageAlertsCaption | Reminders, alarms, permissions, the quick alarm | Mitteilungen, Alarme, Berechtigungen, der schnelle Alarm | Notificări, alarme, permisiuni, alarma rapidă | — |
| calendarGuidePageAttendance | Keep track of attendance | Anwesenheit festhalten | Ține evidența prezenței | — |
| calendarGuidePageAttendanceCaption | Present or missed, counting, “{dayRail}”, a note per day | Anwesend oder verpasst, Zählen, „{dayRail}“, eine Notiz pro Tag | Prezent sau ratat, numărarea, „{dayRail}”, o notiță pe zi | dayRail ← eventShowInDayRail |
| calendarGuidePageCategories | Use categories | Kategorien nutzen | Folosește categoriile | — |
| calendarGuidePageCategoriesCaption | What they are; create, change, hide, delete | Was sie sind; anlegen, ändern, verstecken, löschen | Ce sunt; creează, modifică, ascunde, șterge | — |
| calendarGuidePageFinding | Find an event | Ein Ereignis finden | Găsește un eveniment | — |
| calendarGuidePageFindingCaption | Search, filters, “{overview}” | Suche, Filter, „{overview}“ | Căutare, filtre, „{overview}” | overview ← calendarOverview |
| calendarGuidePageSetup | Set up the calendar | Den Kalender einrichten | Configurează calendarul | — |
| calendarGuidePageSetupCaption | Holidays, the week's first day, language and dark mode | Feiertage, der erste Wochentag, Sprache und dunkles Design | Sărbătorile, prima zi a săptămânii, limba și modul întunecat | — |
| (page title) calendarGuideSectionGood — reused | Good to know | Gut zu wissen | Bine de știut | — |
| calendarGuidePageGoodCaption | Opening the calendar, going back, the rest of ANTA | Den Kalender öffnen, zurück, der Rest von ANTA | Deschiderea calendarului, înapoi, restul aplicației ANTA | — |

#### 2. Page leads (one line under each page's title, above its rows)

| key | en | de | ro |
|---|---|---|---|
| calendarGuideScreenLead | What you see when the calendar opens, and what each part is for. | Was du siehst, wenn der Kalender öffnet, und wofür jeder Teil da ist. | Ce vezi când se deschide calendarul și la ce folosește fiecare parte. |
| calendarGuideEventsLead | An event is anything with a day: an appointment, a bill, a class. Here is how you add one, change it and remove it. | Ein Ereignis ist alles, was einen Tag hat: ein Termin, eine Rechnung, ein Kurs. So fügst du eines hinzu, änderst es und entfernst es. | Un eveniment este orice are o zi: o programare, o factură, un curs. Iată cum adaugi unul, cum îl modifici și cum îl elimini. |
| calendarGuideKindsLead | Most events happen once. Some come back every week or month. The calendar treats the two a little differently. | Die meisten Ereignisse passieren einmal. Manche kommen jede Woche oder jeden Monat wieder. Der Kalender behandelt die beiden etwas unterschiedlich. | Cele mai multe evenimente se întâmplă o dată. Unele revin în fiecare săptămână sau lună. Calendarul le tratează puțin diferit. |
| calendarGuideAlertsLead | Nothing rings by itself. You add a reminder or an alarm to the events that need one. | Nichts klingelt von allein. Du fügst den Ereignissen, die es brauchen, eine Mitteilung oder einen Alarm hinzu. | Nimic nu sună de la sine. Adaugi o notificare sau o alarmă evenimentelor care au nevoie. |
| calendarGuideAttendanceLead | For a class or a habit you want to keep count of, the calendar can remember which days you made it. | Bei einem Kurs oder einer Gewohnheit, die du mitzählen willst, merkt sich der Kalender, an welchen Tagen du es geschafft hast. | Pentru un curs sau un obicei pe care vrei să-l ții la socoteală, calendarul poate reține în ce zile ai reușit. |
| calendarGuideCategoriesLead | A category gives an event its colour and icon. The app comes with a few; make your own and hide the ones you never use. | Eine Kategorie gibt einem Ereignis Farbe und Symbol. Die App bringt ein paar mit; leg eigene an und verstecke die, die du nie brauchst. | O categorie dă unui eveniment culoarea și pictograma. Aplicația vine cu câteva; fă-ți propriile categorii și ascunde-le pe cele pe care nu le folosești niciodată. |
| calendarGuideFindingLead | Three ways to find something: search by name, hide what you do not want to see, or look at a whole year. | Drei Wege, etwas zu finden: nach dem Namen suchen, ausblenden, was du nicht sehen willst, oder ein ganzes Jahr betrachten. | Trei moduri de a găsi ceva: caută după nume, ascunde ce nu vrei să vezi sau privește un an întreg. |
| calendarGuideSetupLead | A few settings make the calendar yours: whose holidays it shows, which day starts the week, and the app's language and look. | Ein paar Einstellungen machen den Kalender zu deinem: wessen Feiertage er zeigt, welcher Tag die Woche beginnt, und Sprache und Aussehen der App. | Câteva setări fac calendarul al tău: ale cui sărbători le arată, ce zi începe săptămâna, limba și aspectul aplicației. |

#### 3. New rows

##### 3.1 "One-time and repeating events" (after the existing `calendarGuideRepeat*` row, which opens the page)

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuideKindsOneTitle (row id `kinds-one`, icon `Icons.looks_one_outlined`) | One day, or many | Ein Tag oder viele | O zi sau mai multe | — |
| calendarGuideKindsOneBody | A new event is one-time: it lives on one day. Give it a rule in “{repeat}” and it becomes repeating, showing on every matching day. Choose “{doesNotRepeat}” again and it is one-time once more, on its start day. | Ein neues Ereignis ist einmalig: Es lebt an einem Tag. Gib ihm in „{repeat}“ eine Regel, und es wiederholt sich – es erscheint an jedem passenden Tag. Wähle wieder „{doesNotRepeat}“, und es ist erneut einmalig, an seinem Starttag. | Un eveniment nou este o singură dată: trăiește într-o singură zi. Dă-i o regulă în „{repeat}” și devine repetat, apărând în fiecare zi potrivită. Alege din nou „{doesNotRepeat}” și este iar o singură dată, în ziua lui de început. | repeat ← eventRepeat, doesNotRepeat ← recurrenceDoesNotRepeat |
| calendarGuideKindsDatesTitle (row id `kinds-dates`, icon `Icons.event_repeat_outlined`) | A one-time event can have extra dates | Ein einmaliges Ereignis kann weitere Termine haben | Un eveniment o singură dată poate avea date în plus | — |
| calendarGuideKindsDatesBody | “{addDate}” adds another day to a one-time event. It is then neither one-time nor repeating: “{repeat}” reads “{threeDates}”, the “{dates}” row lists the days, and “{skip}” works on each of them. From the event's page, “{addDate}” saves at once. | „{addDate}“ fügt einem einmaligen Ereignis einen weiteren Tag hinzu. Dann ist es weder einmalig noch wiederholt: „{repeat}“ zeigt „{threeDates}“, die Zeile „{dates}“ listet die Tage, und „{skip}“ wirkt auf jeden davon. Von der Seite des Ereignisses aus speichert „{addDate}“ sofort. | „{addDate}” adaugă încă o zi unui eveniment o singură dată. Atunci nu mai este nici o singură dată, nici repetat: „{repeat}” arată „{threeDates}”, rândul „{dates}” listează zilele, iar „{skip}” funcționează pe fiecare dintre ele. Din pagina evenimentului, „{addDate}” salvează imediat. | addDate ← eventAddDate, repeat ← eventRepeat, threeDates ← recurrenceSpecificDates(3), dates ← eventDatesLabel, skip ← eventSkipOccurrence |
| calendarGuideKindsOnlyOneTitle (row id `kinds-only-one`, icon `Icons.filter_1_outlined`) | What only a one-time event can do | Was nur ein einmaliges Ereignis kann | Ce poate doar un eveniment o singură dată | — |
| calendarGuideKindsOnlyOneBody | “{removeAfter}” is for one-time events only: the alarm deletes its event once you stop it. And “{noticeSkip}” on the quiet notice before an alarm switches a one-time event's alert off, where on a repeating event it skips that day. | „{removeAfter}“ gibt es nur bei einmaligen Ereignissen: Der Alarm löscht sein Ereignis, sobald du ihn stoppst. Und „{noticeSkip}“ auf dem leisen Hinweis vor einem Alarm schaltet die Erinnerung eines einmaligen Ereignisses aus, während es bei einem wiederholten diesen Tag auslässt. | „{removeAfter}” există doar la evenimentele o singură dată: alarma își șterge evenimentul odată ce o oprești. Iar „{noticeSkip}” de pe înștiințarea discretă dinaintea unei alarme oprește alerta unui eveniment o singură dată, pe când la unul repetat sare peste ziua aceea. | removeAfter ← eventAlertRemoveAfter, noticeSkip ← alertsSkipAction |
| calendarGuideKindsOnlyRepeatTitle (row id `kinds-only-repeat`, icon `Icons.all_inclusive_rounded`) | What only a repeating event can do | Was nur ein wiederholtes Ereignis kann | Ce poate doar un eveniment repetat | — |
| calendarGuideKindsOnlyRepeatBody | “{trackPresence}”, “{countOccurrences}” and a separate note per day appear once an event has more than one day. “{skip}” drops one day and keeps the rest; “{skippedDays}” in the editor lists them. | „{trackPresence}“, „{countOccurrences}“ und eine eigene Notiz pro Tag erscheinen, sobald ein Ereignis mehr als einen Tag hat. „{skip}“ lässt einen Tag aus und behält die anderen; „{skippedDays}“ im Editor listet sie auf. | „{trackPresence}”, „{countOccurrences}” și o notiță separată pe zi apar odată ce un eveniment are mai mult de o zi. „{skip}” renunță la o zi și le păstrează pe celelalte; „{skippedDays}” din editor le listează. | trackPresence ← eventTrackPresence, countOccurrences ← eventCountOccurrences, skip ← eventSkipOccurrence, skippedDays ← eventSkippedDays |
| calendarGuideKindsOneChangeTitle (row id `kinds-one-change`, icon `Icons.sync_alt_rounded`) | One change, every day | Eine Änderung, alle Tage | O modificare, toate zilele | — |
| calendarGuideKindsOneChangeBody | Editing a repeating event changes all of its days at once: a new time moves every session. To change just one day, skip it and add a one-time event for that day instead. | Wer ein wiederholtes Ereignis bearbeitet, ändert alle seine Tage auf einmal: Eine neue Uhrzeit verschiebt jede Sitzung. Um nur einen Tag zu ändern, lass ihn aus und lege stattdessen ein einmaliges Ereignis für diesen Tag an. | Editarea unui eveniment repetat schimbă toate zilele lui deodată: o oră nouă mută fiecare ședință. Ca să schimbi doar o zi, sari peste ea și adaugă în schimb un eveniment o singură dată pentru ziua aceea. | — |
| calendarGuideKindsTrickyTitle (row id `kinds-tricky`, icon `Icons.warning_amber_rounded`) | Where repeating gets tricky | Wo Wiederholung tückisch wird | Unde repetarea devine înșelătoare | — |
| calendarGuideKindsTrickyBody | A monthly event on the 31st skips the months without a 31st; a yearly one on 29 February shows only in leap years. “{ends}” inside “{repeat}” stops a rule after a date, and “{alsoBefore}” lets it show on matching days before the start. | Ein monatliches Ereignis am 31. überspringt die Monate ohne 31.; ein jährliches am 29. Februar erscheint nur in Schaltjahren. „{ends}“ in „{repeat}“ beendet eine Regel nach einem Datum, und „{alsoBefore}“ lässt sie an passenden Tagen vor dem Start erscheinen. | Un eveniment lunar pe 31 sare peste lunile fără 31; unul anual pe 29 februarie apare doar în anii bisecți. „{ends}” din „{repeat}” oprește o regulă după o dată, iar „{alsoBefore}” o lasă să apară în zilele potrivite dinaintea începutului. | ends ← recurrenceEnds, repeat ← eventRepeat, alsoBefore ← recurrenceBeforeStart |
| calendarGuideKindsBirthdayTitle (row id `kinds-birthday`, icon `Icons.cake_outlined`) | Birthdays | Geburtstage | Zile de naștere | — |
| calendarGuideKindsBirthdayBody | Picking the “{birthday}” category on a new event makes it yearly and counts from 0 — set its start date to the real birth date and the event reads the person's age. | Wer bei einem neuen Ereignis die Kategorie „{birthday}“ wählt, macht es jährlich und lässt es ab 0 zählen – setze das Startdatum auf den echten Geburtstag, und das Ereignis zeigt das Alter der Person. | Alegerea categoriei „{birthday}” la un eveniment nou îl face anual și îl pune să numere de la 0 – setează data de început la ziua reală de naștere și evenimentul arată vârsta persoanei. | birthday ← eventCategoryBirthday |

##### 3.2 "Use categories" (the existing `calendarGuideCategory*` row from Events opens the page as "What a category is"; `calendarGuideCategories*` from Make it yours is retired — its content is split below)

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuideCatCreateTitle (row id `cat-create`, icon `Icons.add_circle_outline_rounded`) | Create one | Eine anlegen | Creează una | — |
| calendarGuideCatCreateBody | In “{settingsRow}”, open “{categories}” and tap the + button (“{createCategory}”). Give it a name, pick an icon and a colour, then “{save}”. It is offered in every event from then on. | Öffne in „{settingsRow}“ den Punkt „{categories}“ und tippe auf die Taste + („{createCategory}“). Gib ihr einen Namen, wähle ein Symbol und eine Farbe und dann „{save}“. Ab dann wird sie in jedem Ereignis angeboten. | În „{settingsRow}”, deschide „{categories}” și atinge butonul + („{createCategory}”). Dă-i un nume, alege o pictogramă și o culoare, apoi „{save}”. De atunci este oferită în fiecare eveniment. | settingsRow ← calendarSettingsRow, categories ← calendarCategories, createCategory ← createCategory, save ← save |
| calendarGuideCatChangeTitle (row id `cat-change`, icon `Icons.edit_outlined`) | Change one | Eine ändern | Modifică una | — |
| calendarGuideCatChangeBody | Tap a category in the list to change its icon or colour. The ones that came with the app keep their names; your own can be renamed. | Tippe in der Liste auf eine Kategorie, um Symbol oder Farbe zu ändern. Die mitgelieferten behalten ihren Namen; deine eigenen kannst du umbenennen. | Atinge o categorie din listă ca să-i schimbi pictograma sau culoarea. Cele venite cu aplicația își păstrează numele; ale tale pot fi redenumite. | — |
| calendarGuideCatHideTitle (row id `cat-hide`, icon `Icons.visibility_off_outlined`) | Hide the ones you do not use | Verstecke, was du nicht brauchst | Ascunde-le pe cele pe care nu le folosești | — |
| calendarGuideCatHideBody | The eye on a row (“{hide}”) takes a category out of the pickers. Events that already have it keep their colour and stay on the calendar. Tap the eye again (“{show}”) to bring it back. | Das Auge an einer Zeile („{hide}“) nimmt eine Kategorie aus der Auswahl. Ereignisse, die sie schon haben, behalten ihre Farbe und bleiben im Kalender. Tippe wieder auf das Auge („{show}“), um sie zurückzuholen. | Ochiul de pe un rând („{hide}”) scoate o categorie din liste. Evenimentele care o au deja își păstrează culoarea și rămân în calendar. Atinge ochiul din nou („{show}”) ca s-o aduci înapoi. | hide ← hide, show ← show |
| calendarGuideCatDeleteTitle (row id `cat-delete`, icon `Icons.delete_outline_rounded`) | Delete one | Eine löschen | Șterge una | — |
| calendarGuideCatDeleteBody | The ⋮ on your own category offers “{delete}”. Its events are not lost: they move to “{other}”. The categories that came with the app cannot be deleted, only hidden. | Das ⋮ an deiner eigenen Kategorie bietet „{delete}“ an. Ihre Ereignisse gehen nicht verloren: Sie wandern zu „{other}“. Die mitgelieferten Kategorien lassen sich nicht löschen, nur verstecken. | ⋮ de pe categoria ta oferă „{delete}”. Evenimentele ei nu se pierd: trec la „{other}”. Categoriile venite cu aplicația nu pot fi șterse, doar ascunse. | delete ← the plain "Delete" action key (`delete`; grep `"delete": "Delete"`), other ← the built-in Other category's name key (grep the value "Other" among `eventCategory*`) |
| calendarGuideCatAlertsTitle (row id `cat-alerts`, icon `Icons.notifications_none_rounded`) | An alert for a whole category | Eine Erinnerung für eine ganze Kategorie | O alertă pentru o categorie întreagă | — |
| calendarGuideCatAlertsBody | Inside a category, “{addAlert}” sets a reminder or alarm that every event in that category gets automatically — handy for appointments. An event can switch it off for itself with “{categoryAlerts}”. | In einer Kategorie legt „{addAlert}“ eine Mitteilung oder einen Alarm fest, den jedes Ereignis dieser Kategorie automatisch bekommt – praktisch für Termine. Ein Ereignis kann das für sich mit „{categoryAlerts}“ abschalten. | În interiorul unei categorii, „{addAlert}” stabilește o notificare sau o alarmă pe care o primește automat fiecare eveniment din categoria aceea – util pentru programări. Un eveniment o poate opri pentru el însuși cu „{categoryAlerts}”. | addAlert ← eventAlertAdd, categoryAlerts ← the editor's "Category alerts" switch key (grep the value "Category alerts") |

#### 4. Where every row lives (the hub order; rows in page order)

- **The calendar screen**: lead `calendarGuideScreenLead`; rows month, marks, panel, views. Demo: the demo bar (`CalendarViewMenu` + `CalendarOverflowMenu`) and `PanelModeBar` (§5).
- **Add, change or delete an event**: lead `calendarGuideEventsLead`; rows add-event, time, open, description, unsaved, templates. Demo: a demo list with the real + button, editor, detail sheet, delete.
- **One-time and repeating events**: lead `calendarGuideKindsLead`; rows repeat (`calendarGuideRepeat*`), kinds-one, kinds-dates, kinds-only-one, kinds-only-repeat, kinds-one-change, kinds-tricky, kinds-birthday, skipped (`calendarGuideSkipped*`). Demo: the kinds sandbox.
- **Get reminded**: lead `calendarGuideAlertsLead`; rows add-alert, alert-kinds, permissions (the Samsung body), ring, open-often (the softened body), quick-alarm, hub. Demos: the alert sheet, "Show me the alarm screen", the quick alarm; the action row "Open Permissions".
- **Keep track of attendance**: lead `calendarGuideAttendanceLead`; rows attendance, assume, count, rail, per-day. Demos: the presence row, the count chips.
- **Use categories**: lead `calendarGuideCategoriesLead`; rows category (`calendarGuideCategory*`, retitled by its existing key — leave), cat-create, cat-change, cat-hide, cat-delete, cat-alerts. Demo: the category list sandbox.
- **Find an event**: lead `calendarGuideFindingLead`; rows search, filters, overview. Demos: the search box; the funnel into the filter sheet over a mini month.
- **Set up the calendar**: lead `calendarGuideSetupLead`; rows settings, holidays, week-start, language. Demos: the holiday set list, the week-start strip; the action row "Open Calendar settings". (`calendarGuideCategories*` retired: covered by Use categories.)
- **Good to know**: rows opening, back, notes. No demo.
- **The practice calendar**: its own page (§6).

#### 5. Demo strings — the "Try it" cards

| key | en | de | ro | placeholders |
|---|---|---|---|---|
| calendarGuideTryScreen | Tap the title and the three dots, then switch the panel's mode. | Tippe auf den Titel und die drei Punkte, dann wechsle den Modus des Bereichs. | Atinge titlul și cele trei puncte, apoi schimbă modul panoului. | — |
| calendarGuideTryEvents | Add an event with +, open it, change it, delete it. Nothing here is real. | Füge mit + ein Ereignis hinzu, öffne es, ändere es, lösche es. Nichts hier ist echt. | Adaugă un eveniment cu +, deschide-l, modifică-l, șterge-l. Nimic de aici nu este real. | — |
| calendarGuideTryKinds | Make the event repeat, give it extra dates, skip a day, and watch the month. | Lass das Ereignis sich wiederholen, gib ihm weitere Termine, lass einen Tag aus und beobachte den Monat. | Fă evenimentul să se repete, dă-i date în plus, sari peste o zi și privește luna. | — |
| calendarGuideTryAlerts | Add an alert to the demo event, then see what an alarm looks like. | Füge dem Demo-Ereignis eine Erinnerung hinzu und sieh dir an, wie ein Alarm aussieht. | Adaugă o alertă evenimentului demonstrativ, apoi vezi cum arată o alarmă. | — |
| calendarGuideTryAttendance | Mark a few days present or missed and watch the count. | Markiere ein paar Tage als anwesend oder verpasst und sieh dir die Zählung an. | Marchează câteva zile ca prezent sau ratat și urmărește numărătoarea. | — |
| calendarGuideTryCategories | Create a category, hide one, delete one — in this list only. | Lege eine Kategorie an, verstecke eine, lösche eine – nur in dieser Liste. | Creează o categorie, ascunde una, șterge una – doar în lista aceasta. | — |
| calendarGuideTryFinding | Type a word, a category or a date, and filter the month. | Gib ein Wort, eine Kategorie oder ein Datum ein und filtere den Monat. | Scrie un cuvânt, o categorie sau o dată și filtrează luna. | — |
| calendarGuideTrySetup | Pick a holiday set and a first day of the week; the sample week follows. | Wähle Feiertage und einen ersten Wochentag; die Beispielwoche folgt. | Alege un set de sărbători și o primă zi a săptămânii; săptămâna-exemplu urmează. | — |
| calendarGuideWouldOpen | In the real calendar this would open “{what}”. | Im echten Kalender würde das „{what}“ öffnen. | În calendarul adevărat, asta ar deschide „{what}”. | what ← alertsTitle / calendarSettingsRow / calendarOverview as picked |
| calendarGuideWouldShare | In the real calendar this would share a file with every event. | Im echten Kalender würde das eine Datei mit allen Ereignissen teilen. | În calendarul adevărat, asta ar partaja un fișier cu toate evenimentele. | — |
| calendarGuideYouAreHere | That is this guide — you are already in it. | Das ist dieser Leitfaden – du bist schon drin. | Acesta este ghidul – ești deja în el. | — |
| calendarGuideDemoFormat | Showing “{format}”. | Zeigt „{format}“. | Se arată „{format}”. | format ← calendarFormatMonth / calendarFormatTwoWeeks / calendarFormatWeek as picked |
| calendarGuideDemoPanelDay | “{day}” lists what is on the picked day. | „{day}“ listet, was am gewählten Tag ansteht. | „{day}” listează ce este în ziua aleasă. | day ← panelModeDay |
| calendarGuideDemoPanelTimeline | “{timeline}” draws the day by the hour; all-day events sit above. | „{timeline}“ zeichnet den Tag nach Uhrzeit; ganztägige Ereignisse stehen oben. | „{timeline}” desenează ziua pe ore; evenimentele de toată ziua stau deasupra. | timeline ← panelModeTimeline |
| calendarGuideDemoPanelUpcoming | “{upcoming}” lists what is coming over the next weeks, whatever day is picked. | „{upcoming}“ listet, was in den nächsten Wochen ansteht, egal welcher Tag gewählt ist. | „{upcoming}” listează ce urmează în săptămânile următoare, oricare ar fi ziua aleasă. | upcoming ← upcomingEvents |
| calendarGuidePickedDay | {date}: {count, plural, =0{nothing planned} =1{one event} other{{count} events}} | {date}: {count, plural, =0{nichts geplant} =1{ein Ereignis} other{{count} Ereignisse}} | {date}: {count, plural, =0{nimic planificat} =1{un eveniment} few{{count} evenimente} other{{count} de evenimente}} | date: String (the long weekday-date from intl), count: int |
| calendarGuideDemoAdded | Added “{title}” on {date}. Here it is gone when you leave; in the real calendar it stays. | „{title}“ am {date} hinzugefügt. Hier ist es beim Verlassen weg; im echten Kalender bleibt es. | „{title}” adăugat pe {date}. Aici dispare când pleci; în calendarul adevărat rămâne. | title, date |
| calendarGuideDemoChanged | Saved the change to “{title}”. | Änderung an „{title}“ gespeichert. | Modificarea la „{title}” a fost salvată. | title |
| calendarGuideDemoDeleted | Deleted “{title}” — all of its days. | „{title}“ gelöscht – mit allen seinen Tagen. | „{title}” șters – cu toate zilele lui. | title |
| calendarGuideDemoSkipped | Skipped {date} for “{title}”; the other days stay. | {date} für „{title}“ ausgelassen; die anderen Tage bleiben. | Ai sărit peste {date} pentru „{title}”; celelalte zile rămân. | date, title |
| calendarGuideDemoTemplate | Added “{title}” from a template. | „{title}“ aus einer Vorlage hinzugefügt. | „{title}” adăugat dintr-un șablon. | title |
| calendarGuideDemoFiltered | {count, plural, =0{No filter on} =1{One filter on — the funnel shows it} other{{count} filters on — the funnel shows them}} | {count, plural, =0{Kein Filter aktiv} =1{Ein Filter aktiv – der Trichter zeigt es} other{{count} Filter aktiv – der Trichter zeigt es}} | {count, plural, =0{Niciun filtru activ} =1{Un filtru activ – pâlnia îl arată} few{{count} filtre active – pâlnia le arată} other{{count} de filtre active – pâlnia le arată}} | count: int (the draft's active axes, as the bar's badge counts them) |
| calendarGuideDemoReset | Start over | Von vorn | De la capăt | — |
| calendarGuideDemoLongPressHint | Press and hold + for templates and the quick alarm. | Halte + gedrückt für Vorlagen und den schnellen Alarm. | Ține apăsat + pentru șabloane și alarma rapidă. | — |
| calendarGuideDemoAlertSet | “{title}” now has: {alert}. In the real calendar this is saved with the event. | „{title}“ hat jetzt: {alert}. Im echten Kalender wird das mit dem Ereignis gespeichert. | „{title}” are acum: {alert}. În calendarul adevărat, asta se salvează cu evenimentul. | title, alert ← `EventAlert.describe` |
| calendarGuideShowAlarm (an action row) | Show me the alarm screen | Zeig mir den Alarmbildschirm | Arată-mi ecranul alarmei | — |
| calendarGuideDemoHereOnly | {message} — here only. | {message} – nur hier. | {message} – doar aici. | message ← e.g. `quickAlarmSet(title, time)` |
| calendarGuideDemoOneDay | One day only: {date}. | Nur ein Tag: {date}. | O singură zi: {date}. | date |
| calendarGuideDemoRepeats | {rule} — {count, plural, =1{one day this month} other{{count} days this month}} | {rule} – {count, plural, =1{ein Tag in diesem Monat} other{{count} Tage in diesem Monat}} | {rule} – {count, plural, =1{o zi luna aceasta} few{{count} zile luna aceasta} other{{count} de zile luna aceasta}} | rule ← `RecurrenceFormatter` words, count: int |
| calendarGuideDemoCatCreated | Created “{name}” — here only. | „{name}“ angelegt – nur hier. | „{name}” creată – doar aici. | name |
| calendarGuideDemoCatHidden | “{name}” is hidden: not offered for new events; its events stay. | „{name}“ ist versteckt: nicht mehr für neue Ereignisse angeboten; seine Ereignisse bleiben. | „{name}” este ascunsă: nu mai este oferită pentru evenimente noi; evenimentele ei rămân. | name |
| calendarGuideDemoCatDeleted | Deleted “{name}”; its events moved to “{other}”. | „{name}“ gelöscht; seine Ereignisse sind jetzt bei „{other}“. | „{name}” ștearsă; evenimentele ei au trecut la „{other}”. | name, other ← the Other category's name key |
| calendarGuideDemoMatches | {count, plural, =0{No event matches} =1{One event matches} other{{count} events match}} | {count, plural, =0{Kein Ereignis passt} =1{Ein Ereignis passt} other{{count} Ereignisse passen}} | {count, plural, =0{Niciun eveniment nu se potrivește} =1{Un eveniment se potrivește} few{{count} evenimente se potrivesc} other{{count} de evenimente se potrivesc}} | count: int |
| calendarGuideDemoHolidays | {count, plural, =1{One public holiday in {year}} other{{count} public holidays in {year}}} | {count, plural, =1{Ein Feiertag im Jahr {year}} other{{count} Feiertage im Jahr {year}}} | {count, plural, =1{O sărbătoare legală în {year}} few{{count} sărbători legale în {year}} other{{count} de sărbători legale în {year}}} | count: int, year: String |
| calendarGuideOpenPermissions (an action row) | Open “{permissions}” | „{permissions}“ öffnen | Deschide „{permissions}” | permissions ← permissionsTitle |
| calendarGuideOpenSettings (an action row) | Open “{settingsRow}” | „{settingsRow}“ öffnen | Deschide „{settingsRow}” | settingsRow ← calendarSettingsRow |

Reused as they are: the detail sheet's presence captions ("{attended}/{total} attended · last {days} days", "Streak {count} · best {best}"), the editor's count example captions, `quickAlarmSet`, `recurrenceSpecificDates`, `upcomingSearchHint`, `hide` / `show`, `eventMarkPresent` / `eventMarkMissed`.

#### 6. The practice calendar page

| key | en | de | ro |
|---|---|---|---|
| (title) calendarGuidePagePractice | Practice calendar | Übungskalender | Calendar de exercițiu |
| calendarGuidePracticeBanner | Nothing here is saved. Tap, add, change — it all disappears when you leave. | Hier wird nichts gespeichert. Tippe, füge hinzu, ändere – beim Verlassen ist alles weg. | Nimic de aici nu se salvează. Atinge, adaugă, modifică – totul dispare când pleci. |

The six demo events (`guide-demo-<slug>` ids; the demo picks categories from the visible catalog in order, cycling; the birthday takes the Birthday built-in when it is visible):

| key | en | de | ro | shape |
|---|---|---|---|---|
| calendarGuideDemoEventDentist | Dentist | Zahnarzt | Dentist | one-time, today + 2, 09:00–09:45 |
| calendarGuideDemoEventYoga | Yoga | Yoga | Yoga | weekly on today's weekday, 18:00–19:00, presence tracked, three past weeks marked present and one missed |
| calendarGuideDemoEventRent | Rent | Miete | Chirie | monthly on the 1st, all day |
| calendarGuideDemoEventBirthday | Mum's birthday | Mamas Geburtstag | Ziua mamei | yearly, start 1964-05-12, count from 0 (so the row reads the age) |
| calendarGuideDemoEventBookClub | Book club | Lesekreis | Clubul de lectură | every 2 weeks on Thursday, 19:00 |
| calendarGuideDemoEventFlight | Flight | Flug | Zbor | one-time, today + 9, all day, with a description |
| calendarGuideDemoEventFlightNote | Gate opens two hours before. | Das Gate öffnet zwei Stunden vorher. | Poarta se deschide cu două ore înainte. | the Flight's description |
