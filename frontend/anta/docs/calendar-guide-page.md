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
- §7 The hands-on rework: §7.0 the horizon fix · §7.1 decisions D13–D37
  (D21–D37 the designer's defaults, under §7.2's spec) and the structure
  (the status line lives there) · §7.2 slice specs ·
  §7.3 how to run this (the next session's prompt) · §7.4 the proposal
  the letters answered · §7.5 the coach rework (D40–D48: the coach line,
  the practice tour, the prose cut; its own status line)
  · §7.6 the owner's second review of 2026-10-30 (D53–D65: two practice
  lessons, the screen page's real views, the fasting page; slices F1–F4;
  its own status line)
- §8 The strings: the rework's content spec, en / de / ro · §8.3 the coach
  rework's strings
  · §8.4 the second review's strings (the lessons, the screen cards, the
  fasting page)
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

### 7.1 The rework — status: IN PROGRESS — slice 0 built and reviewed 2026-10-29 (eight seams; the review found nothing on persisted data, 16 items, nine closed in a fix pass — the review note under §7.2's slice 0); the designer's spec and D21–D37 taken 2026-10-29; slice 1 built and reviewed 2026-10-29 (1a every §8 string, 1b the hub, the nine topic pages, the search; 15 review items, ten closed; gate green, suite +10848 ~10 −1); slice 2 (the practice calendar page) built and reviewed 2026-10-29 (24 items, none a write; 14 closed — read seams on the shared widgets; gate green, suite +10888 ~10 −1); slices 1–2 COMMITTED by the owner as `21a90993` (which also swept in slice 3a's files mid-run); slice 3a (the card frame; the screen, events, kinds and alerts cards) built 2026-10-29 (gate green, suite +10937 ~10 −1); slice 3b (attendance, categories, finding, setup) built 2026-10-29 (gate green, suite +10985 ~10 −1); slice 3 reviewed and fixed 2026-10-29 (19 items, none a write; eleven closed) and COMMITTED by the owner as `841f695a`; slice 4 done 2026-10-29 — the `design-reviewer` (18 findings, the seven severity-2 ones closed, D38 / D39 taken), `qa pass alerts` 5 / 5, `qa pass calendar` 27 / 27 after the flow fix, the skills and the feature doc updated; gate green, suite +11032 ~10 −1 — **IMPLEMENTED 2026-10-29, slice 4 uncommitted** (the design fixes, D38 / D39, the flow, this record); **the coach rework of §7.5 (D40–D52) IMPLEMENTED 2026-10-30, uncommitted — its status line is §7.5's**

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
  **As built (2026-10-29, two `implementer` runs):** 1a landed every §8
  string first (112 keys per ARB, after `calendarGuideNotesBody`, in the
  record's order; the D25 and D32 amendments; `calendarGuideStartHere`
  and `calendarGuideHowItWorks`; the three changed values; the page's
  three calls re-pointed — `calendarGuideIntro(tryIt)`,
  `calendarGuideOpeningBody(calendar, title)`,
  `calendarGuidePermissionsBody(battery, permissions)`;
  `reminder_word_test` extended; `railAuto/Always/Never` ←
  `eventShowInDayRailAuto/Always/Never`, `other` ← `eventCategoryOther`,
  `categoryAlerts` ← `eventCategoryAlerts`, `delete` ← `delete`). 1b:
  `GuideMetrics` (`lib/constants/guide_metrics.dart`: the paragraph
  numbers hoisted, `headingInset` 16, `headingGap` 8, `hubRowPadding`,
  `hubGlyphSize` 24, `hubTitleGap` 16 — the tile and the glyph measurement
  read the same constants); the content catalogue
  `lib/models/calendar_guide_content.dart` (`CalendarGuideRow`,
  `CalendarGuideTopic` — slug, glyph, title, caption, lead, rows, a null
  `demo` seam for slice 3); `lib/widgets/calendar_guide_rows.dart`
  (`CalendarGuideReadRow`, the old `_GuideRow` unchanged,
  `calendarGuideParagraphStyle`, `calendarGuideReadEntry`);
  `lib/pages/calendar_guide_topic_page.dart`; the hub rewritten (the
  glyph rule cached per width / scale / locale / density, measured with
  the practice title; search sections per page with the page row first);
  ids `calendarGuidePage(slug)` / `calendarGuideTopic(slug)`; the row id
  `calendar-guide-categories` retired with its pair; icons by grep — rail
  `vertical_split_rounded` (the appearance page's), assume the fallback
  `event_busy_outlined` (the editor's is a chip), priority
  `flag_outlined`. Suites: `calendar_guide_page_test` 16 cases,
  `calendar_guide_topic_page_test` 25; gate green, suite +10844 ~10 −1.
  **Reviewed 2026-10-29** (one `reviewer`, 15 items, nothing on persisted
  data; ten closed by one `implementer`, gate green, suite +10848 ~10 −1):
  the search over-matched — the kit shows a whole section when the query
  hits its title, so en "delete" listed every events row — and the hub now
  keeps only the rows `matchSettingsEntry` matches (the page row first,
  the kept rows as its keywords); `26_guide.txt` scrolls to the hub row
  before tapping it; five sentences retyped labels against D5 and now
  quote them (`calendarGuideCountBody` `{day1}` / `{day2}` / `{week3}` /
  `{year1}` / `{year2}` ← `eventNumberedDays(n)` / `eventNumberedWeeks(3)`
  / `eventElapsedYears(n)`; `calendarGuideAssumeBody`,
  `calendarGuidePageAttendanceCaption`, `calendarGuideTryAttendance`
  `{present}` / `{missed}`; `calendarGuidePriorityTitle` `{priority}` —
  §8's text is superseded by the ARBs there); four `@` descriptions
  corrected; German: "zeigt sie", "ihre Ereignisse" ×2, "So geht’s"; the
  glyph measurement's style is `GuideMetrics.hubTitleFontSize` /
  `hubTitleFontWeight`, held to the kit's title by a test; the catalogue's
  rows build once per locale; the four unused section keys retired with
  their `reminder_word_test` line; tests for the plain push, the card
  membership and order, the search at de 2.0, the D37 pin. Left as found:
  `CalendarGuideReadRow`'s 16 / 12 / 4; the id on the kit's container
  wrapper (every kit row); the pre-existing collision of the row slug
  `open` with the ⋮ row's id `calendar-guide-open` (never one screen; the
  slugs are frozen); the new Dart files are LF in the working copy
  (autocrlf normalises the commit). **Note for the commit:** the intro
  promises a "Try it" corner on every page, which exists only from slice
  3 — slices 1–3 ship together.
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
  **As built (2026-10-29, one `implementer`):**
  `lib/models/calendar_guide_demo.dart` (`GuideDemoCalendar` — the six
  events, the demo's own presence map, skips and per-day descriptions, the
  picked and focused day, format, panel mode, filters; the per-day map over
  the focused month ± 1 plus a week each side, rebuilt on event / skip /
  filter changes and page turns, `eventsFor` a lookup; `upcoming()` 35
  days, memoized; `reset`, `isDirty`) and
  `lib/pages/calendar_guide_practice_page.dart` (settings read once behind
  a spinner gate; the bar, the band, the grid, the panel, the add button;
  the editor / detail / description / dates / filter / menu / template
  paths); `calendarGuidePracticeIcon` / `Slug` in the catalogue; the band
  numbers and `captionTitleMaxChars` in `GuideMetrics` plus
  `practiceHeaderInset` 4, `practiceChevronPadding` 8,
  `practiceMarkerInset` 4 (the real grid's `AppSpacing` and a literal,
  both off-limits here); ids `calendar-guide-practice`,
  `calendar-guide-practice-banner`, `practice-reset`,
  `practice-filter-open`, `practice-more`, `practice-add-event`, the hub
  row `calendar-guide-page-practice`; an optional `identifier` on
  `CalendarAddFab` and `CalendarOverflowMenu` (defaults unchanged). The
  demo grid's header is a plain centred month title (no Today button, no
  month picker — swipe only). Where a shared widget reads a static cache
  the demo cannot feed: the grid bars and the timeline fade read
  `EventPresence` (a missed demo day draws at full strength), the detail
  sheet's chips open "present" on the missed Yoga day and its Skip row
  reads `EventSkips` (always offered), the editor's skip picker starts
  empty; the day panel, Upcoming and "Missed only" take the demo's facts
  explicitly. Captions beyond the table: the template picker's Quick alarm
  row → `calendarGuideWouldOpen(quickAlarmTitle)`; Add date / All dates →
  `calendarGuideDemoChanged`; presence taps say nothing (no string); the
  format choice does not dirty Start over. `PanelModeBar` keeps its expand
  toggle (`expanded: false`, a no-op). Suite:
  `calendar_guide_practice_page_test` (20 cases, a robot, a statement
  interceptor on the in-memory database every calendar service and
  `SettingsService` are bound to — zero statements after each case; the
  matrix with the SDK's real Roboto through
  `test/goldens/support/golden_fonts.dart`, the test font's one-em glyphs
  having pushed the band to 322 dp). Gate green, suite +10868 ~10 −1.
  Pre-existing, noticed: `DayTimelineView` overflows inside its blocks at
  text scale 2.0 (`day_timeline_view.dart:366`).
  **Reviewed 2026-10-29** (one `reviewer`, 24 items, none a write; 14
  closed by one `implementer`, gate green, suite +10888 ~10 −1). The
  lesson: a sandboxed widget that reads a **static cache by event id** lies
  for a demo id, so the fix is a **read seam** whose default is today's
  static read — `isMissed` (`bool Function(CalendarEvent, DateTime dayUtc)`,
  default `EventPresence.isMissed`) on `DayBarsResolver.defaults` (threaded
  to `EventDayBarProvider`), `DayTimelineView` (a reader skips its layout
  memo — no revision tracks the demo's marks), `EventDetailSheet.show` and
  `PresenceAdherence.compute`; `EventEditorSheet.show(initialSkippedDays:,
  initialAlerts:)` (default the facades); `CalendarViewMenu(namesRoute:)`
  (null keeps the per-platform choice); `PanelModeBar.onToggleExpanded`
  nullable (null draws the button disabled). With them the missed Yoga
  week fades in the grid and the timeline, the detail sheet opens "Missed"
  with 4/5 from the demo's marks, a demo skip survives the editor's
  picker, an alert added in the practice editor survives a reopen. Also:
  the detail sheet's callbacks update the demo without `setState` (its
  dispose flushes a task tick inside `finalizeTree`'s lock) and the page
  rebuilds at the end of the frame; per-day descriptions reach the day
  panel and `pendingOccurrenceDescription` is gated on `appliesTo`;
  presence taps caption `eventAdherenceSummary` from the demo's marks;
  `isDirty` compares with the seed (Apply unchanged, add-then-delete,
  mark-then-unmark stay disabled); the seed waits for
  `CategoryService.getInstance()` (the static facade is empty before the
  calendar's bloc loads); the bars are memoized per day; added events
  carry the `guide-demo-` prefix; the hub search finds the Practice row.
  The suite binds all nine services and `SettingsService` to one
  intercepted database (`PublicHolidayService.forTesting` and
  `MarkdownBarService.forTesting` added — `getInstance` delegates to a
  private `_create`), checks `CalendarTemplates` / `PublicHolidays` and
  empty `SharedPreferences`, 38 cases. Left as found: the detail sheet's
  Next row and stats go through `occursOnUtcDay`, which reads the static
  `EventSkips` and so ignores demo skips (a third seam, not taken); the
  plain month title; the `practice*` metrics copying the real grid's
  values; demo events listing the owner's category alerts (read-only).
  **For the `design-reviewer`:** at de 2.0 on 360 × 780 the month grid
  leaves no room for the panel and the Day panel's presence button sits
  under the add button. (The `design-reviewer` measured it: the band,
  oversized by its 'W' stand-in, pushed the button to y 800, below the
  screen; the real page has no band and would show it at about y 619 —
  not the real calendar's geometry. Fixed in slice 4's design fix pass.)
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
  **As built, 3a (2026-10-29, one `implementer`, resumed once past its
  turn cap):** the frame `lib/widgets/calendar_guide_try_card.dart` — an
  abstract `GuideCardDemo` (the stage, the caption, the candidates, the
  appearance and a `needsAppearance` flag), `calendarGuideTrySection`, the
  stateless `CalendarGuideTryCard`, the shared `calendarGuideQuote` /
  `calendarGuideLongestQuote` / `calendarGuideLongestDate` (the practice
  page's private `_quote` moved there); the topic page is stateful and
  owns and disposes the demo (the kit's list disposes a card scrolled
  away), draws the card first, computes the candidates once per locale and
  reads `getCalendarPageSettings()` once for a demo that needs it; the
  catalogue's `demo` seam became `tryLead(l10n)` (the lead-in per page,
  null for Good to know) and the demo factory lives in the page (a factory
  in the card file would cycle the imports); `GuideMetrics.cardInset`,
  `leadToStage`, `stageToCaption`, `stageRadius`, `stagePadding`,
  `stageOutline`, `stageMatrixScale` 2; ids `calendarGuideTry(slug)`,
  `calendarGuideTryCaption(slug)`, `calendarGuideTryControl(slug, c)`
  (`try-<slug>-<c>`). The four demos
  `lib/widgets/calendar_guide_try_screen.dart` / `_events` / `_kinds` /
  `_alerts`: screen — the real `CalendarViewMenu` (its own
  `calendar-view-menu` id), `CalendarOverflowMenu` (`try-screen-more`) and
  `PanelModeBar` (expand disabled); events — three seed rows
  (`try-events-row-<id>`), the real detail sheet (read-only, no
  callbacks: Skip kept in the demo, the quick description, note and dates
  actions just close it), the sandboxed editor, `CalendarAddFab`
  (`try-events-add`) and the template picker; the stage height is fixed by
  an unseen copy of the three seed rows plus `fabClearance`, the rows
  scroll inside it and a fourth added row drops the oldest added one;
  alerts — the real `AlertEditorSheet` (add, edit, Remove — removal
  captions `calendarGuideDemoChanged`, no string of its own),
  `AlarmPage.preview` pushed on its own page route with a payload built as
  the scheduler builds one through `AlertLabels`, `QuickAlarmSheet`
  (`quickAlarmSetOn` for another day, as the calendar does) and the real
  Permissions page (`try-alerts-add` / `-alert-<i>` / `-show-alarm` /
  `-quick` / `-permissions`); kinds — the real `EventRepeatSheet`,
  `pickMulti` and `pickSingle`, and `MonthDotMatrix` at twice its size
  with a Date row through the single-day picker, this month only
  (`try-kinds-repeat` / `-add-date` / `-day` / `-skip`) — the overview's
  `AgendaMonthGrid` clipped its 24 px weekday row at 2.0 ("Mo" wraps at
  360), which the real overview may share. Static reads: the rows read
  `CalendarCategories`, the template picker `CalendarTemplates`,
  `occursOnUtcDay` the empty `EventSkips`. Suite:
  `calendar_guide_try_cards_test` (49 cases, `GuideTryCardRobot`, the
  practice suite's write log moved to `support/sandbox_write_log.dart` and
  shared; the topic suite binds `SettingsService` and loads the real
  fonts — the test font's one-em glyphs overran the ro Repeat value's two
  lines). Gate green, suite +10937 ~10 −1. The hub does not search the
  lead-ins (3b adds them as keywords on the page row).
  **As built, 3b (2026-10-29, one `implementer`):**
  `lib/widgets/calendar_guide_try_attendance.dart` (the practice seed's
  Yoga with its marks through `GuideDemoCalendar` and its `isMissed`
  reader, `PresenceAdherence.compute`; today's row with the day panel's
  presence button as a `FormTrailingButton` — the picker row's only
  trailing type, `outline` instead of the IconButton default; four
  past-week chips; the count switch with both style chips always drawn
  and disabled while off — appearing on toggle would move the caption —
  and the editor's example caption in a slot; ids `today`, `day-0…3`,
  `count`, `count-numbered` / `-elapsed`), `_try_categories.dart` (two
  visible built-ins — `builtInSeeds` when the cache is empty — and one
  custom demo category named after the Book club; eye and ⋮ per row, the
  menu a `showMenu` + `PopupMenuItem(enabled:)` as the saved-filters ⋮
  because `showFormMenu`'s items cannot be disabled, the ⋮ tooltip
  Material's; no "Built-in" line — it broke mid-word beside two buttons at
  2.0 on 360, a built-in shows by its disabled Delete; the list sized for
  three rows, extra rows scroll, Create disabled at six; ids `row-<i>`,
  `eye-<i>`, `more-<i>`, `edit` / `delete`, `add`), `_try_finding.dart`
  (`FormSearchRow` with the hint `search` — `upcomingSearchHint` cut off at
  2.0 inside the stage; `EventSearchQuery.parse` + `EventQueryMatcher`
  over the six seeds from the 1st of this month to a year ahead so the
  birthday counts and the idle "6" is the real count; the funnel as a
  `FormActionRow` whose glyph fills when a filter is on (no badge on an
  action row), Missed only through the demo's `isMissed`;
  `MonthDotMatrix` at 2×; ids `search`, `match-<key>`, `filter`),
  `_try_setup.dart` (`FormMenuRow` of every holiday set, the row's height
  held by a slot over every set; the next three holidays in a slot whose
  candidates are every set's own three lines; a `SegmentedButton` with
  the copied `_choiceWordsFit` rule turning `CalendarAppearancePreview`,
  clamped at `GuideMetrics.sampleWeekMaxTextScale` 1.2 — a day column is
  36.3 dp on 360 and "dum." needs 37.6 at 1.3; the current profile read
  once from `PublicHolidayService.getInstance().profile` by the topic
  page; ids `holidays`, `holidays-<profile>`, `week-monday` / `-saturday`
  / `-sunday`, `settings`); the hub's page rows take `tryLead` as a
  keyword. Gate green, suite +10985 ~10 −1. Noticed, pre-existing: the
  overview's `upcomingSearchHint` is probably cut off at 2.0 on narrow
  phones too.
  **Reviewed 2026-10-29** (one `reviewer` over 3a + 3b, resumed once past
  its turn cap, 19 items, none a write; eleven closed by one
  `implementer`, gate green, suite +11000 ~10 −1): the setup card merged
  both years' holiday maps into one set of distinct dates and counts only
  the shown year — `HolidaySeeds.forYear(unitedStates, 2028)` holds
  2027-12-31 (a Saturday 1 January observed the year before) and
  `forYear(2027)` holds it too, so on 2027-12-26 the next-three list named
  one holiday twice and the 2028 count took a 2027 day (the seeds keep that
  behaviour; the card merges); every demo with a clock takes `now`
  (default `DateTime.now`, threaded from the page, handed to
  `QuickAlarmSheet.show(now:)` too); the events card handles the detail
  sheet's Add date, Dates and description edit as the practice page does
  (they had closed the sheet silently — the sheet shows Add date for a
  one-time event and the description cell for every event); the alerts
  stage is sized by an unseen copy at `kMaxAlertsPerEvent` with the rows
  scrolling inside (it had grown 135 dp per alert at de 2.0: 557 → 1232;
  now 1232 throughout — **taller than a 780 screen, for the
  `design-reviewer` to cap**) and the kinds card's title, Repeat and Date
  rows sit in slots sized over every rule's widest words and the widest
  short date (640 → 906 before; 906 throughout); the alarm preview's
  payload carries `removeAfterAlert`; the kinds card keeps the repeat
  sheet's last answer and reopens on it after "does not repeat" (as the
  editor keeps its draft within a session); per-build work removed — a
  per-locale `GuideLocaleFormat` cache in the card file, the rule words,
  dot masks and slot sizes memoized, setup's counts, next-holiday lines,
  weekday labels and word-fit memoized, attendance's count until a mark
  changes, finding's match list and month mask on (query, filters,
  locale); the topic page applies the look before the holiday read, each
  in its own `try`; `PublicHolidayService._create` has an in-flight guard
  (`reset()` clears it; `test/services/public_holiday_service_test.dart`);
  finding's gap is `RowMetrics.groupGap` and `CalendarGridFilters.axisCount`
  is named once with a test; the `calendarGuideTryControl` doc says the
  title menu keeps its own ids. Tests: the keyboard case asserts the
  field's bottom above the inset; the semantics-node group covers every
  card; Missed only through the demo's marks; setup from a Romania
  profile; Save returns to the detail sheet; the 2.0 matrix renders one
  changed state per card; "a stage never changes height at text scale
  2.0". Left as found, by decision: the caption stand-ins by character
  count (`'W' × 24`, the longest date by length); seed titles under a
  live locale change; the longest weekly rule ellipsized in the Repeat
  row at de 2.0 (the editor's row cuts it the same way). The fix pass ran
  `dart format lib` by mistake and restored the 44 untouched files from
  HEAD with CRLF after matching their token streams; `git status` shows
  only the slice's files.
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
  **As run (2026-10-29):** `26_guide.txt` extended by the lead (the hub →
  the practice page: `{{longdate+1}}` picked, + → the sandboxed editor →
  "Dentist check" saved and found in the panel → `{{longdate+7}}` and the
  seeded `event-row-guide-demo-yoga` into its detail sheet → the funnel →
  the ⋮'s guide row captioning → back → the Events page's card by id →
  back to the calendar; `expect` is not linted, so a typed title needs no
  `_labels.txt` entry); the two skills and the feature doc updated (the
  `calendar-events` reading map, the hub rule, the file map; the
  `calendar-ui` ids and device-pass lines; the feature doc's addendum);
  `rules/calendar.md` keeps 27 flows.
  **The `design-reviewer` (2026-10-29, real Roboto, en / de / ro, 1.0 /
  1.3 / 2.0, both themes, 360 and 412; its renders in that session's
  scratchpad):** the structure, the numbers, the contrast and the
  semantics match the spec — the hub's two cards and rows, the glyph drop
  (off at ≤ 368 dp, on at ≥ 372 at de 2.0), the live query, the heading,
  the card first as a container node, the stage, the live caption, the
  practice bar, Start over's 38 %, the band's 1.5 clamp, the route name;
  every token contrast as measured by the designer. Eighteen findings;
  the severity-2 ones and what one `implementer` did: (F1) the stage's
  rows broke words mid-word at de 2.0 and de 1.3 and en 2.0 on 360 — the
  list padding, `cardInset` and `stagePadding` leave them ~270 dp where
  the real sheets are full width — so from `GuideMetrics.
  stageFullBleedTextScale` 1.3 **inclusive** the stage runs edge to edge
  inside the card (a hairline top and bottom, no radius — D29's
  alternative), with a word-break check in the suite (every
  `RenderParagraph`'s word boxes, every card, idle and changed; two de 2.0
  words no edge-to-edge stage can hold are pinned as `unavoidable`:
  attendance's "Wiederholungen" beside its switch — the editor's sheet
  gives the label 32 dp more — and setup's „Kalendereinstellungen“ öffnen
  in a 256 dp row); (F2) the alerts stage reserved five rows — 1232 dp at
  de 2.0 on 360 with ~675 dp of empty ground — so the demo caps at
  `GuideMetrics.demoAlertCap` 2 (Add disabled at two, Remove re-enables;
  707 dp at de 2.0); (F3) the band's whole node was the live region
  (TalkBack would re-read "Nothing here is saved." on every caption) —
  line 2 is now `Semantics(container: true, liveRegion: true)` alone;
  (F4 / F9) the band is 90 / 134 / 181 dp (de) against the spec's 72 /
  111 / 127 and the card slots run over the spec — the stand-in became
  `'n' × 24` but nothing moved: the German **Skipped** caption with the
  long weekday-date is three lines at 1.0 and sizes the band, the events
  slot the Added caption — see D38; (F5) the finding card's count and
  month sat under the keyboard — on focus gain, once the inset settles
  (read from `View`, the Scaffold strips it from the body), the card
  scrolls toward the caption but never past the field (a plain
  `ensureVisible` hid the field and the caret tracking scrolled back) —
  on 412 × 915 the field and the matches sit above a 320 dp keyboard,
  the count cannot; (F6) the attendance chips said "Oct 1, selected" —
  each now carries `eventPresencePresent` / `eventPresenceMissed` as its
  hint; (F7) the practice header's chevrons were the real page's 40 × 40
  unlabeled ones — 48 dp with tooltips, the month title a plain text
  node (the real page's header is an app-wide decision, §6). Also: the
  kinds and finding matrix fits the stage (`CalendarGuideStageMatrix`,
  `stageMatrixMinScale` 2 … `stageMatrixMaxScale` 4); setup's week choice
  takes the short weekday names; the `stageRadius` comment corrected (the
  stage is a sunken patch in dark only — 1.00:1 against the card in
  light, the line the only edge). Gate green, suite +11032 ~10 −1. The
  rest is in §6 Deferred.
  **The device pass (2026-10-29, `qa-runner`, `anta_qa_1` on
  `emulator-5556`, the QA build of `841f695a` plus the tree):** `qa pass
  alerts` 5 / 5 green; `qa pass calendar` 26 / 27 on the first run —
  `26_guide` red at its step 18 on both runs, the lead's own date
  arithmetic (`{{longdate+7}}` lay on the next month's page: 2026-10-29
  sits in the last week of a five-row month), fixed to `{{longdate}}`
  (today, where the seeded weekly Yoga occurs) and re-run after a rebuild
  of the final tree: **green on the first run** (its six shots show the
  practice page with today's Yoga and Book club, the Added caption with
  the D38 date "Fri, Oct 30", the Yoga detail sheet reading 4 / 5 attended
  from the demo's marks, the filter sheet, the ⋮'s guide caption, the
  Events card with its mini list and +); `qa errors` clean after each
  suite; the device left quiet, no alarm armed. The
  accessibility dump of the practice page at de 2.0 dark: the route is
  named "Übungskalender" (`calendar-guide-practice`), the band's second
  line is its own node under the band and updates after a save (the
  harness prints no live-region flag), the chevrons read "Voriger Monat"
  / "Nächster Monat", "Von vorn" is disabled at idle; the bar titles fit
  on one line at 2.0 on the hub, a topic page and the practice page; the
  alerts card is unclipped at de 2.0; the hub's rows wrap to three lines
  at de 2.0. TalkBack's spoken phrasing and the real keyboard's settling
  stay unverified (device-only, by ear).

**The designer's brief (before slice 1):** the look of three things, one
mock — the hub row (title, caption, chevron on the kit), the "Try it" card
(the label in the section-label role, the lead-in as a caption, the stage,
the live caption; how it sits between read rows without reading as a
button), and the practice page's banner and bar (the banner's one line,
its ground, the bar at `AppBarMetrics`). Render the current hub and a kit
page with real fonts first; return the spec with its defaults lettered;
the owner answers before slice 1 builds.

**The designer's spec (2026-10-29; one mock,
https://claude.ai/artifact/ELx7HcgB9Tn2zKd35jAdDv; the renders and their
`measure.txt` lived in that session's scratchpad):**

- **Numbers** in a new `lib/constants/guide_metrics.dart` → `GuideMetrics`
  (the `AlarmMetrics` precedent — a surface's own numbers, which
  `FormMetrics` should not grow for one page; §2's "no new number" held for
  a page of read rows): `paragraphFontSize` 14 and `paragraphLineHeight`
  1.4 (hoisted from the page's private style), `cardInset` 16,
  `leadToStage` 12, `stageToCaption` 8, `stageRadius` 12, `stagePadding`
  12, `captionTitleMaxChars` 24, `bannerVerticalPadding` 8,
  `bannerGlyphSize` 20, `bannerGap` 12, `bannerMaxTextScale` 1.5.
- **The hub.** The kit `header:` carries the intro (its first two
  sentences, D25). Two cards: "Start here" (chip `flag_rounded`,
  `calendarGuideStartHere`) — Practice calendar, The calendar screen, Good
  to know; "How do I…" (chip `help_outline_rounded`, `calendarGuideHowDoI`)
  — the seven task rows. A hub row is a `ListTile` inside
  `SettingsEntry.builder`, as Calendar settings' navigating rows: leading
  24 `primary` page glyph (`ExcludeSemantics`), title the kit's 14 / 500
  `onSurface`, caption the kit's 12 `onSurfaceVariant` wrapping freely,
  trailing `chevron_right_rounded` 24 `onSurfaceVariant`, ink, `onTap`
  pushes; `SettingsEntry.identifier` = `SemanticsIds.calendarGuidePage
  (slug)` (`calendar-guide-page-<topic>`), one merged button node. The
  glyph rule: when the longest word of any hub title plus the 40 dp glyph
  column does not fit the title column (de "Übungskalender" at 2.0 on
  360), every hub row drops its glyph together — measured as
  `_choiceWordsFit` in `settings_page.dart` does, cached per width / text
  scaler / locale. Page glyphs: practice `touch_app_rounded`, screen
  `calendar_month_rounded`, events `event_rounded`, kinds
  `event_repeat_rounded`, alerts `notifications_active_rounded`,
  attendance `how_to_reg_rounded`, categories `category_rounded`, finding
  `search_rounded`, setup `tune_rounded`, good `info_outline_rounded`; the
  same glyph is the chip of that page's section in a search result.
- **A task page.** `SettingsAppBar(title: calendarGuideTitle)` — the bar
  names the guide, because the German page titles do not fit a bar (D26).
  The kit `header:` holds the page title (`FormMetrics.titleFontSize` 20 /
  `titleLineHeight` 1.3 / w500 `onSurface`, wrapping freely, 16 sides, 8
  below, `Semantics(header: true, headingLevel: 1)`), then the lead in the
  paragraph style. The first card is "Try it" (slice 3; chip
  `touch_app_rounded`, title `calendarGuideTryIt`; one `SettingsEntry`
  whose title is the lead-in — so it is searchable — and whose builder
  draws the body: the lead-in in the paragraph style, `leadToStage`, the
  stage, `stageToCaption`, the caption slot; no ink, no chevron, no tap on
  the card; the entry is a container node `calendar-guide-try-<topic>`,
  never merged, so the stage's controls stay separate nodes). The second
  card is "How it works" (chip = the page glyph, title
  `calendarGuideHowItWorks`) with today's `_GuideRow`s unchanged (D4, D7).
  The stage: `RepaintBoundary` › a `pageGround` fill under a 1 dp
  `outlineVariant` line, `stageRadius`, `stagePadding`; the widgets inside
  keep their own grounds (a `FormRowGroup` is `rowGroup` on it). The live
  caption: a `FormCaptionSlot` whose candidates are every string the card
  can show (the longest fixed demo title; typed titles cut to
  `captionTitleMaxChars` with "…", a 24-character stand-in among the
  candidates), child `FormCaption` 13 / 18 `onSurfaceVariant` with no
  `maxLines`, under `Semantics(liveRegion: true)`, id
  `calendar-guide-try-<topic>-caption`; never empty where the card has a
  resting state (D30).
- **The practice page.** An `AppBar` as `calendar_page.dart:949`
  (`AppBarMetrics`, `surface`, `scrolledUnderElevation` 0,
  `CalendarViewMenu.titleSpacing`; leading back; title the real
  `CalendarViewMenu`; actions: Start over `restart_alt_rounded` in the
  saved-filters slot — tooltip `calendarGuideDemoReset`, id
  `practice-reset`, 38 % until the demo differs from its seed — the funnel
  with its badge, the real `CalendarOverflowMenu`). Under it a full-width
  `primaryContainer` band, no radius, no ink (`RowMetrics.groupInset`
  sides, `bannerVerticalPadding`; glyph `touch_app_rounded` at
  `bannerGlyphSize` `onPrimaryContainer`, then `bannerGap`; line 1
  `calendarGuidePracticeBanner` 14 / 500 / 20 `onPrimaryContainer`, never
  changes; line 2 a `FormCaptionSlot` 13 / 18 `onPrimaryContainer` under
  `liveRegion`, idle `calendarGuidePracticeIdle`, candidates every practice
  caption with `calendarGuideDemoAddedShort`), the band under
  `MediaQuery.withClampedTextScaling(maxScaleFactor: bannerMaxTextScale)`
  — Material's own `MaterialBanner` clamp; id
  `calendar-guide-practice-banner`; the body scopes and names its route
  `calendarGuidePagePractice` (override `CalendarViewMenu`'s `namesRoute`).
- **Measured (±1 dp):** a hub row 71 / 87 / 194–202 at 1.0 / 1.3 / 2.0
  (de 160 at 2.0 without the glyph; 236 with it and a broken word); the
  card 376 / 426 / 682 (en; the stage 170, 224 at 2.0); the caption slot
  54 / 69–92 / 180–216; the banner 72 / 111 / 127 (clamped); the panel left
  on 780 under a 336 grid 276 / 237 / 221. Contrast: caption on card 8.1
  light / 9.6 dark, `primary` glyph 5.6 / 9.6, banner text 13.3 / 7.2, the
  band against the bar 1.23 / 1.99 (the hue separates), the stage line
  1.48 / 1.74 (not a control).
- **The `design-reviewer` re-renders after the build:** the hub (en / de,
  1.0 / 1.3 / 2.0, both themes, 360 and 412; the glyph-drop threshold at
  de 2.0; a live query; a pressed row; the desktop focus ring); the events
  page idle and after "Added" in en and de 2.0, the slot height equal in
  both; the kinds page at de 2.0; the finding page with `viewInsets`; the
  practice page's captions (idle, `AddedShort`, `DemoPanelUpcoming`,
  `YouAreHere`) at 1.0 / 1.3 / 2.0 in de dark with the banner height
  pinned, Start over disabled and enabled. Device-only, for `qa
  screenshot`: the real grid at the AOSP 200 % curve, the TalkBack route
  name and live-region announcements, the bar title at 2.0 ("Kalen…" is
  the real calendar's own geometry). Out of scope, kit-wide (for
  `docs/ui-language-adoption-roadmap.md`): the `SettingsSearchField` hint
  clips at de 2.0; the kit's dividers run the full width.

**D21–D35 — the designer's defaults, taken as delegated in the unattended
session of 2026-10-29 (the recommended option stands; each reversible in
one line):** **D21** (A) the hub is two kit cards, "Start here" (Practice,
The calendar screen, Good to know) and "How do I…" (the seven task rows) —
alternative: Good to know last as a one-row card, as Calendar settings
does. **D22** (B) hub rows keep the page glyph and drop it on every row at
once when a title word cannot fit — alternative: no glyph. **D23** (C) the
Practice row is the first row of the first card, not set apart —
alternative: a `primaryContainer` card above. **D24** (D) hub captions at
the kit's 12 px wrap freely — alternative: two lines. **D25** (E) the
intro drops "You can come back here any time…", which joins the Good to
know "Opening the calendar" row — alternative: keep it (at 2.0 no row
shows on the first screen). **D26** (F) a task page's bar names the guide;
the page title is a 20 / 500 heading atop the list — alternative: the
title in the bar (cut in German at 1.0). **D27** (G) "Try it" is the first
card after the lead — alternative: the last. **D28** (H) the read rows sit
in a "How it works" card — alternative: the page title repeated. **D29**
(I) the stage is `pageGround` under a 1 dp `outlineVariant` line, radius
12, inset 12 — alternative: a full-bleed band. **D30** (J) the live
caption is never empty where the card has a resting state — screen
`calendarGuideDemoFormat(Month)`, events `calendarGuideDemoLongPressHint`,
kinds `calendarGuideDemoOneDay`, attendance the presence caption, finding
`calendarGuideDemoMatches(6)`, setup `calendarGuideDemoHolidays`; alerts
and categories keep an empty reserved slot until the first action —
alternative: an idle string for those two. **D31** (K) the banner is a
full-width `primaryContainer` band under a 1.5 text-scale clamp —
alternative: the record's `rowGroup` on `pageGround` (measured invisible
in dark, 1.09:1). **D32** (L) `calendarGuidePracticeBanner` is split into
"Nothing here is saved." and `calendarGuidePracticeIdle`, and
`calendarGuideDemoAddedShort` serves the practice page — alternative: one
banner key plus a caption slot (+36–81 dp). **D33** (M) Start over is a
bar action, disabled until something changed — alternative: a
`TextButton` in the banner. **D34** (N) the numbers live in
`GuideMetrics` — alternative: `FormMetrics`. **D35** (O) one glyph,
`touch_app_rounded`, marks "tap here, nothing is saved" on the Practice
row, the Try it chip and the banner — alternative: a glyph each. Two more
of the lead's: **D36** the §8.1 `priority` row, which table 4 omits,
lives on the events page after `description`; **D37** a live hub query
shows one kit section per page with a match — titled with the page's
name under its glyph, its first row the page's own navigating row, then
the matching read rows (title or body) — and hides the page list while
the query is live. After the design review (2026-10-29): **D38** the
practice band's captions spell their dates in the abbreviated
weekday-date (`DateFormat.MMMEd`), the cards keep the long form — the
German Skipped caption with the long date was three lines at 1.0 and
sized the band at 90 / 134 / 181 dp against the spec's 72 / 111 / 127,
pushing the Day panel's presence button below a 780 screen at de 2.0 on
360 in the month format; **D39**, taken only if D38 alone leaves that
button off screen: the band's text-scale clamp drops from 1.5 to 1.3
(the band is chrome; the one line that matters stays legible at 1.3).
Both landed (2026-10-29): the band is 72 / 134 / 134 dp (de 1.0 / 1.3 /
2.0; D38 alone 72 / 134 / 154; 72 / 111 / 111 since the coach rework's
one-clause lines, §7.5, which is the value the suite pins) and the presence button's bottom moved
836 → 813 → 793 — still 13 dp below a 780 screen at de 2.0 on 360 in the
month format. **Accepted as is:** the Day panel scrolls, so the row is
reached with one flick, the two-week and week formats show it outright,
and a lower clamp would cost the band's one line its legibility; at 1.3
a caption other than a dated one holds the slot at 134 (the spec said
111) — not traced.

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

### 7.5 The coach rework (2026-10-29, after the owner saw slice 4) — status: **IMPLEMENTED 2026-10-30, uncommitted** — C1 (D49), C2 and C3 (D50) built, reviewed and fixed; the design review and its fix pass (D51, D52); gate green (suite +11079 ~10 −1); `qa pass calendar` 27 / 27 (`26_guide` green again on the rebuilt APK), `qa errors` clean; the skills, the feature doc and this record updated

**Why.** The owner's critique of the shipped guide, 2026-10-29: (1) "When
you say try it in the calendar, how is the user supposed to know that she
has to click on the event in the bottom sheet to do something?" — every
live line in the guide reported what had just happened and never what to
do next: the events card rested on the long-press hint, the alerts and
categories cards on an empty slot (D30), the practice band answered a day
pick with a count, and a card's lead listed four actions in one sentence
without saying where any of them was; (2) "some documentation parts are
very long without showing something interactive … the idea is to not have
too much text" — after the one card a page ran 3–9 paragraphs of ~200
characters (kinds 9 rows / ~1,900 characters, alerts 7 / ~1,570, events
7 / ~1,400, attendance 5 / ~1,320, categories 6 / ~1,100), most of them
describing what the card above already lets her do, and the hub's intro
fills the first screen at de 2.0. The owner's register note: "sometimes
just saying: you can edit an event by tapping it in the bottom sheet
works." Of the four lettered pairs put to him the owner took the
recommended option of each ("seems like a good idea").

**Decisions.**

- **D40 (owner, A)** One coach line per card, above the stage, replacing
  both the card's lead and the caption under the stage. It names the next
  tap; the demo advances it when it sees the action; a skip control steps
  past a line; after the last step it reads a closing line. The slot keeps
  one fixed height over every line the card can show (alternative B: keep
  lead and caption and reword them).
- **D41 (owner, A)** "How it works" keeps only what no stage can show, at
  most four rows per page, two sentences per row; the rows the card walks
  are deleted (B: cut each body to its first sentence; C: a collapsed
  "More" row).
- **D42 (owner, A)** The practice band coaches a five-step tour, one line
  at a time; Start over restarts it (B: only the idle line changes).
- **D43 (owner, A)** The hub's intro is one line (B: keep it).
- **D44 (the owner's register)** A coach line is one or two short
  sentences that say *where* — "you can open an event by tapping it in
  the list below" — in "you can…" or imperative form; never a list of
  several actions; it quotes the app's labels through placeholders as
  every guide string does.
- **D45 (lead)** A page's lead stays (D25) but is one sentence of at most
  75 English characters.
- **D46 (lead)** The card's line after an action is "{report} {next}": the
  report clause of what just happened — the demo's existing captions, cut
  to one sentence — then the first instruction not yet done. The step
  machine is a *done set*, not a cursor: an action marks its own step done
  wherever it sits in the order, so a step she does early is not asked
  again, and the line always shows the first undone step. An action that
  is no step (a menu item that would open a page) changes only the report.
  A report belongs to the action that just happened: the next action
  replaces it or clears it.
- **D47 (lead)** The band shows one clause at a time, never a composed
  line: the tour's current instruction, or — only for an action with no
  visible result on the stage (the ⋮'s Alerts, Settings and Guide rows,
  the title menu's Overview, Export) — that action's report alone until
  the next action. The band's other reports (the picked day's count,
  Added, Changed, Deleted, Skipped, Template, the filters' count, the
  format, the panel modes, the presence marks) are retired: the stage
  shows them. Reason: the band is the one surface where a tall slot
  pushes the real panel off a 780 screen (D38 / D39), and a composed
  German line would have been three lines at 1.0.
- **D48 (lead)** The card's searchable line (the kit entry's title) is its
  first instruction, static per locale; the builder draws the live line
  in its place. The closing line and the skip tooltip are shared by every
  card and the band.

**The coach line — spec.**

- Inside the card, where the lead was: a `Row` of the slot (expanded) and
  the skip button, `crossAxisAlignment: start`; then `GuideMetrics.coachToStage`
  (the former `leadToStage`, 12) and the stage; no caption below;
  `stageToCaption` is retired. The slot is a `FormCaptionSlot(alignment:
  AlignmentDirectional.centerStart)` over `Text` in
  `calendarGuideParagraphStyle` in `onSurface` (the card's body text, not
  the caption role); its candidates are every instruction, the closing
  line, and every report composed with every instruction and with the
  closing line (`calendarGuideCoachAfter`), each report at its longest as
  the demo's `candidates` already list them. The live `Text` is a
  `Semantics(container: true, liveRegion: true)` node and keeps the id
  `calendarGuideTryCaption(slug)` (ids are never renamed).
- The skip: a `FormTrailingButton` (48 dp), glyph `skip_next_rounded`,
  tooltip `calendarGuideSkipStep`, id `calendarGuideTryControl(slug, 'skip')`,
  a `GuideMetrics.coachGap` (8) from the text; it marks the current step
  done and clears the report; **disabled, never hidden, once every step is
  done**.
- The machine lives once, `GuideCoach` in `lib/models/calendar_guide_coach.dart`:
  `GuideCoachStep(action, line)`; `steps` in order; `did(action,
  [report])`, `say(report)`, `skip()`, `reset()`; `current` (the first
  undone step or null), `finished`, `next(l10n)` (the current instruction
  or `calendarGuideCoachDone`), `report(l10n)`; `candidates(l10n, reports,
  {composed})`. `GuideCardDemo` owns one and exposes `steps`, `reports(l10n)`
  (its former `candidates`) and `line(l10n)` = `report == null ? next :
  after(report, next)`; the page's `didChangeDependencies` builds the
  candidates once per locale as today. The practice page owns one too
  (D47: `line` = `report ?? next`).

**Steps per card** (the strings in §8.3; the action names are the
machine's, the trigger is where the demo calls `did`).

| card | step | action | trigger |
|---|---|---|---|
| screen | 1 `calendarGuideCoachScreenTitle` | `title` | `_setFormat`, and `onPageSelected` (reports WouldOpen Overview) |
| | 2 `…ScreenMore` | `more` | any ⋮ row (reports WouldOpen / WouldShare / YouAreHere) |
| | 3 `…ScreenPanel` | `panel` | `_setMode` (reports the mode's caption) |
| events | 1 `…EventsAdd` | `added` | `_addEvent` saved (reports `calendarGuideDemoAddedShort`), a template picked (reports `…DemoTemplate`) |
| | 2 `…EventsOpen` | `opened` | the start of `_open` (no report) |
| | 3 `…EventsChange` | `changed` | `EventEditorSaved`, a description edit, a dates change (reports `…DemoChanged`) |
| | 4 `…EventsDelete` | `deleted` | `EventEditorDeleted` (reports `…DemoDeleted`); the detail sheet's Skip and the quick-alarm pick are `say` only |
| kinds | 1 `…KindsRepeat` | `repeat` | `_update` with a repeating rule (reports `…DemoRepeats`) |
| | 2 `…KindsSkip` | `skipped` | `_skip` (reports `…DemoSkipped`) |
| | 3 `…KindsOnce` | `once` | `_update` with `OneTimeRecurrence` (reports `…DemoOneDay`) |
| | 4 `…KindsAddDate` | `addDate` | `_update` with `SpecificDatesRecurrence` (reports `recurrenceSpecificDates`); `_pickDay` stays `changed()` |
| alerts | 1 `…AlertsAdd` | `alert` | `_saidAlert` after an add or an edit (reports `…DemoAlertSet`); a removal is `say(DemoChanged)` |
| | 2 `…AlertsShow` | `alarm` | `_showAlarm` when the page is pushed (no report); the quick alarm is `say(DemoHereOnly)`, Permissions nothing |
| attendance | 1 `…AttendanceMark` | `flipped` | `_flip` (reports the stats line the idle caption shows today) |
| | 2 `…AttendanceCount` | `counting` | the count switch turned on (reports the stats line); a style pick `changed()` |
| categories | 1 `…CategoriesCreate` | `created` | `_create` (reports `…DemoCatCreated`) |
| | 2 `…CategoriesHide` | `hidden` | `_toggleHidden` to hidden (reports `…DemoCatHidden`); back to shown and `_edit` are `say(DemoChanged)` |
| | 3 `…CategoriesDelete` | `deleted` | `_delete` (reports `…DemoCatDeleted`) |
| finding | 1 `…FindingSearch` | `query` | `_onQuery` with a non-empty query (reports `…DemoMatches`); an emptied field is `say` |
| | 2 `…FindingFilter` | `filtered` | `_openFilters` with `activeCount > 0` (reports `…DemoFiltered`); a cleared filter is `say` |
| setup | 1 `…SetupHolidays` | `holidays` | a holiday set picked (reports `…DemoHolidays`) |
| | 2 `…SetupWeek` | `week` | a week start picked (no report); the settings row nothing |

**The practice tour** (D42, D47; the band's line is the instruction, or
one of the five no-effect reports alone):

| step | action | trigger |
|---|---|---|
| 1 `calendarGuideTourPick` | `picked` | `onDaySelected` with at least one event on the day |
| 2 `…TourOpen` | `opened` | `_openEvent` (a panel row or a timeline block) |
| 3 `…TourEdit` | `changed` | `EventEditorSaved` from the detail sheet's Edit, a description edit, a dates change |
| 4 `…TourAdd` | `added` | the editor saved from +, a template picked |
| 5 `…TourFilter` | `filtered` | filters applied with `activeCount > 0` |
| — `…TourDone` | | every step done |

The band's skip is a `FormTrailingButton` at the row's end in
`onPrimaryContainer`, id `SemanticsIds.practiceSkip` (`practice-skip`),
tooltip `calendarGuideSkipStep`, disabled when the tour is done; the band
stays under its 1.3 clamp (D39). Start over resets the tour with the demo
and is enabled when the demo is dirty **or** a step is done. The idle
line is step 1; `calendarGuidePracticeIdle` and `calendarGuidePickedDay`
are retired.

**The prose — the keep list** (D41; the new bodies in §8.3; every other
row of the page is deleted from the catalogue, its keys retired):

| page | kept, in order | deleted |
|---|---|---|
| screen | `marks`, `views` | `month`, `panel` |
| events | `description`, `priority`, `unsaved`, `templates` | `add-event`, `time`, `open` |
| kinds | `kinds-one-change`, `kinds-tricky`, `kinds-birthday`, `kinds-only-repeat` (now also carries the untick fact of `skipped`) | `repeat`, `kinds-one`, `kinds-dates`, `kinds-only-one`, `skipped` |
| alerts | `alert-kinds`, `permissions`, `ring`, `open-often` | `add-alert`, `quick-alarm`, `hub` |
| attendance | `assume`, `rail`, `per-day` | `attendance`, `count` |
| categories | `category`, `cat-change`, `cat-alerts` | `cat-create`, `cat-hide`, `cat-delete` |
| finding | `filters`, `overview` | `search` |
| setup | `settings`, `language` | `holidays`, `week-start` |
| good | `opening`, `back`, `notes` (bodies cut) | — |

The `26_guide` flow's `calendar-guide-add-event` step moves to
`calendar-guide-templates`; the hub suite's "Speichern finds the de Add
row" moves to the `unsaved` row, which still quotes `save`.

**Must not change.** The eight sandbox seams and the read seams of §7.2;
the no-write rule and every suite's run over `sandbox_write_log.dart`;
each stage's controls and their ids; the id `calendar-guide-try-<slug>-caption`
(now the coach line's node); the hub's two cards and the practice row
first; the practice page's bar, grid, panel and the five no-effect
reports (the flow expects "That is this guide — you are already in it.");
`GuideMetrics` numbers other than `leadToStage` → `coachToStage`,
`stageToCaption` (retired) and `coachGap` (new); D38 / D39; every
persisted field (the guide persists nothing).

**Slices** (one `implementer` and one `reviewer` each, the gate after
each, sequential — the three slices share the ARBs and the flow, and
`flutter test` runs one at a time):

- **C1 — the coach line and the cards**: `GuideCoach`; the card frame
  (`calendar_guide_try_card.dart`: the row, the skip, no caption; the
  section's entry title = the first instruction); the eight demos' steps
  and `did` / `say` sites per the table; `GuideMetrics`; **every string of
  §8.3 except the bodies and the leads** (the coach lines, the tour lines,
  the frame strings, the shortened reports) in en / de / ro — added, not
  yet retiring anything the practice page still reads; `calendar_guide_try_cards_test.dart`
  moves from captions to lines and gains: idle = step 1 alone; the
  step's action composes report + next; an out-of-order action marks its
  step done; skip advances and is disabled at the end; the closing line;
  the slot's height constant across every line at de 2.0 (extend the
  stage-height group); the entry title is the first instruction.
- **C2 — the practice tour**: the page's `GuideCoach`, the band's skip,
  Start over's new enablement, the five `say`s, the retired band reports
  and their keys (`calendarGuidePracticeIdle`, `calendarGuidePickedDay`,
  `calendarGuideDemoAdded`, `calendarGuideDemoLongPressHint`);
  `practice-skip`; `calendar_guide_practice_page_test.dart` (idle = step 1;
  a day with events → step 2; a row → step 3; the five reports alone;
  skip; Start over after a skip; the band's heights re-measured); the
  flow gains `expect id:practice-skip` and `expect id:try-events-skip-step`.
- **C3 — the prose**: the catalogue's keep list; the bodies, the leads and
  the intro of §8.3 (en from the record; de / ro cut from the existing
  translations, re-translated only where the English changed, the ARB's
  vocabulary kept); the instruction trims of §8.3.2a (D50); the retired
  row keys; `calendarGuideIntro` loses its placeholder; `calendar_guide_page_test.dart` and
  `calendar_guide_topic_page_test.dart` (the catalogue test's table, the
  search cases, the Speichern case); the flow's row id.
- **The close**: one `design-reviewer` on the events card and the band
  (the slot's height at 1.0 / 1.3 / 2.0 in de, the skip's target and
  contrast, the band's height against D38 / D39), `qa pass calendar`,
  the skills' rule lines, the feature doc's addendum, this status line.

**Done means.** The gate; no demo writes; on every card the first thing
she reads says where to tap; no page carries more than four read rows;
the band is no taller than today at de 1.0 / 1.3 / 2.0; `26_guide` green.

**C1 as built (2026-10-29 evening; gate green, suite +11058 ~10 −1):**
`GuideCoach` in `lib/models/calendar_guide_coach.dart` (a done set;
`candidates(l10n, reports, {composed})` de-duplicated), the steps on
`CalendarGuideTopic.steps` (a getter of `GuideCoachStep`s whose lines take
the localizations, so a coach built before the page has a language
survives a language change; `tryLead` returns the first line), the frame
(the row, `coachToStage`, no caption), the eight demos' triggers exactly
as the table, every §8.3.1–8.3.4 string, `test/models/calendar_guide_coach_test.dart`
(9), the cards suite moved to the line and extended (idle = step 1 and
the entry title; skip through to the closing line, then disabled;
composed "report next" per card with out-of-order steps; the slot's
height through every line at de 2.0 on 360). The implementer's defaults,
taken: **(a)** the skip's id is `try-<slug>-skip-step` — `try-kinds-skip`
has been the kinds stage's "Skip this day" row since slice 3 and ids are
never renamed, so C2's flow line is `expect id:try-events-skip-step`;
**(b)** the de / ro entries carry no metadata blocks, as no guide key in
those two files does (gen-l10n reads the English metadata); **(c)** the
count switch turned off keeps the last report (`changed()`); **(d)** a
query counts as non-empty after trimming; **(e)** the finding card's
keyboard reveal now scrolls the line to the top with the field and the
first match under it (the line sits above the field; aligned to the
bottom, the matches stayed under the keyboard), its 412 × 915 / 412 × 1200
cases rewritten; **(f)** on a two-date event "does not repeat" keeps the
dates and reports as `addDate`. Known cost: the kinds card's slot lays
out about 380 hidden candidates (75 reports × 5 lines) once per locale.
Left for C2: `test/l10n/reminder_word_test.dart:77` lists
`calendarGuideTryAlerts` and goes with the key; two comments still say
"caption" (`SemanticsIds.calendarGuideTryCaption`, `calendarGuideQuote`).

**C1 reviewed (2026-10-29 evening; 11 findings, none a write).** The
machine, the triggers, the candidates' coverage (long titles never grow
the slot), the ids, the strings and the must-not-change list held. What
did not: **(1)** at de 2.0 on 360 the composed slot is 390–546 px tall
(kinds 546, categories 546, events 507; 80–140 at de 1.0) and every
stage sits below the first screen — the report × instruction
composition D46 asked for, on a column the skip narrows by 56 px;
**(2)** `centerStart` floats a short line up to 136 px below the skip;
**(3)** on 360 × 780 at de 2.0 the finding card's keyboard reveal leaves
the first match under the keyboard (the slot cannot fit, the early
return keeps the field's bottom-aligned scroll) and the keyboard tests
cover only 412 × 915 / 1200 in en 1.0; **(4)** `did` accepts a name that
is no step; **(5)** `did('alarm')` fires before the push, so the live
region can speak over the ring screen; **(6)** the C2 bullet above still
said `try-events-skip`. Accepted as found: kinds step 2 cannot be done
while the event is one-time (she skipped step 1 — the skip is the way
past it); the kinds slot's ~380 hidden candidates are rebuilt but never
re-laid out (`RenderParagraph` keeps an identical text's layout).

**D49 (lead, supersedes the composition of D46 and unifies the cards with
D47):** on a card as on the band, **the line is one clause**: the first
undone step's instruction, or, after an action that is no step and shows
nothing on the stage (`say`), that action's report alone until the next
action; `did` carries no report. Reason: the owner asked for less text,
and the composed line is what pushed the stage off the first screen at
2.0. The two results a stage could not show move into the stage, under
the control that makes them, in a `FormCaptionSlot` of their own: the
attendance card's stats line (the detail sheet's presence captions) as
the chip row's caption, the setup card's `calendarGuideDemoHolidays`
count under the holiday-set row. The `say` reports that remain on the
cards: the events card's detail-sheet Skip (`calendarGuideDemoSkipped`)
and its quick-alarm pick (`calendarGuideWouldOpen`), the alerts card's
quick alarm (`calendarGuideDemoHereOnly`); every other former report is
a visible change on the stage and becomes `changed()`. The slot's
candidates are the instructions, the closing line and those reports
(`composed: false`); `calendarGuideCoachAfter` is retired in the fix
pass. The slot aligns `topStart`, so the line sits under the skip and a
short line leaves its blank below. The categories card's third step
names where the events go (the §8.3.2 line gains ": its events move to
“{other}”", `{other}` ← `eventCategoryOther`, in the three languages).
With a one-clause slot the finding card's reveal keeps the line at the
top where it fits and otherwise falls back to the field at the top; a
360 × 780 de 2.0 keyboard case joins the suite. Keys the cards stop
reading (C2 retires what the band no longer reads either):
`calendarGuideDemoAddedShort`, `…DemoChanged`, `…DemoDeleted`,
`…DemoTemplate`, `…DemoFormat`, `…DemoPanelDay` / `Timeline` / `Upcoming`,
`…DemoFiltered`, `…DemoMatches`, `…DemoRepeats`, `…DemoOneDay`,
`…DemoAlertSet`, `…DemoCatCreated`, `…DemoCatHidden`, `…DemoCatDeleted`,
`…DemoLongPressHint`, `…CoachAfter`.

**C1 fix pass as built (2026-10-29 evening; gate green, suite +11060 ~10
−1):** D49 in full — `GuideCoach.did(action)` takes no report and asserts
the action is a step, `line` = `report ?? next`, `candidates(l10n,
reports)` plain; the `say` reports left on the cards are the events
card's Skipped and WouldOpen(quick alarm) and the alerts card's HereOnly,
every other demo's `reports` is empty; the attendance stats are the chip
row's caption slot (sized on the 88 / 88 / 88 / 88 summary), the holiday
count a caption slot under the setup card's holiday-set row, both live
from the first build; the slot aligns `topStart`; the finding card's
reveal keeps the line at the top when the first match (or the field,
with no match) fits under it and otherwise puts the field at the top, a
360 × 780 de 2.0 keyboard case added; `did('alarm')` after the pushed
page returns; `SemanticsIds.calendarGuideTrySkip(slug)`; the categories
step 3 names "{other}". The slot at de 2.0 on 360 (232 wide): screen 195,
events 273, kinds 351, alerts 273, attendance 273, categories 312,
finding 312, setup 234 (390–546 before). Accepted: the screen card's ⋮
rows and the title menu's Overview advance their step and say nothing
(D49: no report on a `did`) — the opened menu is the demonstration;
`CalendarGuideStageMatrix`'s doc still says "the caption says". For C3:
the kinds slot is set by its own instructions' length — every
instruction is cut to about 70 English characters there, the trailing
"watch…" sentences going where the stage shows the result.

**C2 as built (2026-10-29 evening; gate green, suite +11064 ~10 −1):**
`GuideCoach(steps, {closing})` (the band's closing line is
`calendarGuideTourDone`, the cards' default `calendarGuideCoachDone`) and
`advanced`; `calendarGuideTourSteps` beside the practice slug in the
catalogue; the page owns the coach and a `ValueNotifier<int>` revision
(the `_caption` notifier is gone), `_reports` the six `say`s (Overview,
Alerts, Export, Guide, Settings, the template picker's quick alarm);
`picked` counts the grid's events (a holiday-only day does not count),
`opened` fires inside `_sheets.run` (a tap the guard drops does not
count); Skip, Delete, the format, the panel modes and the presence marks
only `setState`; the skip in the band is a `FormTrailingButton` with no
gap of its own (an 8 dp gap made the band 137 at de 1.3, above the 134
ceiling; the button's inset keeps the glyph off the text); Start over
enabled on `isDirty || advanced` and resetting both; `practice-skip`;
the 28 keys of §8.3.5's C2 list and D49's list retired from the three
ARBs (`calendarGuideCoachAfter` was never committed; no other reader
found in `lib/ test/ tool/`); the band at de on 360 is 72 / 111 / 111
(72 / 134 / 134 before). The suite's "added then deleted leaves Start
over disabled" became "enabled" (adding is a tour step) with the seed
comparison checked on a twin demo. Two comments left for C3: `SemanticsIds.calendarGuidePracticeBanner`
("the live caption"), the `26_guide` header ("only captions").

**C2 reviewed (2026-10-29 evening; 11 findings, none a write, the band
not taller).** Fixed in the C2 fix pass, on the band and the cards alike
since the machine is shared: **(1)** a `say` report outlived every
non-step action (a format pick, a panel mode, a presence press, a Skip,
a Delete, a cleared filter, an empty day) — now `GuideCoach.clearReport()`
runs from every non-step handler and from `GuideCardDemo.changed()`, so
the line holds "until the next action" as D47 / D49 say; **(2)** a skip
under a standing report marked an unseen step done — a skip now only
clears the report when one stands; **(3)** step changes fired while a
sheet was up (`opened` at the trip's start, `changed` under the editor),
where `ModalBarrier`'s `BlockSemantics` hides the live region — the trip
records its step actions and applies them when it returns, on the page
and on the events card (the C1 alarm finding's family); **(4)** the
band's skip glyph sat across the title and the line — the button now
takes a top inset that centres its glyph on the line's first row
(`titleLine − (button − captionLine) / 2`, never below 0, from the
scaled line heights), which adds no height; **(5)** the disabled skip
greyed in `onSurface` on `primaryContainer` — `FormTrailingButton` gains
`disabledColor` (its suite a case) and the band passes its ink at 38 %;
**(6)** `calendarGuideTourSteps` is `List.unmodifiable`; **(7)** one
`ValueListenableBuilder` round the band's row; **(8)** the suite asserts
the step after a timeline block, Blank saved and a template picked, that
Skip, the format and the panel do not move a later step, and a report
followed by a non-step action. Accepted: a day whose only bar is a
holiday's does not count as "a day with a bar" (its panel row is no
event to open; the seed puts events on most days of the week); the de
1.3 band's widest line sat 0.34 dp inside its column (D50's shorter
`calendarGuideTourEdit` removes it).

**C2 fix pass as built (2026-10-29 evening; gate green, suite +11075 ~10
−1):** all eight as the note says. Two details of its own: on the events
card the detail sheet's Skip settles the trip's deferred steps *before*
its `say`, so the Skipped report stands rather than being cleared by the
deferred `opened`; where `did('changed')` used to redraw the stage under
a sheet the card now notifies directly, so the stage updates under the
sheet and only the line waits for it to close. `FormTrailingButton.disabledColor`
is the one primitive change (its suite has the case); the band's skip
inset is about 5 dp at 1.0 and 13.7 at 1.3, the glyph is
`FormMetrics.trailingIconSize` (20). Device-only, unverified: whether
the leaving sheet's barrier still blocks the announcement at the moment
the trip's future returns. Noticed, left: a month swipe on the practice
grid does not clear a standing report.

**C3 as built (2026-10-29 evening; gate green, suite +11075 ~10 −1):**
the catalogue holds the keep list — 27 rows (screen 2, events 4, kinds
4, alerts 4, attendance 3, categories 3, finding 2, setup 2, good 3; 48
before); 42 keys retired (the Title and Body of Month, Panel, Add, Time,
Open, Repeat, KindsOne, KindsDates, KindsOnlyOne, Skipped, AlertAdd,
QuickAlarm, Hub, Track, Count, CatCreate, CatHide, CatDelete, Search,
Holidays, WeekStart); `calendarGuideKindsTrickyBody(ends, repeat)` and
`calendarGuideKindsOnlyRepeatBody(trackPresence, countOccurrences,
skippedDays)` lost the placeholders the new text no longer uses, as
`calendarGuidePerDayBody(perDay, thisDay)` did; the 8.3.6 leads and the
intro (its `@` entry keeps a one-line description, only the placeholders
block went), the 8.3.7 bodies and the 8.3.2a trims in the three ARBs —
de / ro cut where a sentence survived, re-translated where the English
changed (the implementer's list is in its report; the de tier words
hold: Mitteilung the reminder tier, Erinnerung an alert of either kind;
ro notificare / alertă); the flow's row step on `calendar-guide-templates`
and its header reworded; `reminder_word_test.dart` lost the three
retired bodies it listed, `calendarGuidePermissionsBody` left its
not-the-tier list (the new English says nothing of a reminder) and
`calendarGuideCatAlertsBody` moved to the umbrella list; the topic
suite's catalogue case is the keep list, its quote group reads `unsaved`
and `alert-kinds`; the hub suite's page-name query is "add" ("changing"
holds no "change"). Not re-measured: the kinds slot after D50 (the
design review measures it).

**C3 reviewed (2026-10-30, 00:xx; 10 findings, none a write).** The
catalogue, the 42 retirements, all 137 guide keys' placeholders, the
generated files, the de / ro against the new English and the tests
held. Fixed by the lead in the tree: **(1)** the intro was two 20 px
lines at 1.0 on 360 in all three languages (the column is 296 px; the
record's text was 351–365) — now "Tap a page. Nothing you try there is
real." / „Tippe auf eine Seite. Nichts dort ist echt.“ / „Atinge o
pagină. Nimic de acolo nu e real.”; **(2)** `calendarGuideAlertKindsBody`
said an alarm needs a start time — the alert sheet mints an all-day
alarm at a time of day (`alert_editor_sheet.dart:169-175`), only
"minutes before" needs one; the three texts corrected (§8.3.7); **(3)**
de `calendarGuideAlertsLead` "wo du einen willst" → "wo du sie
brauchst"; **(4)** de `calendarGuideKindsBirthdayBody` "den echten
Geburtstag" → "das echte Geburtsdatum"; **(5)** de
`calendarGuideDescriptionBody` "Das erscheint" → "Das alles siehst du";
**(6)** the de `calendarGuideCoachCategoriesCreate` set the categories
slot at de 2.0 (273) — shortened to "Name, Symbol, Farbe"; **(7)** the
hub suite's "country" case asserts every other page absent, not only
attendance; **(8)** §8.3.8 amended for the two arities. Left: the "add"
query also matches `description` ("address") and rows on other pages —
its assertions still prove the case; the working-tree LF endings in the
files the agents rewrote normalize on commit (autocrlf). The slots at de
2.0 on 360 after D50: screen 195, events 273 (its Skipped report), kinds
234 (351 before), alerts 234, attendance 195, categories 273 → lower
after (6), finding 195, setup 195; the closing line (de, 195) is now the
floor on four cards.

**Design review of the close (2026-10-30; the events and categories
cards and the band over light / dark × en / de × 1.0 / 1.3 / 2.0 × 360 ×
780 / 412 × 915, real fonts).** The band holds every pinned number: 72 /
111 / 111 at de on 360 (72 / 88 / 88 on 412), the 2.0 band identical to
the 1.3 one, the skip glyph centred on the line's first row to 0.00 dp,
13.3:1 / 7.2:1 enabled and 2.4:1 disabled (allowed), no word broken in
any language, one live region, the title read once, the three guideline
matchers green on the cards in both themes. Found: **(1, sev 2)** at de
2.0 on 360 × 780 the events card's stage starts at 819 dp — the heading
is four lines (64→272), the lead four, the slot 273 (sized by the card's
Skipped report, a long weekday-date), so "Tap +" is read before its +
is on screen (en 2.0: 715; categories de 2.0: 637; 412 × 915 de 2.0:
689; at 1.3 always on screen); **(2, sev 2)** under a short line the
slot leaves 40 dp blank at en 1.0 and up to 156 at en 2.0, the same
cause; **(3, sev 2, not this rework's)** on the practice page at de 2.0
on 360 in the month format the + covers 36 × 42 dp of the Day panel's
presence button (L272 T722 R320 B770 under the FAB at L284 T708 R344
B764 — the button is on screen now, 793 before, and under the +; at 1.3
a 5 dp overlap; none at 1.0); **(4, sev 2, slice 3's)** on the events
stage with a fourth row the + covers the last row's chevron until the
list is scrolled; **(5, sev 1)** the card's skip glyph sits 14 dp below
the line's first row at 1.0 (the band's is exact); **(6, sev 1)** the
card's skip in `outline` reads 3.96:1 / 2.31:1 light enabled / disabled
on the kit card's `surfaceContainer` — enabled and finished look alike;
**(7, sev 1)** the skip takes 56 dp of the text column (accepted); **(8)**
the kit card paints `surfaceContainer`, not `rowGroup` (equal in dark);
**(9, sev 1, not this rework's)** `androidTapTargetGuideline` fails on
the practice page on the panel's mode segment (98.7 × 32), real calendar
chrome; **(10)** the pressed ink does not render under `flutter test`
(device bucket).

**D51 (lead)** The topic page's heading is clamped at `GuideMetrics.headingMaxTextScale`
1.5 (`MediaQuery.withClampedTextScaling` round the heading alone, never
the lead or the rows): a 20 px heading at 2.0 is 40 px and four lines in
German, a fifth of the screen before the first instruction; at 1.5 it is
30 px. The lead and every read row keep the full scale. **D52 (lead)**
The events card's Skipped report writes its date as the band did under
D38 (`DateFormat.MMMEd`), so the slot is sized by the instructions
again; the card's skip takes `onSurfaceVariant` (`disabledColor` the
same at 38 %) and the line's slot a top inset of `(trailingButtonSize −
the line's first row) / 2`, never below 0, so the glyph is centred on
the first row as the band's is — the inset is constant per scale, so
nothing moves. Done means for the close: the events and categories
stages' tops under 780 at de 2.0 on 360 × 780, asserted in the topic
page suite. Deferred to §6: (3), (4), (9).

**Design fix pass as built (2026-10-30; gate green, suite +11079 ~10
−1):** D51 and D52 as written — `GuideMetrics.headingMaxTextScale` 1.5
round the heading alone; the events card's one `GuideLocaleFormat` is
`DateFormat.MMMEd` (no second format kept); the skip in `onSurfaceVariant`
with `disabledColor` at 38 %; the slot's top inset from a private
`_lineInset(TextScaler)`. Measured: the stage's top at de 2.0 on 360 ×
780 is 693 on the events page (819 before) and 576 on categories (637);
the events slot 234 (273); the glyph's centre against the first row's
−0.4 dp at en 1.0 and +0.2 at de 2.0 (+13.8 / +4.6 before). The topic
suite asserts both stage tops under 780 and the heading's scale, the
cards suite the glyph within 1 dp; the slot cases compare the
stage-to-line offset with `moreOrLessEquals` (a fractional inset put
float noise in an exact compare).

**Device pass (2026-10-30, 00:33–00:45, `qa pass calendar -d
emulator-5556`): 27 / 27 green in 522 s**, `26_guide` 20 s; the pass
warned that `app_localizations.dart` was touched 14 s after the APK was
built — `flutter test` regenerates it byte-identically (a `gen-l10n`
afterwards changed no diff), and the `qa-runner` rebuilt and re-ran
`26_guide` green (17 s) regardless; `qa errors` clean before and after
the hand checks. Hand checks at de 2.0 dark on the emulator: the events
page shows its first instruction, the skip and the + with three seed
rows on the first frame; the practice page's band shows its skip and
its first line, and the Yoga row's presence button is on the first
frame (today is Yoga's weekday); a 4 s press on either skip shows the
tooltip and no ink ring at 2.2 s (a brief ink at press time is not
excluded — §6 (d) stays). The device left on en / 1.0 / light, the QA
database fresh and empty, nothing armed.

### 7.6 The owner's second review (2026-10-30) — two practice lessons, the screen page's real views, a fasting page — status: **IMPLEMENTED 2026-10-30 — F1–F4 built, reviewed and fixed (uncommitted; suite +11264 ~10 −1, `qa pass calendar -d emulator-5556` 28 / 28, `qa errors` empty)**

**The owner's letter (2026-10-30), after the coach rework:** the practice
calendar "is okay" but is to be called *Practice calendar events*; "we
need the exact same screen with data to teach the user filtering"
(*Practice calendar filtering*); "the Calendar screen is near useless in
current form, let's at least put some mocks of current widgets to show the
user the overview, monthly, all modes, no need to be able to edit data
there"; Good to know and the seven task pages stay as they are; "we also
need here a guide on how to use fasting system"; and "please make sure
that we do not add needless tech debt, if we update our widgets that we
normally use in the app the update should be automatic".

**Decisions.** The lead's are reversible defaults, lettered for the
owner; the owner's are his words.

- **D53 (owner)** The practice calendar is "Practice calendar events"; a
  second hub row, "Practice calendar filtering", opens the same screen
  over a fuller seed with a tour about the funnel.
- **D54 (lead)** One page class: `CalendarGuidePracticePage(lesson:)`
  over `enum GuidePracticeLesson { events, filtering }`; the lesson picks
  the route's label and title, the seed, the tour's steps and closing
  line, and the container id. Never a second page class, never a copied
  build. The frozen slug `practice` and every `practice-*` control id
  stay (the two lessons are never on screen together); the filtering
  lesson's hub row is `calendar-guide-page-practice-filtering` and its
  container `calendar-guide-practice-filtering`. In "Start here" the two
  practice rows come first, events then filtering; the search lists one
  section per lesson, each holding its own row, keyed on the lesson's
  first tour line as a page's row is on its card's.
- **D55 (lead)** The filtering seed is the events seed plus six, one per
  axis the funnel offers that a demo can hold (the money axis reads the
  note ledger and is left out): a tracked weekly event with a missed
  week and priority P2; a weekly event that ended two weeks ago (Not
  ended); a yearly counted all-day event (Counted); a one-time all-day
  event at P1 with a description (Priority, With description); a one-time
  timed event in a further category; and an every-third-day all-day
  event at P5, so a month reads as busy. Categories continue the cycle
  the events seed starts (§8.2 table 6's rule), so the funnel's category
  list has at least four to untick. The titles are §8.4. *Amended after
  the F1 review:* the tracked event is "Pilates", not "Gym" — on a fresh
  install the cycle dresses it in Mobility, and a newcomer who unticks
  the Gym category would have watched the Gym event stay.
- **D56 (lead)** The filtering tour is four steps and a closing line
  (§8.4), each marked from what the funnel *returns* — the sheet reports
  only on Apply: `funnel` (the sheet closed, applied or dismissed — not
  `opened`, which is the events tour's word for an event's sheet, and the
  page reports every action to whichever tour runs), `category` (applied
  with a category hidden), `trait` (applied with any axis but categories
  active: priority, repeat, timing, Only show, a layer), `reset` (applied
  with nothing active after something was, **and only once `category`
  and `trait` are done** — the F1 reviewer showed the closing line
  reading "everything is back" over a live filter otherwise). A done set
  as every coach is (D46): an Apply that hides a category and sets a
  trait marks both. The lines stay inside the band's pinned height
  (D38 / D39), which cut the first draft's lines by half; the badge is
  left to speak for itself. Start over restores the lesson's own seed.
- **D57 (owner)** The calendar screen page shows the real views over demo
  data — the month grid in its formats, the panel in its three modes, the
  overview in its three modes — and nothing on it edits: no add button,
  no sheet, no presence button. The switches that change a view (the
  title menu, the mode bar, the overview's chips, its arrows and Today, a
  day tap) stay live: they are the lesson.
- **D58 (lead)** Three cards on the screen page, not one tall stage: the
  `screen` card (slug kept; the bar over the month grid, the title menu
  reshaping it; steps `title`, `more`), the `panel` card (the mode bar
  over the picked day's panel body; step `panel`, the existing line), the
  `overview` card (the period nav, the chip row and the mode's body; steps
  `mode`, `period`). The catalogue gains `CalendarGuideTopic.cards`, a
  list of `GuideCardSpec(slug, steps, title)`; every other page has one
  card titled "Try it"; the screen page's three carry their own section
  titles (§8.4). `tryLead` becomes the first card's first line and the
  hub row's keywords take every card's. The alternative, B, one card with
  a mode machine, would stand 900 px tall and reach the overview only
  through the title menu. The three cards select one day between them
  (the demo's), so the panel shows the day the grid picked.
- **D59 (lead, the owner's tech-debt rule)** The guide keeps one copy of
  each wiring. `GuideCalendarGrid` (`lib/widgets/calendar_guide_grid.dart`)
  is the practice page's `_grid` lifted out, with the cell's tint, number
  colour and bars taken from resolvers the caller passes; the two lessons,
  the screen card and the fasting card draw it. `GuideDemoPanel`
  (`lib/widgets/calendar_guide_demo_panel.dart`) is `_panelBody`,
  `_dayEntries` and `_upcoming` lifted out, with the taps optional; the
  practice page and the panel card draw it. The overview's chip row
  becomes `OverviewModeChips` (`lib/widgets/overview_mode_chips.dart`),
  the overview page and the overview card draw it (`onSearch` nullable
  → the button disabled, never hidden; the ids a callback). The year
  tiles come from a real `AgendaMonthStore` over the demo's scans and the
  one tile builder the overview uses (`agenda_year_scroll.dart:750`,
  `agenda_year_grid.dart:50`), never a second tile formula. What stays
  duplicated is `_CalendarTable`'s `TableCalendar` wiring
  (`calendar_page.dart:1679`, bloc-bound, with the output caches and the
  rail) against `GuideCalendarGrid`: lifting the calendar page's grid out
  of its bloc is the hot path's own refactor and the owner's call —
  recorded in §6.
- **D60 (owner)** A fasting page. **(lead)** `CalendarGuideTopic.fasting`,
  slug `fasting`, the settings section's glyph
  (`Icons.restaurant_menu_rounded`), last of "How do I…" after Set up the
  calendar, titled "Fasting days" (§8.4).
- **D61 (lead)** The fasting card's stage, top to bottom: four
  `FormSwitchRow`s, one per tradition, glyph and colour as the settings
  page draws them (`calendar_settings_page.dart:654-670`); an
  "Appearance" row that opens the real `FastingStyleSheet` for the first
  tradition that is on, its value the tradition's name; a "My practice"
  row that opens the real `FastingScheduleSheet`; a "Multi-day fasts"
  switch. The three are disabled, never hidden, while no tradition is on
  (the switch only while Orthodox is). Under them `GuideCalendarGrid` in
  the month format, pageable, with no events, washed and barred by the
  real fasting providers; under that a fixed-height day panel
  (`DaySummaryPanel`) for the picked day with the real
  `FastingSummaryProvider` and the weekend row, scrolling inside its slot.
  The stage opens on today's month with every tradition off. The two
  sheets write through their `onChanged` only, into the demo; the
  style sheet's swatch picker runs in its sandbox.
- **D62 (lead)** The fasting seams, the `isMissed` pattern (a default that
  is today's static read): `FastingCalendar.computeYear(year, traditions:,
  orthodoxGreatFasts:, schedule:)`, pure, which the static `_buildYear`
  calls with the configured values (the Orthodox builder takes the flag
  as an argument instead of reading `_orthodoxGreatFasts`);
  `FastingCalendar.resolveCellStyle(infos, appearance)`, pure, which the
  static `cellStyleForUtcDay` calls; `FastingSummaryProvider`,
  `FastingDayBarProvider` and `FastingCellTintProvider` take an optional
  `FastingLookup` (`on(day)` and `appearance`) whose absence is the static
  read; the static `styleOf`, `colorOf` and `iconFor` and the providers
  share one set of pure helpers. The demo never calls `configure`; the
  suite pins `FastingCalendar.revision` across every action of the card
  and runs under the sandbox write log.
- **D63 (lead)** Steps per card, the lines in §8.4: fasting `tradition`,
  `style`, `practice`; screen `title`, `more`; panel `panel`; overview
  `mode`, `period`.
- **D64 (lead)** The screen page's `views` row keeps only its trap (a
  grid shrunk to one or two rows); `marks` stays. The fasting page's rows
  are four: where it is switched on, what the row says, your own
  practice, hiding them for a while.
- **D65 (lead)** Flows: `26_guide` expects the screen page's three cards
  by id; a new `27_guide_lessons` walks the filtering lesson (the hub's
  row, the funnel, a category unticked, Apply, the badge, Start over) and
  the fasting page (the card by id, a tradition switch, back). The
  calendar pass becomes 28 flows.

**The design review (2026-10-30, F4; 18 findings over 95 renders in
both themes, de 1.0 / 1.3 / 2.0 on 360 and en 1.0 / 2.0 on 412, the
three guideline matchers, the four suites green)** found nothing
blocking and one severity-3: on 360 × 780 the fasting card's switches
(y 364–559 at de 1.0) and the grid they change (its first row below 780)
were never on screen together. Its decisions:

- **D66 (lead)** The coach line clamps its text scale at 1.3
  (`GuideMetrics.coachMaxTextScale`), the band's D39 by analogy: the slot
  had measured 273 dp at de 2.0 on the fasting card (seven lines in a
  232 dp column) and 234 on the overview card, so the line and its stage
  never shared the screen.
- **D67 (lead, amends D61)** The fasting stage puts the grid first, then
  the four traditions as one `FormChipRow` of selectable chips (the ids
  kept), then Appearance, My practice and Multi-day fasts, then the
  panel; the tradition line says "under the grid" (§8.4.4). The
  switches' glyph-and-colour rule goes with the switches.
- **D68 (lead)** The overview card opens in Month mode on the shared
  day's month (it opened on Year with this month's tile below the slot's
  fold — nine empty tiles); Year mode scrolls on entry so the current
  month's row is visible; List mode lists the shown month, the nav
  stepping months in Month and List and years in Year, so a slot's
  content is short and a flick inside it reaches its end (a year of rows
  in a 360 dp slot held the page mid-screen).
- **D69 (lead)** `DaySummaryPanel` draws no chevron on a row with no tap
  (the panel card's rows read as tappable and did nothing); the panel
  card's slot follows the clamped text scale (300 × min(scale, 1.3)),
  since at de 2.0 its fixed 324 dp stage could not show one Day row.
- The four suites gain the Android tap-target and the text-contrast
  guidelines (as built `GuideTapTargetGuideline` / `GuideTextContrastGuideline`
  in `test/widgets/support/guide_guidelines.dart`) with two named
  exceptions (the day cells at 45.7 dp on 360, `PanelModeBar`'s 32 dp
  segments). The severity-1 items
  left as the app's own are in §6; the device-only bucket (the slot
  hand-off under a thumb, the mini month's swipe, the sheets over the
  card at 2.0, TalkBack on the chips and the band, the "→" glyph in de
  and ro, dark wash in sunlight) is the owner's phone check.

**Must not change.** Everything §7.2's and §7.5's lists hold: the
sandbox seams and the no-write rule, the frozen ids, the coach machine's
done-set semantics, the practice page's band geometry (D38 / D39), the
fasting engine's static behaviour and caches (`configure`,
`resetConfiguration`, the FIFO), the overview page's behaviour and ids,
`CalendarDayCell` and `CalendarDayBars`, the ARB keys every flow reads.

**Slices** (one `implementer` and one `reviewer` each, the gate after
each, the owner commits):

- **F1 — the two lessons and the shared wiring.** D53–D56, D59's
  `GuideCalendarGrid` and `GuideDemoPanel` (lifted as they are, the
  practice page drawing them with nothing visible changed), the hub's
  rows and search, the rename, §8.4's practice strings, the suites
  (`calendar_guide_practice_page_test.dart` over both lessons through
  `PracticeCalendarRobot`; the filtering lesson's cases: the seed's
  variety per axis, the tour in order, a step done early, reset to the
  closing line, Start over, the route name; the hub suite's two rows and
  search), `27_guide_lessons`'s first half.
  *As built 2026-10-30 (one `implementer`, one `reviewer`, one fix pass):*
  `GuidePracticeLesson { events('practice'), filtering('practice-filtering') }`
  in the catalogue with `title`, `caption`, `steps`, `closing`; the page's
  `_mark` reports every action to whichever tour runs and `GuideCoach`
  gained `hasStep` / `hasDone`; `GuideLocaleFormat` moved to
  `lib/utils/guide_locale_format.dart` so the grid and the try card do not
  import each other; `DayTimelineView.onEventTap` and
  `AgendaDayListRowBuilder.onEntryTap` became nullable (null = an inert
  block or row, an all-day block a plain `Chip`), the seam the panel card
  of F2 draws through; a dismissed filter sheet clears a standing report
  in both lessons (D49). The review (10 items, nothing writes, the lift
  diffed mechanically against `5b4275da`) closed nine: the band's pinned
  height (the lines cut, §8.4.2), the false closing line (D56's "reset
  last" rule), Gym → Pilates (D55), the panel's overclaiming doc, the
  dismissal asymmetry, two stale comments, four test gaps, the import
  cycle; the insurance's 29 February start was left. Gate: analyze clean,
  `untranslated.txt` `{}`, suite +11100 ~10 −1 (the Windows-only case).
  `27_guide_lessons` is unrun until F4. The Dart files the slice edited
  are LF in the working copy (`core.autocrlf` normalises them on commit).
- **F2 — the screen page.** D57–D59's rest, D63's screen, panel and
  overview cards, D64's `views` row, §8.4's screen strings, the try-cards
  suite (the three cards, the one picked day, every view switch, no
  sheet opens from any tap, the stages' heights at 2.0), the overview
  page's suite over `OverviewModeChips`, `26_guide`'s ids.
  *As built 2026-10-30 (one `implementer`, one `reviewer`, one fix pass):*
  `GuideCardSpec(slug, steps, title)` and `CalendarGuideTopic.cards`;
  `GuideCardDemo` over a spec; the screen page's three demos over one
  `GuideScreenWorld` (the shared `GuideDemoCalendar`, the look, the
  palette, the resolvers; built before the first frame over the cached
  categories and re-seeded over `CategoryService`'s with the picks kept);
  `GuideOverviewDemo` over a real `AgendaMonthStore` resolved only on
  navigation and on a world change, Year mode one year at a time on
  `AgendaYearGrid` (the day list's own grid — the overview page scrolls
  years continuously through `AgendaYearScroll`, which no card can hold);
  `OverviewModeChips` lifted out of the overview page with the ids as a
  callback. The review (11 items, the gate green, five probes run in a
  copy of the tree) found two confirmed interaction bugs — the fixed
  slots (340 / 480 px) took two thirds of a 732 px viewport and never
  handed a drag back to the page; the mini month keyed on its month was
  thrown away at the half-way point of a swipe — a confirmed staleness (a
  language change left the seed in the old language), the grid card's bar
  hand-built with the saved-filters button and the funnel dropped, and the
  "Mon" / "Wed" pins at en 2.0 as the card's narrowing, not the widget's.
  The fix pass: `GuideStageSlot` (a fixed box whose inner scrollables hand
  a finger's overscroll to the page, slots 300 / 360), the grid keyed on a
  navigation counter, the world re-seeded on a locale change,
  `GuideCalendarBar` lifted from the practice page and drawn by the card
  with its two filter slots disabled, the Month mode's whole-month toggle
  and the page's pickable-day rule, the three stages full-bleed at every
  scale, one notification per tap, the titles cached, the panel's bottom
  clearance a parameter.
- **F3 — the fasting page.** D60–D64, §8.4's fasting strings, the seams
  with their tests (`computeYear` against the static build for a year,
  `resolveCellStyle`, a provider with a lookup), the card's suite (the
  switches, the two sheets through their own robots, the grid washed and
  barred, the panel row, `revision` pinned, no write), the topic page's
  rows, `27_guide_lessons`'s second half.
  *As built 2026-10-30 (one `implementer`; its review and fix pass follow):*
  `FastingLookup` in `fasting_calendar.dart` — an abstract class with
  `on(day)`, `appearance` and the three helpers `styleOf` / `colorOf` /
  `iconFor` written once; `FastingLookup.facade` reads the static engine
  live and the static getters go through it (a const object holding the
  appearance would have frozen it); `computeYear` pure, `_buildYear`
  calling it with the configured values, `_buildOrthodox` and
  `_applyForcedDays` taking their inputs as arguments;
  `resolveCellStyle` lifted out of `cellStyleForUtcDay`; the three
  providers take `lookup:` by name (null = the facade);
  `FastingStyleSheet.show(sandbox:)` reaching the icon picker and the
  swatch strip; `FormSwitchRow.glyphColor` (retired in F4 with D67's
  chips); `GuideDemoCalendar.empty`;
  `GuideCalendarGrid(tintResolver:, numberColorFor:)` wired as
  `_buildDayCell` wires them; `GuideFastingDemo` building a year only on a
  change and on paging, the window's and the picked day's years kept;
  `fastingPanelHeight` 220; the Appearance row opens the first tradition
  that is on, its height held over every name. The suite's fixed dates:
  2027-03-17 (Great Lent 2027 starts 15 March; the 10th is Cheesefare
  week) and 13 / 15 October 2027. Gate: analyze clean, `untranslated.txt`
  `{}`, suite +11178 ~10 −1. The review (10 items, nothing blocking; the
  engine lift diffed against `5b4275da`, the sandbox gates traced, the
  strings checked by script) found the coach line pointing at a disabled
  Appearance row once every tradition was off again, the two parity
  tests proving only the pass-through, the overflow exemption too broad,
  and the resolvers assembled by hand instead of through the three
  `defaults` factories; the fix pass: the `tradition` line while nothing
  is on, `lookup:` on the three factories, behaviour cases on the pure
  `computeYear`, the write-log cases through every sub-sheet, a skipped
  and a forced date reaching the wash, a disposal guard on
  `GuideCardDemo`, the flow asserting the switch's effect, a full-panel
  height case and a `computeYear` call count. *Fix pass as built:* the
  factories' parameter is `fastingLookup:` (beside `isMissed` and
  `showFasting` a bare `lookup` read wrong); the card's year window is
  the grid's real reach (a week before the month to the 14th of the next,
  plus the picked day's year), and `FastingCalendar.debugComputeYearCalls`
  counts builds behind an `assert` — the first tradition on builds the
  year once, a tap, a frame and a look change build none, paging into
  December builds the next year once; the "fullest day" case (the
  2027–2028 day most traditions mark, at least three) holds the stage's
  height at de 2.0; a Skip from idle on this card marks a step without
  moving the line while no tradition is on (the `tradition` line stands
  until one is), so two Skips look dead — accepted, the third reads the
  closing line. Gate: suite +11193 ~10 −1.
- **F4 — close.** The `design-reviewer` over the filtering lesson, the
  screen page and the fasting page; `qa pass calendar -d emulator-5556`
  28 / 28 and `qa errors`; the skills (`calendar-events` SKILL.md's guide
  paragraph and `references/subsystems.md`'s guide section), the feature
  doc's guide pointer, this status line.
  *As built 2026-10-30 (the design review's fix pass, one `implementer`):*
  D66 — the coach row (the line's `FormCaptionSlot` and the skip) under
  `MediaQuery.withClampedTextScaling(maxScaleFactor:
  GuideMetrics.coachMaxTextScale)`, a `Builder` so the line's top inset
  and the candidates are measured under the same clamp; a case per card
  that the coach slot at 2.0 equals its slot at 1.3. D67 — the grid, then
  one `FormChipRow(indented: false)` of the four traditions in
  declaration order (`try-fasting-tradition-<name>` kept, each a toggle
  labelled by `traditionNameOf`) as the first row of the group, then
  Appearance, My practice, Multi-day fasts, then the panel;
  `FormSwitchRow.glyphColor` and its test retired (the switches were its
  only caller; `form_rows.dart` is back to `5b4275da`); a geometry case
  on 360 × 780 at en 1.0. D68 — `GuideOverviewDemo` opens in Month on the
  shared day's month; Month and List step a month, Year a year; List
  lists the shown month under the overview's own custom-span title
  (`OverviewCustomPeriod.menuValue`), the Today tooltip naming the span;
  Year opens with the shown month's row at the slot's top through a
  private `_YearScrollHost` owning a `ScrollController(initialScrollOffset:)`
  — the row's extent from `YearMonthTile.gridDelegate`, capped at the
  grid's reach so no ballistic correction follows; the focus month is
  the one Month or List last showed if it is in the shown year, else
  this month in this year, else January; keyed on the navigation counter
  and the column count, so every entry and step reopens on that row;
  `AgendaYearGrid` takes an optional `controller` (null keeps the page's
  behaviour). *Deviation:* List's one month header carries no count
  (`monthCounts` dropped) — at de 2.0 on 360 it overflowed by 17 px and
  the nav shows the same number. D69 — `DaySummaryPanel` draws no chevron
  when `onEventTap` is null (the real callers pass one); the panel slot
  is `panelStageHeight` scaled by the text scale clamped at
  `panelStageMaxTextScale` (390 dp at 1.3 and 2.0), with a case that it
  holds one whole Day row at de 2.0. The guidelines
  (`test/widgets/support/guide_guidelines.dart`): `GuideTapTargetGuideline`
  subclasses `MinimumTapTargetGuideline` and lets off, by name, a node
  wholly inside a `PanelModeBar` segment and a node narrower than 48 dp
  but at least 48 tall inside a try card's `TableCalendar` (45.7 on the
  grid card; the mini month's 44.6 is the same cause); two cases prove
  each exception is needed (the stock guideline fails on the grid card
  at 360 and on the panel card at 412); `GuideTextContrastGuideline` also
  skips a node whose *merged* data says disabled — a disabled chip,
  switch or picker inside an `AutomationId` (a `MergeSemantics`) carries
  the flag only there, so the stock check judged the fasting card's
  three idle rows at 2.99:1 light / 2.38:1 dark (the app-wide side is in
  §6). Every card and both lessons run both guidelines × 360 and 412 ×
  light and dark, idle and closing, the section `Card` scrolled to the
  list's top (and to its bottom when taller than the screen — aligning
  the stage instead sampled the bar's colours under the overview
  caption); with the chips the review's 4.01:1 node is gone. The pins
  moved: the overview card's idle breaks "Mon" / "Wed" like the grid
  card; the panel's "Wöchentlich" pin is gone (without the chevron the
  caption fits). The Year-opens-on-the-row case compares the tile after
  a step away and back with `rectMoreOrLessEquals(epsilon: 0.01)` — an
  exact `Rect` compare failed on float noise. Gate: analyze clean,
  `untranslated.txt` `{}`, suite +11264 ~10 −1 (the lead's run; the
  implementer's own whole-suite run printed its result and then never
  exited, a two-hour wait, and an editor-page save test it had never
  touched timed out at ten minutes in that run and passed in the
  lead's). The device pass: `qa pass calendar -d emulator-5556` 28 / 28
  green in 482 s (`27_guide_lessons` 18.2 s and `26_guide`'s screen page
  20.0 s on their first device run, no rerun needed), `qa errors` empty,
  the device left quiet; the skill bullet, `references/subsystems.md`'s
  guide pointer and the feature doc's addendum updated in the same
  change.

How to run it: the lead session is this one (Fable 5.1); each slice is
one `implementer` (Opus 5.5, high) briefed from this section and §8.4
with the files named, then one `reviewer`, then the same implementer's
fix pass; F4's device pass is the `qa-runner`.


## 6. Deferred

- **From the second review (2026-10-30, D59):** the guide's grid wiring
  (`GuideCalendarGrid`) is one copy and `_CalendarTable`'s
  (`calendar_page.dart:1679`, bloc-bound, with the three output caches and
  the rail) is the other; lifting the calendar page's `TableCalendar` out
  of its bloc into one `CalendarGrid` both draw is the hot path's own
  refactor (the memo contract of `_syncResolverOutputCache`, the keyboard
  probe, the long-press quick add) and the owner's call. The same holds
  for the bar: `GuideCalendarBar` is the practice page's and the grid
  card's; the calendar page's `AppBar` stays its own.
- **From F2's review (2026-10-30), accepted as the card's cost:** a
  screen card's stage is 40 dp narrower than the screen (the kit's group
  inset and the card's), so at en 2.0 the weekday row breaks "Mon" and
  "Wed" (49.5 dp needed, 45.7 given) where the real grid at 360 holds
  them; the overview card's Year mode is `AgendaYearGrid`, one year at a
  time, not the page's `AgendaYearScroll`; the look arriving after the
  first frame can change the grid card's row height once (the practice
  page waits for it behind a spinner instead); the overview card's rows
  wrap where the page clamps them to one line for its exact extents.
- **From F4's design review (2026-10-30), left as the app's own or the
  card's cost:** the card grids' day cells are 45.7 × 62 dp on 360 (the
  real grid's 51.4, the overview's mini month 50.3, a 412 phone 53), the
  Android 48 dp rule's one failure on these pages besides `PanelModeBar`'s
  32 dp segments (§6 c); the overview card's idle breaks "Mon" / "Wed"
  as the grid card does (the panel's "Wöchentlich" fit once the chevron
  went, D69); with every tradition on the fasting grid is one
  violet, because every tradition defaults to `CalendarColors.fasting` and
  Orthodox and Catholic share a glyph (the app's defaults, shown
  faithfully); the fasting wash is faint in dark (the app's tint alpha);
  the fasting grid shows the weekend bars before any tradition is on (the
  factories' weekend layer, the real grid's look); the overview's chip row
  wraps "Liste" at de 2.0 on 360 and the period nav reserves its longest
  month title (the real page's); the filter badge covers half the funnel
  at 2.0 (`calendar_page.dart:1042`, app-wide); the Timeline's 14 px
  overflow at 2.0 (pinned); the stage's hairline edge at 1.48:1 in light
  (D29, not a control). App-wide, from the fix pass: a disabled row built
  from the form primitives (`FormPickerRow`, `FormSwitchRow`, a `FormChip`
  behind `AutomationId`) carries its disabled flag only on the merged
  child, so Flutter's stock `textContrastGuideline` judges its dimmed
  text everywhere; the guide's `GuideTextContrastGuideline` skips a
  merged-disabled node, and the primitives could set the flag on the
  outer node instead — the `ui-language` kit's call.
- **From F3's review (2026-10-30), not this slice's:** `ColorSwatchPicker`
  constructs `CalendarPaletteService` in `initState` even in sandbox
  (`color_swatch_picker.dart:136`), and that service's first construction
  folds legacy `recent_event_colors` into the custom colours
  (`calendar_palette_service.dart:101-110`) — a one-time migration write
  the sandboxed style sheet and Look sheet could trigger on an install
  whose palette was never read; the sandboxed strip reads the facade for
  its swatches, so the gate would be "publish without folding", the
  service's call.
- **From the coach rework's design review (2026-10-30), not the coach's
  own:** (a) the calendar's Day panel with one row under the + at de 2.0
  on 360 in the month format — on the practice page the presence button
  (L272 T722 R320 B770) sits under the FAB (L284 T708 R344 B764), a 36 ×
  42 dp overlap that a panel flick clears; the real calendar page lays
  the same panel under the same FAB, so the fix is the panel's (bottom
  clearance that holds even when its content does not scroll), in
  `calendar_bottom_panel.dart`, calendar-wide; (b) the events card's
  stage (`calendar_guide_try_events.dart`) with a fourth row: the last
  row's end sits under the stage's + until the list is scrolled — reserve
  the +'s row below the list or scroll to the added row; (c) `PanelModeBar`'s
  segments are 98.7 × 32 dp on 360 and fail `androidTapTargetGuideline`
  — real calendar chrome, an app-wide decision with the kit's segmented
  rows; (d) the pressed ink of either skip is unverified off a device.
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
- **From the hands-on rework's reviews (2026-10-29), left as found:**
  the kit's `SettingsSearchField` is a 38 dp target and its hint clips at
  de 2.0 (both for `docs/ui-language-adoption-roadmap.md`, kit-wide); the
  read rows' German compounds ("Bearbeitungsbildschirm",
  "Benachrichtigungen", „Kalendereinstellungen“) break at de 2.0 on both
  phone widths — running text with no hyphenation, since the first build;
  the hub's intro fills the first screen at de 2.0 on 360 (D25's cost; a
  1.3 clamp on the intro would fix it — the owner's call); the categories
  and alerts cards rest on an empty caption slot (D30 — an idle string for
  each would need two ARB keys); `CalendarDaysOfWeek` breaks "sâm." /
  "dum." at ro 2.0 on 360 and the Day panel's date title is ellipsised at
  2.0 (the calendar's own, shared with the real grid); the real calendar
  page's month-header chevrons are 40 × 40 with no label
  (`calendar_page.dart:1942`, an app-wide decision — the practice page's
  own header was fixed); the overview's `AgendaMonthGrid` seems to clip
  its 24 px weekday row at 2.0 ("Mo" wraps at 360 — seen in tests, to
  confirm on a device) and its `upcomingSearchHint` is probably cut off
  at 2.0 on narrow phones; the detail sheet's Next row and stats go
  through `occursOnUtcDay`, which reads the static `EventSkips` and so
  ignores a demo skip (a third read seam, not taken); the practice grid's
  plain month title (no Today button, no month picker); the caption
  stand-ins by character count (a 24-'W' title can grow a slot); seed
  titles under a live locale change; the `practice*` metrics copying the
  real grid's `AppSpacing` values; the hub rows' `hasSelectedState`
  (`ListTile`'s default, as Calendar settings); `DayTimelineView`
  overflowing inside its blocks at text scale 2.0
  (`day_timeline_view.dart:366`, pre-existing).

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

### 8.3 The coach rework's strings (§7.5; C1 lands 8.3.1–8.3.4, C2 the retirements of 8.3.5, C3 8.3.6–8.3.8)

Every quoted label is a placeholder fed from the app's own key (the
guide's rule since D5): `{calendar}` ← `calendar`, `{day}` ← `panelModeDay`,
`{timeline}` ← `panelModeTimeline`, `{upcoming}` ← `upcomingEvents`,
`{save}` ← `save`, `{edit}` ← `edit`, `{deleteEvent}` ← `deleteEvent`,
`{repeat}` ← `eventRepeat`, `{weekly}` ← `recurrenceWeekly`, `{done}` ←
`eventDescriptionDone`, `{date}` ← `eventDateLabel`, `{skip}` ←
`eventSkipOccurrence`, `{doesNotRepeat}` ← `recurrenceDoesNotRepeat`,
`{addDate}` ← `eventAddDate`, `{addAlert}` ← `eventAlertAdd`, `{showAlarm}`
← `calendarGuideShowAlarm`, `{countOccurrences}` ← `eventCountOccurrences`,
`{createCategory}` ← `createCategory`, `{delete}` ← `delete`, `{apply}` ←
`apply`, `{holidaySet}` ← `holidayProfileTitle`, `{weekStart}` ←
`calendarWeekStartTitle`.

#### 8.3.1 The frame

| key | en | de | ro |
|---|---|---|---|
| calendarGuideCoachAfter | {report} {next} | {report} {next} | {report} {next} |
| calendarGuideCoachDone | Done. Nothing here was real. Try anything, or go on. | Fertig. Nichts hier war echt. Probiere, was du willst, oder geh weiter. | Gata. Nimic de aici nu a fost real. Încearcă orice sau mergi mai departe. |
| calendarGuideSkipStep (tooltip) | Skip this step | Diesen Schritt überspringen | Sari peste acest pas |

#### 8.3.2 The cards' coach lines

| key | en | de | ro |
|---|---|---|---|
| calendarGuideCoachScreenTitle | Tap “{calendar}” at the top: that title is a menu of views. | Tippe oben auf „{calendar}“: dieser Titel ist ein Menü mit Ansichten. | Atinge „{calendar}” sus: titlul este un meniu cu moduri de afișare. |
| calendarGuideCoachScreenMore | Now tap the three dots at the top right: the calendar's menu. | Tippe jetzt oben rechts auf die drei Punkte: das Menü des Kalenders. | Acum atinge cele trei puncte din dreapta sus: meniul calendarului. |
| calendarGuideCoachScreenPanel | Switch the panel at the bottom between “{day}”, “{timeline}” and “{upcoming}”. | Wechsle den Bereich unten zwischen „{day}“, „{timeline}“ und „{upcoming}“. | Schimbă panoul de jos între „{day}”, „{timeline}” și „{upcoming}”. |
| calendarGuideCoachEventsAdd | Tap + to add an event. Give it a name, then tap “{save}”. | Tippe auf +, um ein Ereignis hinzuzufügen. Gib ihm einen Namen und tippe auf „{save}“. | Atinge + ca să adaugi un eveniment. Dă-i un nume, apoi atinge „{save}”. |
| calendarGuideCoachEventsOpen | You can open an event by tapping it in the list below. Open the one you added. | Ein Ereignis öffnest du, indem du es in der Liste unten antippst. Öffne das, das du hinzugefügt hast. | Poți deschide un eveniment atingându-l în lista de mai jos. Deschide-l pe cel adăugat de tine. |
| calendarGuideCoachEventsChange | Open it again and tap “{edit}” at the top right. Change the name, then “{save}”. | Öffne es noch einmal und tippe oben rechts auf „{edit}“. Ändere den Namen, dann „{save}“. | Deschide-l din nou și atinge „{edit}” din dreapta sus. Schimbă numele, apoi „{save}”. |
| calendarGuideCoachEventsDelete | To delete it: open it, tap “{edit}”, then “{deleteEvent}” at the very bottom. | Zum Löschen: öffne es, tippe auf „{edit}“ und ganz unten auf „{deleteEvent}“. | Ca să-l ștergi: deschide-l, atinge „{edit}”, apoi „{deleteEvent}” de tot jos. |
| calendarGuideCoachKindsRepeat | Tap “{repeat}” and choose “{weekly}”, then “{done}”. Watch the month below fill up. | Tippe auf „{repeat}“, wähle „{weekly}“, dann „{done}“. Sieh zu, wie sich der Monat unten füllt. | Atinge „{repeat}”, alege „{weekly}”, apoi „{done}”. Privește cum se umple luna de jos. |
| calendarGuideCoachKindsSkip | Tap “{date}” and pick a day with a dot, then “{skip}”. That day goes; the others stay. | Tippe auf „{date}“, wähle einen Tag mit Punkt, dann „{skip}“. Dieser Tag fällt weg, die anderen bleiben. | Atinge „{date}”, alege o zi cu punct, apoi „{skip}”. Ziua aceea dispare; celelalte rămân. |
| calendarGuideCoachKindsOnce | Tap “{repeat}” again and choose “{doesNotRepeat}”: one day again. | Tippe noch einmal auf „{repeat}“ und wähle „{doesNotRepeat}“: wieder nur ein Tag. | Atinge din nou „{repeat}” și alege „{doesNotRepeat}”: din nou o singură zi. |
| calendarGuideCoachKindsAddDate | “{addDate}” gives a one-time event a second day. Try it. | „{addDate}“ gibt einem einmaligen Ereignis einen zweiten Tag. Probier es aus. | „{addDate}” dă unui eveniment unic o a doua zi. Încearcă. |
| calendarGuideCoachAlertsAdd | Tap “{addAlert}”, choose when it should go off, then “{done}”. | Tippe auf „{addAlert}“, wähle, wann sie losgehen soll, dann „{done}“. | Atinge „{addAlert}”, alege când să sune, apoi „{done}”. |
| calendarGuideCoachAlertsShow | Now tap “{showAlarm}” to see what an alarm looks like when it rings. | Tippe jetzt auf „{showAlarm}“, um zu sehen, wie ein Alarm aussieht, wenn er klingelt. | Acum atinge „{showAlarm}” ca să vezi cum arată o alarmă când sună. |
| calendarGuideCoachAttendanceMark | Tap a day below to mark it missed; tap it again for present. The count follows. | Tippe unten auf einen Tag, um ihn als verpasst zu markieren; noch einmal für anwesend. Die Zählung folgt. | Atinge o zi de mai jos ca s-o marchezi ratată; atinge-o din nou pentru prezent. Numărătoarea urmează. |
| calendarGuideCoachAttendanceCount | Turn on “{countOccurrences}” to number the days, then pick how they count. | Schalte „{countOccurrences}“ ein, um die Tage zu nummerieren, und wähle dann, wie gezählt wird. | Pornește „{countOccurrences}” ca să numerotezi zilele, apoi alege cum se numără. |
| calendarGuideCoachCategoriesCreate | Tap “{createCategory}”: a name, an icon, a colour, then “{save}”. | Tippe auf „{createCategory}“: Name, Symbol, Farbe, dann „{save}“. (shortened after the C3 review — it set the categories slot at de 2.0) | Atinge „{createCategory}”: un nume, o pictogramă, o culoare, apoi „{save}”. |
| calendarGuideCoachCategoriesHide | Tap the eye on a category to hide it from the pickers. Tap it again to show it. | Tippe auf das Auge einer Kategorie, um sie aus der Auswahl zu nehmen. Noch einmal, und sie ist wieder da. | Atinge ochiul unei categorii ca s-o ascunzi din liste. Atinge-l din nou ca s-o arăți. |
| calendarGuideCoachCategoriesDelete (D49: `{other}` ← `eventCategoryOther`) | Tap the three dots on your own category, then “{delete}”: its events move to “{other}”. | Tippe auf die drei Punkte deiner eigenen Kategorie, dann auf „{delete}“: ihre Ereignisse wandern zu „{other}“. | Atinge cele trei puncte ale categoriei tale, apoi „{delete}”: evenimentele ei trec la „{other}”. |
| calendarGuideCoachFindingSearch | Type a word, a category or a date in the field: the list keeps only the matches. | Gib ein Wort, eine Kategorie oder ein Datum ins Feld ein: die Liste behält nur die Treffer. | Scrie un cuvânt, o categorie sau o dată în câmp: lista păstrează doar potrivirile. |
| calendarGuideCoachFindingFilter | Tap the funnel, hide a category, then “{apply}”. The funnel shows a number while a filter is on. | Tippe auf den Trichter, verstecke eine Kategorie, dann „{apply}“. Solange ein Filter aktiv ist, zeigt der Trichter eine Zahl. | Atinge pâlnia, ascunde o categorie, apoi „{apply}”. Cât timp un filtru este activ, pâlnia arată un număr. |
| calendarGuideCoachSetupHolidays | Tap “{holidaySet}” and pick your country: the count of holidays changes. | Tippe auf „{holidaySet}“ und wähle dein Land: die Zahl der Feiertage ändert sich. | Atinge „{holidaySet}” și alege-ți țara: numărul sărbătorilor se schimbă. |
| calendarGuideCoachSetupWeek | Choose “{weekStart}” below: the sample week turns to match. | Wähle unten „{weekStart}“: die Beispielwoche dreht sich mit. | Alege „{weekStart}” mai jos: săptămâna-exemplu se potrivește. |

#### 8.3.2a The instructions trimmed (D50, landed by C3)

**D50 (lead, 2026-10-29 evening):** after the C1 fix pass the kinds card's
slot was still 351 px at de 2.0 on 360, set by its own instructions'
length; every instruction is cut to about 70 English characters, the
trailing sentence that only narrates what the stage shows ("Watch the
month below fill up.", "The count follows.", "the sample week turns to
match") going. The owner's register holds: one or two short sentences
that say where. These rows **replace** the same keys in 8.3.2 and 8.3.3;
keys not listed here keep their 8.3.2 / 8.3.3 text.

| key | en | de | ro |
|---|---|---|---|
| calendarGuideCoachScreenPanel | Switch the panel at the bottom: “{day}”, “{timeline}”, “{upcoming}”. | Wechsle den Bereich unten: „{day}“, „{timeline}“, „{upcoming}“. | Schimbă panoul de jos: „{day}”, „{timeline}”, „{upcoming}”. |
| calendarGuideCoachEventsOpen | You can open an event by tapping it in the list below. | Ein Ereignis öffnest du, indem du es in der Liste unten antippst. | Poți deschide un eveniment atingându-l în lista de mai jos. |
| calendarGuideCoachEventsChange | Open it, tap “{edit}” at the top right, change the name, then “{save}”. | Öffne es, tippe oben rechts auf „{edit}“, ändere den Namen, dann „{save}“. | Deschide-l, atinge „{edit}” din dreapta sus, schimbă numele, apoi „{save}”. |
| calendarGuideCoachEventsDelete | To delete it: open it, “{edit}”, then “{deleteEvent}” at the bottom. | Zum Löschen: öffne es, „{edit}“, dann unten „{deleteEvent}“. | Ca să-l ștergi: deschide-l, „{edit}”, apoi „{deleteEvent}” jos. |
| calendarGuideCoachKindsRepeat | Tap “{repeat}”, choose “{weekly}”, then “{done}”. | Tippe auf „{repeat}“, wähle „{weekly}“, dann „{done}“. | Atinge „{repeat}”, alege „{weekly}”, apoi „{done}”. |
| calendarGuideCoachKindsSkip | Tap “{date}”, pick a day with a dot, then “{skip}”. | Tippe auf „{date}“, wähle einen Tag mit Punkt, dann „{skip}“. | Atinge „{date}”, alege o zi cu punct, apoi „{skip}”. |
| calendarGuideCoachKindsOnce | Tap “{repeat}” again and choose “{doesNotRepeat}”. | Tippe noch einmal auf „{repeat}“ und wähle „{doesNotRepeat}“. | Atinge din nou „{repeat}” și alege „{doesNotRepeat}”. |
| calendarGuideCoachAlertsShow | Now tap “{showAlarm}” to see how an alarm looks. | Tippe jetzt auf „{showAlarm}“, um zu sehen, wie ein Alarm aussieht. | Acum atinge „{showAlarm}” ca să vezi cum arată o alarmă. |
| calendarGuideCoachAttendanceMark | Tap a day below to mark it missed; tap it again for present. | Tippe auf einen Tag unten: er gilt als verpasst. Noch einmal: anwesend. | Atinge o zi de mai jos: devine ratată. Atinge-o din nou: prezent. |
| calendarGuideCoachAttendanceCount | Turn on “{countOccurrences}”, then pick how to count. | Schalte „{countOccurrences}“ ein und wähle, wie gezählt wird. | Pornește „{countOccurrences}”, apoi alege cum se numără. |
| calendarGuideCoachCategoriesHide | Tap the eye on a category to hide it; tap it again to show it. | Tippe auf das Auge einer Kategorie, um sie zu verstecken; noch einmal zeigt sie wieder. | Atinge ochiul unei categorii ca s-o ascunzi; atinge-l din nou ca s-o arăți. |
| calendarGuideCoachCategoriesDelete | Tap the three dots on your category, then “{delete}”: its events go to “{other}”. | Tippe auf die drei Punkte deiner Kategorie, dann „{delete}“: ihre Ereignisse gehen zu „{other}“. | Atinge cele trei puncte ale categoriei tale, apoi „{delete}”: evenimentele ei trec la „{other}”. |
| calendarGuideCoachFindingSearch | Type a word, a category or a date: the list keeps only the matches. | Gib ein Wort, eine Kategorie oder ein Datum ein: die Liste behält nur die Treffer. | Scrie un cuvânt, o categorie sau o dată: lista păstrează doar potrivirile. |
| calendarGuideCoachFindingFilter | Tap the funnel, hide a category, then “{apply}”. | Tippe auf den Trichter, verstecke eine Kategorie, dann „{apply}“. | Atinge pâlnia, ascunde o categorie, apoi „{apply}”. |
| calendarGuideCoachSetupHolidays | Tap “{holidaySet}” and pick your country. | Tippe auf „{holidaySet}“ und wähle dein Land. | Atinge „{holidaySet}” și alege-ți țara. |
| calendarGuideCoachSetupWeek | Pick a day under “{weekStart}”. | Wähle einen Tag unter „{weekStart}“. | Alege o zi sub „{weekStart}”. |
| calendarGuideTourEdit | You can change it with “{edit}” at the top right, then “{save}”. | Mit „{edit}“ oben rechts kannst du es ändern, dann „{save}“. | Îl poți modifica cu „{edit}” din dreapta sus, apoi „{save}”. |

The hub suite's search case that typed "count of holidays" (a phrase of
the old setup line) types "country" after this.

#### 8.3.3 The practice tour

| key | en | de | ro |
|---|---|---|---|
| calendarGuideTourPick | Tap a day with a bar under it. | Tippe auf einen Tag mit einem Balken darunter. | Atinge o zi cu o bară sub ea. |
| calendarGuideTourOpen | Now tap the event in the panel below to open it. | Tippe jetzt im Bereich unten auf das Ereignis, um es zu öffnen. | Acum atinge evenimentul din panoul de jos ca să-l deschizi. |
| calendarGuideTourEdit | You can change it with “{edit}” at the top right. Try it, then “{save}”. | Mit „{edit}“ oben rechts kannst du es ändern. Probier es, dann „{save}“. | Îl poți modifica cu „{edit}” din dreapta sus. Încearcă, apoi „{save}”. |
| calendarGuideTourAdd | Tap + to add an event on the picked day. | Tippe auf +, um am gewählten Tag ein Ereignis hinzuzufügen. | Atinge + ca să adaugi un eveniment în ziua aleasă. |
| calendarGuideTourFilter | The funnel at the top hides categories. Try it, then “{apply}”. | Der Trichter oben versteckt Kategorien. Probier es, dann „{apply}“. | Pâlnia de sus ascunde categorii. Încearcă, apoi „{apply}”. |
| calendarGuideTourDone | That is the whole calendar. Nothing you did here was saved. | Das ist der ganze Kalender. Nichts, was du hier getan hast, wurde gespeichert. | Acesta este tot calendarul. Nimic din ce ai făcut aici nu s-a salvat. |

#### 8.3.4 Reports cut to one sentence (changed in place)

| key | en | de | ro |
|---|---|---|---|
| calendarGuideDemoAlertSet | “{title}” now has: {alert}. | „{title}“ hat jetzt: {alert}. | „{title}” are acum: {alert}. |
| calendarGuideDemoCatCreated | Created “{name}”. | „{name}“ angelegt. | „{name}” creată. |

The cards' Added report is `calendarGuideDemoAddedShort` (the band's
until C2).

#### 8.3.5 Retired keys

C2: `calendarGuidePracticeIdle`, `calendarGuidePickedDay`,
`calendarGuideDemoAdded`, `calendarGuideDemoLongPressHint`,
`calendarGuideTryScreen` … `calendarGuideTrySetup` (the eight leads; C1
stops reading them, C2 removes them). C3: the deleted rows' title and body
keys per §7.5's keep list (`calendarGuideMonth*`, `calendarGuidePanel*`,
`calendarGuideAdd*`, `calendarGuideTime*`, `calendarGuideOpen*` — not
`calendarGuideOpening*` / `calendarGuideOpenOften*` / `calendarGuideOpenPermissions` /
`calendarGuideOpenSettings` —, `calendarGuideRepeat*`, `calendarGuideKindsOne*`
— not `calendarGuideKindsOneChange*` —, `calendarGuideKindsDates*`,
`calendarGuideKindsOnlyOne*`, `calendarGuideSkipped*`, `calendarGuideAlertAdd*`,
`calendarGuideQuickAlarm*`, `calendarGuideHub*`, `calendarGuideTrack*`,
`calendarGuideCount*`, `calendarGuideCatCreate*`, `calendarGuideCatHide*`,
`calendarGuideCatDelete*`, `calendarGuideSearchTitle` / `calendarGuideSearchBody`
— not `calendarGuideSearchHint` —, `calendarGuideHolidays*`,
`calendarGuideWeekStart*`).

#### 8.3.6 The hub's intro and the page leads (C3; the English is the
spec, de / ro cut from the existing translations where a sentence
survives, re-translated only where it changed)

| key | en |
|---|---|
| calendarGuideIntro (no placeholder any more; the C3 review measured the first text at two lines on 360 — D43 means one visual line, so it is shorter) | Tap a page. Nothing you try there is real. |
| calendarGuideScreenLead | What you see when the calendar opens, and what each part is for. |
| calendarGuideEventsLead | An event is anything with a day: an appointment, a bill, a class. |
| calendarGuideKindsLead | Most events happen once; some come back every week or month. |
| calendarGuideAlertsLead | Nothing rings by itself: you add a reminder or an alarm where you want one. |
| calendarGuideAttendanceLead | For a class or a habit, the calendar can count the days you made it. |
| calendarGuideCategoriesLead | A category gives an event its colour and icon. |
| calendarGuideFindingLead | Search by name, hide what you do not need, or look at a whole year. |
| calendarGuideSetupLead | Whose holidays, which day starts the week, the language and the look. |

de / ro for the intro: „Tippe auf eine Seite. Nichts dort ist echt.“ ·
„Atinge o pagină. Nimic de acolo nu e real.” (each one line at 1.0 on
360).

#### 8.3.7 The kept rows' bodies (C3; titles unchanged; placeholders as today's keys)

| key | en |
|---|---|
| calendarGuideMarksBody | A bar under a day means something is planned there, in its category's colour. Holidays and weekends have bars of their own. |
| calendarGuideViewsBody | The title “{calendar}” is a menu: a whole month, two weeks, one week, or “{overview}”. If the days shrink to one or two rows, pick “{month}” there again. |
| calendarGuideDescriptionBody | Under the name there is room for an address, a phone number, what to bring. It shows when you open the event. |
| calendarGuidePriorityBody | “{priority}” orders a busy day and decides which events get a bar when there are more than three. “{iconColor}” gives one event its own icon or colour. |
| calendarGuideUnsavedBody | If you close an event you were changing, the app asks whether to keep editing or discard. A saved event stays on the phone — no internet needed. |
| calendarGuideTemplatesBody | An event you add often can be saved with “{saveAsTemplate}” at the bottom of the editor. Press and hold + to use it. |
| calendarGuideKindsOneChangeBody | Editing a repeating event changes all of its days: a new time moves every session. To change one day, skip it and add a one-time event there. |
| calendarGuideKindsTrickyBody | A monthly event on the 31st skips the months without one; a yearly one on 29 February shows only in leap years. “{ends}” inside “{repeat}” stops a rule after a date. |
| calendarGuideKindsBirthdayBody | The “{birthday}” category makes a new event yearly and counts from 0: set the real birth date and the event reads the person's age. |
| calendarGuideKindsOnlyRepeatBody | “{trackPresence}”, “{countOccurrences}” and a note per day appear once an event has more than one day. “{skippedDays}” in the editor lists the days you skipped; untick one to bring it back. |
| calendarGuideAlertKindsBody (corrected after the C3 review: an alarm on an all-day event rings at its time of day — only "minutes before" needs a start time) | “{reminder}”: a notification you can dismiss or snooze. “{alarm}”: it rings until you stop it, even on a locked phone; to go off minutes before, the event needs a start time — turn off “{allDay}”. |
| calendarGuidePermissionsBody | The first time, ANTA asks to show notifications and set alarms: allow both, or nothing rings. On a Samsung phone also turn on “{battery}”; if something stays silent later, “{permissions}” in the main menu shows what is missing. |
| calendarGuideRingBody | A reminder is a notification with “{done}” and “{snooze}”. An alarm fills the screen with “{stop}” and “{snooze}”, and falls silent by itself if nobody answers. |
| calendarGuideOpenOftenBody | unchanged |
| calendarGuideAssumeBody | With “{trackPresence}” on, every day counts as “{present}” until you mark it “{missed}”. “{assumeAbsent}” turns that around for things you rarely manage. |
| calendarGuideRailBody | “{dayRail}” is a thin strip at the left edge of a day with one mark per tracked event. Turn it on in “{settingsRow}”, under “{appearance}”; each event can then choose “{railAuto}”, “{railAlways}” or “{railNever}”. |
| calendarGuidePerDayBody | A repeating event shares one description across its days. Turn on “{perDay}” and, above the description, “{thisDay}” writes for that day alone. |
| calendarGuideCategoryBody | Every event has a category — the “{category}” row under its name — which gives it its colour and icon. Create your own at the bottom of that list. |
| calendarGuideCatChangeBody | Tap a category in the list to change its icon or colour. The built-in ones keep their names; your own can be renamed. |
| calendarGuideCatAlertsBody | Inside a category, “{addAlert}” sets an alert every event in it gets automatically. An event can switch it off for itself with “{categoryAlerts}”. |
| calendarGuideFiltersBody | A filter hides, it never deletes. If events seem to be missing, open the funnel and tap “{reset}”, then “{apply}”. |
| calendarGuideOverviewBody | “{overview}” in the title menu shows the months as tiles (“{year}”) or everything in a period as one list (“{list}”). The arrow at the top left brings you back. |
| calendarGuideSettingsBody | unchanged |
| calendarGuideLanguageBody | In the main menu (three lines, top left): “{language}” switches the language and “{theme}” chooses light or dark. The text size follows your phone's font size. |
| calendarGuideOpeningBody | From the app's first screen, tap the menu button at the top left, then “{calendar}”. To come back here: the three dots on the calendar, then “{title}”. |
| calendarGuideBackBody | The arrow at the top left, or your phone's back gesture, returns to the previous screen. A sheet that slid up closes with its X, or by swiping it down. |
| calendarGuideNotesBody | ANTA is also a notebook: the folders and notes behind the main menu. An event can point to a note through “{linkedNote}”. |

A body whose placeholder list shrinks (`calendarGuideCategoryBody` loses
nothing; `calendarGuidePerDayBody` loses `{allDays}`;
`calendarGuideRingBody` keeps all three; `calendarGuideViewsBody` keeps
all three) changes its metadata block in all three ARBs together.

#### 8.3.8 The catalogue's call sites that change with the bodies

`calendarGuidePerDayBody(perDay, thisDay)`, `calendarGuideKindsTrickyBody(ends,
repeat)` (no `alsoBefore`), `calendarGuideKindsOnlyRepeatBody(trackPresence,
countOccurrences, skippedDays)` (no `skip`); every other kept row keeps
its arguments. The deleted rows leave `CalendarGuideTopic.rows` and the
`calendarGuideRow` ids they carried are no longer in the tree (a flow or
a test that named one moves per §7.5).

### 8.4 The second review's strings (§7.6; F1 lands 8.4.1–8.4.2, F2 8.4.3, F3 8.4.4)

Every label in quotes is a placeholder fed from the app's own key, as
every guide string is; the key named in parentheses after a placeholder
is the one it takes.

#### 8.4.1 The hub's practice rows (F1)

| key | en | de | ro |
|---|---|---|---|
| calendarGuidePagePractice (changed) | Practice calendar events | Übungskalender: Ereignisse | Calendar de exercițiu: evenimente |
| calendarGuidePagePracticeCaption (changed) | A calendar that saves nothing. Add, change and delete freely. | Ein Kalender, der nichts speichert. Füge hinzu, ändere und lösche nach Belieben. | Un calendar care nu salvează nimic. Adaugă, modifică și șterge în voie. |
| calendarGuidePagePracticeFiltering | Practice calendar filtering | Übungskalender: Filter | Calendar de exercițiu: filtre |
| calendarGuidePagePracticeFilteringCaption | The same calendar, fuller. Hide things with the funnel and bring them back. | Derselbe Kalender, voller. Verstecke Dinge mit dem Trichter und hol sie zurück. | Același calendar, mai plin. Ascunde lucruri cu pâlnia și adu-le înapoi. |

#### 8.4.2 The filtering lesson (F1)

The tour, in order; the band shows one line at a time (D47):

| key | en | de | ro |
|---|---|---|---|
| calendarGuideTourFilterOpen | Tap the funnel at the top right: it hides things you do not need. | Tippe auf den Trichter oben rechts: Er versteckt, was du nicht brauchst. | Atinge pâlnia din dreapta sus: ea ascunde ce nu-ți trebuie. |
| calendarGuideTourFilterCategory {categories} (calendarCategories) {apply} | Tap “{categories}”, untick one, then “{apply}”. | Tippe auf „{categories}“, wähle eine ab, dann „{apply}“. | Atinge „{categories}”, debifează una, apoi „{apply}”. |
| calendarGuideTourFilterTrait {onlyShow} (calendarFilterOnlyShow) {apply} | Open the funnel again: try “{onlyShow}”, then “{apply}”. | Öffne den Trichter erneut: Probier „{onlyShow}“, dann „{apply}“. | Deschide pâlnia din nou: încearcă „{onlyShow}”, apoi „{apply}”. |
| calendarGuideTourFilterReset {reset} (calendarFilterReset) {apply} | In the funnel, tap “{reset}”, then “{apply}”. | Tippe im Trichter auf „{reset}“, dann „{apply}“. | În pâlnie, atinge „{reset}”, apoi „{apply}”. |
| calendarGuideTourFilterDone | Everything is back. A filter only hides, it never deletes. | Alles ist wieder da. Ein Filter versteckt nur, er löscht nie. | Totul e la loc. Un filtru doar ascunde, nu șterge niciodată. |

(The first draft's lines — "…: its events leave the grid", "…or
“{priority}”…", "The number on the funnel counts your filters…" — ran to
129 German characters and would have made the band three rows at 1.0;
the F1 review's finding 1, cut 2026-10-30.)

The six events the filtering seed adds to §8.2 table 6's (ids
`guide-demo-<slug>`; categories continue the cycle; every date relative
to today):

| key | en | de | ro | shape |
|---|---|---|---|---|
| calendarGuideDemoEventPilates (was Gym until the F1 review — D55) | Pilates | Pilates | Pilates | weekly on two weekdays other than today's, 07:00–08:00, presence tracked, P2, last week's two marked present and the most recent one missed |
| calendarGuideDemoEventPiano | Piano lesson | Klavierstunde | Lecția de pian | weekly on one weekday, 16:00–16:45, started ten weeks ago and ended two weeks ago (Not ended hides it) |
| calendarGuideDemoEventInsurance | Car insurance | Kfz-Versicherung | Asigurarea mașinii | yearly, all day, start three years ago on today + 15's month and day, counting from 0 (Counted) |
| calendarGuideDemoEventTax | Tax return | Steuererklärung | Declarația de venit | one-time, today + 20, all day, P1, with the description below |
| calendarGuideDemoEventTaxNote | Papers are in the blue folder. | Die Unterlagen sind im blauen Ordner. | Hârtiile sunt în dosarul albastru. | the Tax return's description |
| calendarGuideDemoEventLunch | Team lunch | Mittagessen mit dem Team | Prânz cu echipa | one-time, today + 4, 12:30–13:30 |
| calendarGuideDemoEventPlants | Water the plants | Blumen gießen | Udă florile | every third day from today − 30, all day, P5 |

#### 8.4.3 The screen page's cards (F2)

| key | en | de | ro |
|---|---|---|---|
| calendarGuideCardGrid | The month grid | Das Monatsraster | Grila lunii |
| calendarGuideCardPanel | The panel under it | Der Bereich darunter | Panoul de sub ea |
| calendarGuideCardOverview | The overview | Die Übersicht | Sumarul |
| calendarGuideCoachOverviewMode {year} (dayListModeYear) {month} (dayListModeMonth) {list} (dayListModeList) | Tap “{year}”, “{month}” or “{list}”: three ways to see the same events. | Tippe auf „{year}“, „{month}“ oder „{list}“: drei Arten, dieselben Ereignisse zu sehen. | Atinge „{year}”, „{month}” sau „{list}”: trei feluri de a vedea aceleași evenimente. |
| calendarGuideCoachOverviewPeriod | The arrows step back and forward; the button between them returns to today. | Die Pfeile blättern vor und zurück; die Taste dazwischen führt zu heute zurück. | Săgețile dau înainte și înapoi; butonul dintre ele te aduce la azi. |
| calendarGuideViewsBody (changed; {month} (calendarFormatMonth) only — `calendar` and `overview` placeholders retired) | If the days shrink to one or two rows, the title menu was switched: pick “{month}” there again. | Wenn die Tage auf ein oder zwei Reihen schrumpfen, wurde im Titelmenü umgeschaltet: Wähle dort wieder „{month}“. | Dacă zilele se restrâng la unul sau două rânduri, s-a schimbat vederea din meniul titlului: alege din nou „{month}” acolo. |

The screen card keeps `calendarGuideCoachScreenTitle` and
`calendarGuideCoachScreenMore`; the panel card takes
`calendarGuideCoachScreenPanel` as it is.

#### 8.4.4 The fasting page (F3)

| key | en | de | ro |
|---|---|---|---|
| calendarGuidePageFasting | Fasting days | Fastentage | Zilele de post |
| calendarGuidePageFastingCaption | Orthodox, Catholic, Muslim or Jewish fasts on the grid and in the day panel | Orthodoxe, katholische, muslimische oder jüdische Fastentage im Raster und im Tagesbereich | Posturile ortodoxe, catolice, musulmane sau evreiești în grilă și în panoul zilei |
| calendarGuideFastingLead | The calendar can mark the fast days of your tradition, with each day's rule. | Der Kalender kann die Fastentage deiner Tradition markieren, mit der Regel jedes Tages. | Calendarul poate marca zilele de post ale tradiției tale, cu rânduiala fiecărei zile. |
| calendarGuideCoachFastingTradition (reworded with D67, 2026-10-30; the first draft said "Turn on a tradition below: its fast days get a tint on the grid and a row in the panel.") | Pick a tradition under the grid: its fast days get a tint. | Wähle unter dem Raster eine Tradition: Ihre Fastentage werden getönt. | Alege o tradiție sub grilă: zilele ei de post se colorează. |
| calendarGuideCoachFastingStyle {appearance} (fastingAppearanceTitle) | Tap “{appearance}” to show them as a tint, a bar or a bold day number. | Tippe auf „{appearance}“, um sie als Tönung, Balken oder fette Tageszahl zu zeigen. | Atinge „{appearance}” ca să le arăți ca nuanță, bară sau număr îngroșat. |
| calendarGuideCoachFastingPractice {myPractice} (fastingScheduleTitle) | Tap “{myPractice}” to keep only the weekdays you fast on. | Tippe auf „{myPractice}“, um nur die Wochentage zu behalten, an denen du fastest. | Atinge „{myPractice}” ca să păstrezi doar zilele săptămânii în care postești. |
| calendarGuideFastingWhereTitle | Where it is switched on | Wo es eingeschaltet wird | Unde se pornește |
| calendarGuideFastingWhereBody {calendarSettings} (calendarSettingsRow) {fastingSection} (fastingSectionTitle) | “{calendarSettings}” → “{fastingSection}”, one switch per tradition. Several can be on at once, each with its own look. | „{calendarSettings}“ → „{fastingSection}“, ein Schalter je Tradition. Mehrere können zugleich an sein, jede mit eigener Darstellung. | „{calendarSettings}” → „{fastingSection}”, un comutator pentru fiecare tradiție. Mai multe pot fi pornite deodată, fiecare cu aspectul ei. |
| calendarGuideFastingRulesTitle | What the row says | Was die Zeile sagt | Ce spune rândul |
| calendarGuideFastingRulesBody | The row names the fast and the day's rule: strict, wine and oil, fish, dairy, or dawn to sunset. The dates follow the common printed calendars; Muslim dates can differ by a day from the moon sighting. | Die Zeile nennt das Fasten und die Regel des Tages: streng, Wein und Öl, Fisch, Milchprodukte oder von der Morgendämmerung bis zum Sonnenuntergang. Die Daten folgen den üblichen gedruckten Kalendern; muslimische Daten können um einen Tag von der Mondsichtung abweichen. | Rândul numește postul și rânduiala zilei: post aspru, dezlegare la vin și ulei, la pește, la lactate, sau de la răsărit până la apus. Datele urmează calendarele tipărite obișnuite; datele musulmane pot diferi cu o zi față de observarea lunii. |
| calendarGuideFastingPracticeTitle | Your own practice | Deine eigene Praxis | Rânduiala ta |
| calendarGuideFastingPracticeBody {myPractice} (fastingScheduleTitle) {applyTo} (fastingWeekdayScopeTitle) {allFasts} (fastingWeekdayScopeAll) | “{myPractice}” keeps only the weekdays you fast on, turns whole months off, and skips or adds single days. The long fasts still mark every one of their days unless “{applyTo}” is set to “{allFasts}”. | „{myPractice}“ behält nur die Wochentage, an denen du fastest, schaltet ganze Monate aus und überspringt oder ergänzt einzelne Tage. Die langen Fastenzeiten markieren weiter jeden ihrer Tage, außer „{applyTo}“ steht auf „{allFasts}“. | „{myPractice}” păstrează doar zilele săptămânii în care postești, oprește luni întregi și sare sau adaugă zile singure. Posturile lungi marchează în continuare fiecare zi a lor, dacă „{applyTo}” nu este pus pe „{allFasts}”. |
| calendarGuideFastingHideTitle | Hiding them for a while | Eine Weile ausblenden | Ascunderea lor pentru o vreme |
| calendarGuideFastingHideBody {fasting} (upcomingShowFasting) {apply} | In the funnel, turn off “{fasting}” and tap “{apply}”: the fast days leave the grid and the panel until you turn it on again. | Schalte im Trichter „{fasting}“ aus und tippe auf „{apply}“: Die Fastentage verschwinden aus Raster und Bereich, bis du es wieder einschaltest. | În pâlnie, oprește „{fasting}” și atinge „{apply}”: zilele de post dispar din grilă și din panou până le pornești din nou. |

The card's own controls take the app's labels as they are: the four
tradition names (`fastingTradition*`), `fastingAppearanceTitle`,
`fastingScheduleTitle`, `fastingOrthodoxGreatFasts`.
