# Calendar report — design record (2026-10-30)

**Status: COMMITTED — S0–S2 `08470643`, S3–S5 `350973b8` (2026-10-31,
committed and pushed by the lead on the owner's word); the designer's
spec is §4.8, the as-built notes per slice §7.1, the verification §8, what
was left §9** — proposed 2026-10-30; the same day the owner delegated every
lettered decision ("you have free will … the focus on this feature is
quality"), so the recommended option stands for each — D1–D24 in §3, the
lead's own D25–D47 as the build taught them; the build ran overnight on
Fable 5.1 as the lead with one Opus 5.5 implementer and one reviewer per
slice, a designer before the page, a design reviewer and two device
passes after. The mock:
https://claude.ai/artifact/Gk9fwraARua1r8hDecTWHe — the Report page for
October 2026 in light and dark, the lower cards scrolled in, the digest editor
with its one new row, the two notification states, the decisions and the
must-not-change list under the board. Redrawn on 2026-10-30 (live version
`1793372958-d166`): all five worked periods of §4.4 are on it — the training
month, the family month, the to-do week, Last week and Next week — with every
event list drawn as the per-category groups of W (open at four rows, "n more"
for the rest), plus the Period menu with its Last / Next entries, a monthly
notification with no routine in scope, and decisions M–X. Architecture and
performance: §4.7.
Session memory: `calendar-report-proposal-2026-10-30`.

Contents: §1 How to run this · §2 Why · §3 Decisions · §4 The spec (§4.1 the
three shapes of event, §4.2 the page, §4.3 the cards, §4.4 three worked
periods, §4.5 report digests, §4.6 copy, §4.7 architecture and performance,
§4.8 the designer's spec) ·
§5 Behaviour · §6 Facts from the tree · §7 Slices · §8 Definition of done ·
§9 Deferred.

## 1. How to run this

The prompt for the implementing session (Opus 5.5 at `high`; this record was
written on Fable 5.1 and that session ends here):

> Load `calendar-events`, `calendar-ui`, `ui-language`, `l10n`, `verify` and
> `delegation` (`drift-migrations` only if S4 turns out to need a migration —
> it should not, the digest cadence is a stored name). Open
> `docs/calendar-report-roadmap.md`: read §3 (the owner's answers, by then
> D-numbered), §4.7, §5 and §6 whole, then only the slice you are on in §7
> and its part of §4. If `git log` says the status line is stale, correct it first.
> Run the slices in order, one `implementer` and one `reviewer` per slice; the
> `designer` specifies the page before S2 and the `design-reviewer` checks it
> after; the `qa-runner` runs the device pass at the end of S3 and S4. The
> guide work (`docs/calendar-guide-page.md` §7) landed in `2f29b797` on
> 2026-10-30, so the overview's files are free; the report still adds beside
> the overview and never edits the guide's practice card or coach copy (a
> report topic for the guide is S5). The gate after
> every slice: `dart analyze lib`, the whole `flutter test`, `flutter gen-l10n`
> with `untranslated.txt` empty, §5's must-not-change list re-read against the
> diff. Check in at every slice boundary with the uncommitted file count and a
> ready commit; never commit unasked.

Before S0 the owner answers §3. The letters become `D1 … Dn` in §3's table with
the mock's URL beside the ones it settled; the mock is redrawn once if the
answers change the board.

## 2. Why

The owner asked on 2026-10-30 for "an analytics mode for the calendar to select
a week/month/year so that we can see events but from an analytical point of
view like a report", with the categories chosen, and for the same report to
arrive on a schedule "in combination with the alarm system", like a weekly
report; then, the same day, for the report to serve birthdays, to-dos and
"nice events" as well as training; and later that day for it to answer two
questions outright — "what do I do next week?" and "what did I do last
week?" — with hangouts and birthdays in the answer, in both tenses.

What the shipped calendar cannot do today:

- The overview **lists**; its only number is the one-line totals slot under the
  nav (entries per category). No hours, no attended-of-total, no previous
  period, no busiest weekday.
- A birthday's age and a program's "Week N" exist per row (the count label)
  but are never gathered: "three birthdays this month, Ana 32, Mihai 40" is a
  scroll, not a line.
- A to-do is a one-time event whose description may hold a task list; nothing
  counts the ticked boxes across a week.
- Digests look **forward** only (span = fire day + lead); nothing says what the
  week that just ended looked like.
- The calendar exports `.ics` only; sharing a period as text was deferred on
  2026-10-11.

Research facts that shaped the design are in §6; the ones not derivable from
the code are in the session memory.

## 3. Decisions

Lettered until the owner answers; the recommended option is first in each.
D-numbers are assigned on answering and nothing here is rewritten afterwards
(an amendment appends). A–L are on the mock; M–Q came with the second request
(birthdays, to-dos, outings); R–T with the third (the two questions); U–V with
the architecture and performance pass (§4.7); W–X with the fourth request
(fifty events are overwhelming: coalesce them into categories).

**Answered 2026-10-30 — delegated.** The owner handed every decision to the
lead ("free will", quality the one brief), so option (1) stands for each
letter and the D-numbers below are the letters in order: D1 = A · D2 = B ·
D3 = C · D4 = D · D5 = E (superseded by D23 / W: a header tap folds its group,
the bar's Categories picker narrows the scope) · D6 = F · D7 = G · D8 = H ·
D9 = I · D10 = J · D11 = K · D12 = L · D13 = M · D14 = N · D15 = O · D16 = P ·
D17 = Q · D18 = R · D19 = S (the Routines and Happened cards of S are
superseded by D23 / W; its Ahead rule — every shape, routines included, in
the past or current tense — stands) · D20 = T · D21 = U · D22 = V · D23 = W ·
D24 = X. The mock (live version `1793372958-d166`) settled D1–D12 and
D13–D24 as drawn; it is not redrawn. Amendments append as D25 onward.

| # | Question | Options (recommended first) and why |
| --- | --- | --- |
| A | Where the report lives | (1) **Its own page**, `CalendarReportPage`, the third entry of the title view menu beside Calendar and Overview, stamped `NavDestinationKind.calendarReport`, inheriting the overview's period and categories when opened from there. `AgendaDayListMode` is shared with the day-list sheet (two persisted keys) and the guide's practice card; `OverviewModeChips.modes` is drawn by the page and the guide card alike (guide D59); the coach copy says "three ways to see the same events". (2) A fourth overview mode — all of the above move, while the guide agent edits the same files. |
| B | Periods | (1) **Add This week and This month** to the Period menu (`OverviewPeriodChoice.thisWeek` / `thisMonth`, week start from `SettingsKeys.calendarWeekStart`); the report offers This week · This month · This year · Last 12 months · Last 90 days · Custom, **no All time** (the range scan clamps at 366 days and All time has no previous period). (2) Only the overview's five choices — a week is then a custom span every time. |
| C | Counting | (1) **Days after today never count** in the totals (caption "To 30 October"); an occurrence is a day (a two-day trip counts 2 — there are no multi-day events); tracked occurrences split attended / missed by `EventPresence.isMissed`; untracked ones count as events and hours; hours = durations of occurrences not missed; skipped days are already out of every scan and are named in the caption. (2) Count the whole period — every future tracked day reads missed under assume-absent. |
| D | Deltas | (1) **Plain text** in `onSurfaceVariant` ("+4 vs September"); a report has no "up is good" for every tile. (2) Coloured by direction. |
| E | Category row tap | (1) **Focuses the report on that category** (the Categories badge shows 1, the row group re-folds). (2) Opens the categories picker. |
| F | Trend caption | (1) **The busiest unit and the usual hour band** ("Most on Mondays · usually 18:00 – 19:30"; the band only from three timed occurrences). (2) No caption. |
| G | Missed rows | (1) **Carry the day panel's presence button** (D31 of the overview record), so "I did go on Tuesday" is fixed from the report and the report re-folds. (2) Read-only rows. |
| H | Empty cards | (1) **Not drawn**; Totals always is. (2) Drawn with an empty line. |
| I | The scheduled report | (1) **Two new `DigestCadence` values**, `weeklyReport` and `monthlyReport`, spanning the week or month that just ended; words written at arm time only when `now >= spanEnd`, else "Last week's report is ready"; a notification on the digest channel, no alarm tier (digests have none; alarm-tier digests stay deferred in `docs/category-alerts-and-digests-roadmap.md` §11). An older build decodes an unknown cadence as **disabled** (§3.4 of that record) — a `kind` key would make it fire as an upcoming digest. (2) A separate "report" entity — a second editor, a second planner, for the same rows. |
| J | Creating one | (1) **From the report's footer** ("Send me this report weekly / monthly", pre-filled with the report's categories) **and from the Alerts hub**. (2) Hub only. |
| K | Share | (1) **Markdown text through `shareExport`**, in a later slice (S5). (2) Never. (3) Also as a note in a folder. |
| L | Primitives | (1) **One new form primitive**, the meter row, in `form_rows.dart`; stat tiles and the column chart are calendar widgets under `ReportMetrics`. (2) Everything page-local. |
| M | To-dos and "done" | (1) **No Done flag.** A one-off is "happened" once its day has passed; its done-ness is the task list in its description — `[x]` / `[X]` ticked, every other state open — counted by the engine's one task grammar (`MarkdownListSyntax`), once per shared description or per occurrence under per-day scope; a Tasks tile and "3 of 4 tasks" on the row; ticking happens in the detail sheet the row opens. (2) Lift the presence gate for one-offs so the presence button reads Done — reverses a deliberate decision (`docs/presence-tracking-roadmap.md`, "Presence on one-time events") and assume-absent would mark every past to-do missed. (3) A `done` column: migration, backup, CRDT, a sheet button — a feature of its own, after the report. |
| N | The future inside the period | (1) **Split at today**: tiles and the Happened / Routines / Missed cards count to today; an **Ahead** card lists the rest of the period (ages via the count label, times, task counts), so "this month" says what happened and what is left. (2) Nothing after today anywhere (C alone). (3) Count the future into the tiles — misstates attendance. |
| O | Which tiles | (1) **Decided by the selection, not the period**: Events always; Attended + Missed when any event in the chosen categories tracks presence; Hours when any is timed; Tasks when any description holds a task item — so ◄ ► never reshuffles the grid (a tile reads "—" when the period has nothing for it). (2) By the period's data — fewer blanks, a grid that changes under the thumb. |
| P | Digest lines | (1) **One line per category, worded by its dominant shape** ("Gym · 4 of 4 · 5 h", "Birthday · 3 · Ana 32, Mihai 40, Ioana 7", "To do · 4 · 9 of 12 tasks"), the summary line first, `kDigestMaxLines` kept. (2) One line per event as drawn on the mock — overflows at five with any real selection. |
| Q | Over time | (1) **Drawn from `ReportMetrics.trendMinOccurrences` (4) happened occurrences** in the period; below it the Happened card is the story (three birthdays make no chart). (2) Always drawn. |
| R | Last and next, one tap | (1) **Four relative entries** in the report's Period menu — Last week · Next week · Last month · Next month — beside This week and This month; each is its This preset stepped once (`OverviewPeriod.stepped`, a custom span today), so nothing new is persisted and ◄ / ► keep stepping from there; like the overview's steps they are not restored across a relaunch (the report reopens on the base preset). The menu reads This week · Last week · Next week · This month · Last month · Next month · This year · Last 12 months · Last 90 days · Custom. (2) ◄ from This week — two taps for the question the owner asked most. |
| S | Who is in Happened and Ahead | (1) **Happened holds repeats and one-offs; Ahead holds every shape, routines included.** Looking back, a routine's days are the Routines card's aggregate ("Gym · 4 of 5 · 4 h") and a month would list fourteen gym rows; looking ahead there is nothing to aggregate yet, and "Gym · 18:00 · Mon 2 Nov" is the plan. Both chronological, oldest first, day-grouped as the overview's rows are; the footer's Show as list is the full day-by-day diary. (2) Happened lists every occurrence — thirty training rows in a month. (3) Routines' kept days in Happened for periods of a week or less only — one more rule to explain. |
| T | A future period reads as a plan | (1) **Tense follows the period.** Past or current: Totals (O's set) · By category · Over time · Routines · Happened · Missed · Ahead. Wholly future (Next week, Next month, a custom span ahead): Totals with **Planned · Hours · Tasks** only · By category · Ahead; the band's subtitle "10 planned · 9 h 30" instead of "31 events · 3 missed"; deltas against the previous period of the same length in both tenses (next week vs this week). T refines O: the tile set is per selection within a tense; stepping across today changes the tense once, together with the caption. (2) One shape for every period — "Attended —, Missed —" on a plan. |
| U | Architecture | (1) **The house layering: `CalendarReportPage` → `CalendarReportBloc` → `CalendarReportService` → pure `CalendarReportBuilder`.** The bloc routes `ReportRequested(period, categories)`, steps, a category focus and `ReportRefold` (on the calendar revisions) and holds `ReportReady(model)` / `ReportFolding(previous)`; the service turns the facades into samples, memoizes folds by key and lends the planner the same pure path; so the page, the digest words and the Markdown share read **one `CalendarReport` model** and never disagree. §4.7. (2) Page-local compute as the overview does — three places that compute one number. |
| V | Caps | (1) **By category folds past `ReportMetrics.maxCategoryRows` (7)** into one "n more categories ›" row (a sub-sheet with the rest); **Happened and Ahead stop at `ReportMetrics.maxListRows` (200)** with a "Show as list ›" row; Routines keeps its top three + All. A card never grows with the data — the overview's List is the unbounded view, and past seven classes the dataviz rule says a table. (2) No caps — forty categories make a forty-row card. |
| W | Fifty events | (1) **Categories is the one event list.** One foldable group per category in scope (descending count, folded past seven groups per V); the header is today's By category row — glyph, name, meter, "count · hours · n missed" — plus a fold glyph (▾ open, ▸ closed). A group opens at `ReportMetrics.groupPreviewRows` (4) rows: routines first as aggregates ("Gym · 8 of 10 attended · 8 h"), then the period's repeats and one-offs as dated rows, oldest first; "n more ▾" shows the rest (X). A header tap closes or opens its group; the fold state lives for the visit, never persisted. Missed and Ahead are built from the same groups; in the future tense the groups are the plan, so there is no separate Ahead card. Supersedes E's focus-on-tap (the bar's Categories picker narrows the scope) and the separate Routines and Happened cards of S. (2) Groups closed by default with the counts in the header — compact, but the page says nothing until a tap. (3) Flat lists capped at 200 (V alone) — fifty one-offs are fifty rows. |
| X | Seeing the rest of a group | (1) **"n more ▾" expands the group in place; "Show less ▴" folds it back to four**; the page's one scroll carries the growth and nothing above the tapped row moves. A fixed four-row slot that scrolls inside the page is the nested-scroll trap this app hit on 2026-10-30 (`GuideStageSlot` had to forward a finger's overscroll), it hides how many rows exist, and a thumb cannot tell which list it is dragging. (2) A four-row slot scrolling in place on the `GuideStageSlot` precedent — the owner's sketch. (3) "n more ›" opens the category's events in a sub-sheet — one more level, no page growth. |

**D25 (2026-10-30, the lead, amends D2 / D18 before S0).** This week and
This month are calendar-unit periods beside the year — `OverviewWeekPeriod
(start)` and `OverviewMonthPeriod(year, month)` mirroring `OverviewYearPeriod`
— not `OverviewRollingPreset` values. Why: a rolling preset ends today and
steps by its own length, which would land "Last month" from October on
31 Aug – 30 Sep; a calendar unit steps to its true neighbour (1–30 September,
then August), so D18's "the This preset stepped once" is a real week or month
and ◄ / ► keep landing on real ones. They encode as `thisWeek` / `thisMonth`
(the `thisYear` grammar) only while they hold today — a paged week or month
is a look and encodes null, as a paged year does — and the saved views store
them the same way (rolling kind while they hold today, pinned otherwise).
`decode` and `fromChoice` take the week start (`SettingsKeys.calendarWeekStart`)
for This week; `menuChoice` and `followingToday` need no new input (a week
holding today is This week; a page left open advances by whole weeks). §8's
last bullet reads `thisWeek`, not `preset:thisWeek`, accordingly.

**D26–D30 (2026-10-30, the lead, before S1 — the counting rules the worked
periods of §4.4 left open; where a sketch disagrees, these win).**

- **D26 Events counts what happened.** The Events tile and a group header's
  count are occurrences to today that were not missed (every kept tracked
  day plus every untracked occurrence); Missed is its own number, never
  inside Events. So the group headers always sum to the Events tile — a
  property the owner can check by eye. Period 4's sketch therefore reads
  Events 10 (its "11" counted the missed day twice).
- **D27 Tasks per text the user sees.** A shared-scope event's description is
  counted once per event in the period; a per-day-scope event counts each
  counted occurrence's effective text (`descriptionFor`: the override, else
  the shared text — what that day shows). The parse is `countTasks(text)` in
  `lib/utils/task_count.dart` over `MarkdownListSyntax.parse` per line, with a
  small LRU keyed by the text, so a shared text is parsed once however many
  days show it (§4.7's cache, placed where every caller gets it).
- **D28 Deltas compare like with like.** Past tense: the whole previous
  period of the same kind (`stepped(-1)`). Current tense: the previous period
  counted to the same elapsed length (October 1–30 against September 1–30),
  never a partial month against a whole one. Future tense: the plan against
  the previous span's every occurrence, missed ones included (they were
  planned). Every tile carries its previous value; the page prints the delta
  as D4 says.
- **D29 The trend's caption facts.** Busiest weekday = the weekday with the
  most happened occurrences, none on a tie; the usual band = the median start
  minute and the median end minute of the timed happened occurrences, from
  `ReportMetrics.trendMinTimedForBand` (3) of them, the end only when
  durations exist. Buckets: a span up to 31 days per day, up to 182 days per
  week from the app's week start, longer per month; buckets cover the whole
  span, the ones after today at zero (the month so far reads as a month).
- **D30 The service is owned, not a singleton.** `CalendarReportService` is a
  plain class holding the memo (`memoFolds` reports, twice that many totals,
  keyed on span, category ids, the three revisions and today): the report
  bloc owns one for its page's life, the digest planner's caller one per
  reconcile, so nothing has to be registered for `DatabaseLifecycle.reset`
  and no memo outlives the data it was folded from. The previous period's
  tiles are a totals fold memoized per span, so ◄ then ► re-folds nothing.

**D31 (2026-10-30, the lead, from the S1a review).** Today's tracked
occurrence without an explicit presence mark is **pending**, not missed and
not attended: `assumesAbsentOn` treats today like a past day (no wall clock
anywhere in presence reads), so a Monday-morning "This week" would otherwise
count tonight's gym session as missed before it could happen. The sampler
flags it (`ReportSample.pending`, from `EventPresence.marksFor(id)[today] ==
null`), the builder keeps it out of every tile and the Categories and Missed
groups and lists it under Ahead; an explicit mark today counts at once; an
untracked occurrence today happened. The day panel and the grid keep showing
`isMissed` as they do — the report is the one surface that speaks in the
past tense and so must not grade a day that is still running. Also from
that review: a tracked `SpecificDatesRecurrence` is a routine (the presence
gate wins over §4.1's one-off column); `ReportInput.overrides` carries every
per-day text of the selection so the Tasks tile never flickers under ◄ / ►;
the trend has at most 31 day, 27 week or 14 month columns (a partial first
week, a 365-day span's thirteenth month); V's folds and caps are the page's —
the model is complete and the share prints it whole; the usual band's two
medians come from the same samples (timed with a duration).

**D32–D34 (2026-10-30, the lead, from the S1b review).**

- **D32 The allowlist is the overview's.** The report scopes events by the
  **stored** `categoryId`, as `EventAgenda.passesEventFilters` does for the
  overview's List and `DigestPlanner.plan` for the digests — the surfaces that
  hand the category set over — so a report opened from the overview counts
  exactly what that overview lists; grouping and drawing resolve the id
  (unknown → `other`), as every row does. The memo key also carries
  `PublicHolidays.revision`: workday and holiday rules read that facade, which
  changes with no bloc event (the calendar bloc folds it as a generation for
  the same reason), and the report bloc re-asks on resume.
- **D33 A long span keeps its end.** A Custom span over 366 days is clamped to
  its **last** 366 days — at pick time by the page and again by the service
  as the safety net — so a span that holds today keeps today and its Ahead;
  the band titles the clamped span.
- **D34 One memo.** `CalendarReportService` keeps one LRU of `memoFolds` whole
  reports; the separate totals memo of D30 is dropped — a current span's own
  totals are keyed on today's counted range, which a later step never asks
  for except at a month's end, and `fold` folds them itself. A miss costs one
  sampling and fold of the span plus one sampling and totals fold of the
  previous span (about 50 ms + 50 ms worst case on the 366-day, 50-event
  fixture); ◄ then ► is a report hit, `foldCount` unchanged. `skippedDays`
  counts a skip only where the rule would otherwise produce an occurrence
  (`CalendarEvent.wouldOccurOnUtcDay`, the skip-free half of
  `occursOnUtcDay`), because a skip row outlives a rule change.

**D35 (2026-10-30, the lead, before S2 — what the report remembers).** The
report keeps its own period and category set, `SettingsKeys.reportPeriod`
(the overview's `encode` grammar: `thisWeek` / `thisMonth` / `thisYear` /
`preset:<name>`, a stepped or custom span null — the report reopens on the
base preset, D18) and `reportCategoryIds` (empty = every category, the
overview's allowlist rule), defaulting to This month and every category,
loaded in one statement with the week start. Opened from the overview's view
menu it starts on that overview's shown period and categories for the visit
(a `ReportLook` carried in process by `AppNavigator.toCalendarReport`, the
`pendingOverviewLook` idea without the notifier), persisting the period only
when it is a persistable kind and the categories always; opened from the
calendar page or restored at launch it reads its own keys. A Custom pick
over 366 days is clamped to its last 366 days at pick time (D33). The footer's
Send row reads "weekly" on a week period and "monthly" otherwise, and stays
disabled at 38 % until S4 wires it; Share stays disabled until S5.

**D36 (2026-10-30, the lead, from the S2a review).** (1) The three calendar
views never stack: a view-menu switch pops back to the stamped view when it
sits beneath with only calendar views (calendar · overview · report) above
it, and pushes otherwise (`returnOrPush` collapsed only onto the page
directly beneath, which held for two pages); an alert tap keeps a report
above the calendar as it keeps an overview. (2) A relative row (Last / Next
week or month) persists its **base** preset (D18: the report reopens on This
week / This month); a Custom pick clears the key as the overview's does. (3)
"against …" names what was compared: the whole previous period's name in the
past and future tenses, the counted part's span ("against Sep 1 – 15") in
the current tense (D28) — `CalendarReport.previousCounted` carries it. (4)
The empty caption is composed, never conjugated: "{period} · Nothing
happened" (a period label is a noun phrase that no preposition fits in three
languages). (5) Durations under an hour read in minutes ("40 min", "+5
min"); from an hour, decimal hours. (6) A fold yields a real frame
(`SchedulerBinding.endOfFrame`, injectable for tests) before folding; a fold
that throws logs and re-emits the last Ready, never a dim that stays. (7) A
pick equal to the shown period still re-emits Ready, so `home` and the Today
slot follow. (8) The overview's Month mode hands the report its month, not
its year. (9) While Folding, everything derived from a report (subtitle,
caption, Show as list) describes the report it came from; the band's title
alone shows the new pick. (10) `ReportLook` lives in `lib/models/`, so the
bloc never imports the navigator. (11) The en counted-to date keeps the
app's month-first grammar ("To October 30"), as `dateSpanLabel` does.

**D37 (2026-10-30, the lead, after the S2a fix pass — the Totals grid).**
The built page measured §4.8's widest template at 132.9 for "888 von 888"
(de 1.0) and 158.4 for "888 of 888" (en 1.3) against a half-card budget of
131.5 at 360, not the 107.2 / 125.0 the spec assumed, so German at default
scale and English at 1.3 would fall to one column — five stacked tiles, a
490 dp card as the first screen. The column rule becomes two-stage, still
decided by templates and never by a value (C): (1) "888 of 888" fits half
the card → two columns, Attended and Tasks read "21 of 24" in the value;
(2) else "888" fits half → two columns and the "of" part moves to the
detail line ("of 24 · 88 %", "of 12 · 3 open" — the common stat-tile
shape); (3) else one column with the full value. The design-reviewer checks
the shape after S3. Also noted: the band measures 78 / 97 / 146, not §4.8's
52 / 64 / 146, because its title box is measured over the cross-year span
templates that wrap at 360 even at 1.0 — the overview's List nav has the
same box; it is constant through a step and a refold, which is the rule
that matters, and the 26 dp of air at 1.0 is an app-wide item for the
overview's record (§9). From the S2b review: the axis fit test subtracts the
label gap (a label passing the fit and then thinned left "This year" at 360
with seven of twelve months); the spoken peak takes one phrase per unit;
`FormMeterRow` treats a non-finite fraction as zero; a missed part never
vanishes under the 2 dp gap; axis labels are measured with the bold-text
setting and sit in a shrink box like the meter row's caption; column edges
and hairlines snap to device pixels.

**D38 — the S3a review's rulings (lead, 2026-10-30, after the Opus review
of the group rows).** The spoken hours are the shown figure read back
(`hoursFigure`, the whole-hours plural when it parses as an integer):
`(hours × 10).round()` disagreed with `NumberFormat('0.#')` at .x5 values —
537 min showed "8.9 h" and spoke "9 hours", 123 min showed "2 h" and went
through the decimal key ("20 ore" for ro's "20 de ore"). A dated row's day
is an ARB template over `DateFormat.E` / `.d` / `.MMM` (`reportRowDay`,
`reportRowDayMonth`): the raw pattern `E d` gave de "Do. 8" where German
writes "Do., 8."; no year — the one-day overlap of a 366-day span is
deferred (§9). A dated row's subtitle is composed by the report — day ·
start time · duration · count label · "n of m tasks" — never the day panel's
tail, which carries a time range, "All day", the recurrence word, the count
label first and the removed-after-alert note; `EventSummaryProvider`
supplies the icon, the colour and the title only. `reportAttendedOf` is a
plural on `total` (ro "din 25 de prezențe"). `ReportRoutineRow.latestDay`
(the latest attended day, else the latest counted occurrence) is where a
routine aggregate's tap opens the detail sheet (V). The in-group "Show as
list" row gets `report-group-list-<card>-<id>` and a spoken label. Every
row carries a `ValueKey`, so a group's `SliverList` (its own since S3b) maps
rows across a fold through `findChildIndexCallback` and a later header never
inherits an earlier one's rotation state. A missing event (impossible — the builder
dereferences `events[id]!`) is asserted and skipped the same way for both
row kinds. A category whose counted occurrences were all missed keeps its
Categories group ("0 · 2 missed", one "0 of 2 attended" row): the group
tells the story and D26's sums hold. §4.3's "rows faded 0.35" on Missed is
superseded by §4.8 G (unfaded — 0.35 measured 2.17:1), and the widget ships
as `ReportGroupRows` because the model already owns the name
`ReportCategoryGroup`.

**D39 — the S3b review's rulings (lead, 2026-10-31, after the Opus review
of the cards on the page; no blocker, two defects, twelve nits).** *Nothing
moves under the finger at the end of the page*: a shrink of the content near
`maxScrollExtent` — a Missed row marked, a whole group or the MISSED card
leaving, a long group closed by its header — made the viewport clamp the
offset and slide everything down; the page ends in a **slack sliver** that,
when armed before such a frame, takes exactly the extent the clamp would
have taken (`scrollOffset + remainingPaintExtent` at its layout) and only
ever shrinks afterwards, so scrolling up drains it and scrolling down stays
bounded; armed on a header close, on "Show less" and on a refold the page's
own mark caused (as built: the same look only; D40 narrows it further to a
pending mark). The two child-row kinds are pinned to one exact
height, so the "Show less" jump may read any built child row. The in-group
Show as list on the Ahead card hands the days after the counted end
(`countedTo + 1` to the span's end); Categories and Missed hand the folded
span (the overview's Missed only narrows it there — `OverviewLook` stays
`(start, end, categoryIds)`, §5). The presence mark clicks like the
overview's and ignores a second tap on a row whose mark has not folded yet.
The recording bloc in the page suite emits what production emits (the same
list, both revisions bumped). The clamp test, the "nothing above moves"
test and the presence test were tautological at offset 0 and are now asked
at a scrolled offset, after `pumpAndSettle`, and against a rect above the
tapped row. Recorded, not changed: a disclosure row's element is kept only
when the old index 5 was built, positions hold either way.

**D40 — the S3c review's rulings (lead, 2026-10-31; two medium findings,
both on the slack).** The slack is armed only for a shrink the page itself
caused at or below the viewport: a header close, "Show less", and a refold
while one of the page's own marks is pending — never for another same-look
refold (an event deleted or re-categorised in the detail-sheet trip's
editor, a category deleted in settings), where the removed extent may lie
*above* the leading edge and an armed slack would lift every visible row by
it and open blank ground below; the clamp's small slide on return from such
a trip is accepted. A look change (a step, a pick) *releases* the slack
(`remembered = 0`), so a shorter period never inherits blank ground under
its footer. A shrinking bottom clearance (the keyboard closing under a
sheet's editor, which had drained slack through the min rule) arms, because
that shrink is below the viewport by construction. The bookkeeping lives in
the bloc listener, never in `build`. Recorded, not changed: while the slack
drains, `maxScrollExtent` moves each frame and a fling restarts its
simulation per frame (bounded by the slack; a device check); a failed
presence write leaves the row quiet until the next Ready; an unrelated
Ready may clear the in-flight set early (the write is idempotent). The page
and the sub-sheet share one group-stack implementation
(`report_group_stack.dart`: the folds, the per-group slivers, "Show less",
the slack sliver), lifted from the page in S3d.

**D41 — report digests (lead, 2026-10-31, S4a/S4b).** `DigestCadence.weeklyReport`
/ `monthlyReport` are appended (the names are the stored value; `fromName`
keeps falling back to monthly, so an older build reads them as
monthly-but-disabled-and-unreadable, §3.4 of the digests record); they fire
on the weekly / monthly schedule and `spanFor` gives the last whole week
(from the user's week start) or the calendar month that ended *before* the
fire day, never containing it; `leadDays` is kept in the payload and never
read. At arm time the scheduler folds the report through one
`CalendarReportService` per reconcile pass (D30) only when date-only now is
past the span's end, else the body is the one line "Last week's / month's
report is ready" and the next reconcile rewrites it (the arm signature
hashes the text); a presence or skip write requests `reconcileAllQuietly`
unawaited after its chain, gated on an enabled report digest existing, so a
user without one pays nothing. The words (P): the summary line "{categories}
— {attended} of {total} attended · {hours} · {missed} missed" (or "{n}
happened" without routines), then one line per category in the report's
order worded by its dominant shape — routine "{attended} of {total} · {hours}",
repeat "{count} · {titles}", one-off "{count} · {ticked} of {total} tasks" —
`kDigestMaxLines` kept, every number through `ReportLabels` (U). The payload
gains the additive `pg` key (`page: report`); `OpenOverviewIntent` routes it
to `AppNavigator.toCalendarReportLook` (a week span → `OverviewWeekPeriod`, a
calendar month → `OverviewMonthPeriod`, else custom) published on
`pendingReportLook`, the overview-look twin, which the report page serves
through `ReportLookArrived`; an absent key lands on the List as today. The
editor's Shows row (Upcoming · The week just ended · The month just ended)
drives the cadence; under a report Shows the Every row reads the implied
cadence disabled and Covers is disabled, On and At stay (S4b).

**D42 — the S3d review's rulings (lead, 2026-10-31; one medium).** The
keyboard arm re-measured the slack's whole reach, which lifts the visible
rows when the content above the viewport shrank in the same layout (an
offstage report under Settings hears a keyboard and a deletion, then comes
back; an editor saved while the keyboard is still closing): the slack now
takes the clearance as an input and *credits* only the clearance's shrink
(`remembered = min(remembered + max(0, laid − clearance), reach)`), no arm
on a clearance change. A mark's arm is keyed, not counted: a same-look
report arms when a pending `(eventId, day)` was among the previous report's
Missed rows and is absent from the new one, and only those keys are cleared
— a failed write or an unrelated Ready no longer arms or disarms the wrong
refold. A release wins over an arm in the same update. The sub-sheet shares
the page's `ReportGroupFolds` (the state is per visit, X, and the sheet's
ids never overlap the page's seven). A sheet row's second tap in one frame
is dropped (`Navigator.pop` twice would pop the report page — the day list
sheet has the same exposure; the owner's call). The slack's counts ride a
`ValueNotifier` under a `ValueListenableBuilder`, so a fold rebuilds the
slack, not every card. Tests for each, plus the sheet's own slack and its
`largest` meter.

**D43 — the S4a review's rulings (lead, 2026-10-31; two medium).** The
numbers are folded from the span's *last day* on (date-only now ≥
`span.end` — I's "now >= spanEnd" read literally), not only after it: with
"after" a Sunday-evening mark never produced Monday's words unless a pass
ran between midnight and the fire minute, which only a launch, a resume or
an edit starts; on the last day a marked occurrence counts and an unmarked
one is pending (D31), and the next pass — a mark, a launch — rewrites the
words through the signature. No midnight timer (the scheduler has none;
§9). The summary says "{attended} of {total} attended" only when the
Attended tile counts something, else "{n} events" (the builder emits the
tile for any routine in the *selection*, so a paused routine beside three
birthdays read "0 of 0 attended" and never named the three); a routine
line's hours are its routine rows' minutes, not the group's; the summary's
"{categories} — {facts}" is an ARB template; counts go through
`ReportLabels`' number formatting. `digestEntries` (the hub) and the
editor's caption plan read the week start too, so a Sunday-start user's
row describes the span that is armed. The arm-time words are inside the
scheduler's try with the fold (a throwing `ReportLabels` must not abort the
pass and strand the entries after it); `page` joins `digestArmSignature`.
Recorded as built: "{n} events" for "{n} happened"; the repeat line lists
each title once and drops the count labels (P's "Ana 32" — the title
already names whose day it is and a notification line is short); the title
says "3 categories" past two names as every digest does; `reportPeriodOf`
makes any seven-day span a week period whatever the week start (harmless
after a week-start change between arm and tap). The editor's On row and
anchors cover the report cadences (S4b). Tests: the page's served look end
to end, a second reconcile after a mark re-arming new words, the fold
fallback, a Sunday week start and a monthly report through the scheduler,
the seven-day alignment of every planned week.

**D44 — the design review's rulings (lead, 2026-10-31; Opus
design-reviewer over ~130 real-font renders, 24 cells of Period 1 and seven
more states; every §4.8 number confirmed except those noted).** Fix: a
route pushed in the frame right after an unsettled scroll jump at de 2.0 on
412 wide drops one semantics frame (`flushSemantics` → `geometry!` null on
a sliver of the page) — bisect the page's slivers (the slack sliver first)
and pin it with a no-settle tap in the page suite at that cell; the Hours
tile speaks "45 h" — its spoken value and delta go through `hoursSpoken`
like the headers; de says "Ereignisse" on the tile and "Termine" everywhere
else — "Termine"; a group whose facts are a bare count ("1") says "1 event";
"6 less than" for a count is "fewer" (hours keep "less"); the Send rows'
de / ro labels are shortened so de 2.0 on 360 stays at two lines ("Bericht
wöchentlich senden"); the disclosure row's trailing glyph is a named part,
not a raw `Icon`. Accepted and recorded: rows wrap at 2.0 and grow (the
disclosure and cap rows 92 at 2.0, the Send row 92–132) — constant per
state, never at runtime; the chart card's height follows its caption's
wrap (304 at en 2.0 with a 12-hour range, 196 at de 1.0 single-series) —
constant per state, §4.8's 268 is one caption's number; the chart's missed
part in dark at 1.74:1 (the legend, the Missed tile and the Missed card
carry it — a device look); the band's two-line de 2.0 title with its ▾ at
the edge (the overview's nav); "To October 30" beside today's pending
occurrence under Ahead as "Fri 30" (D31 — the row's time says the rest);
the 38 % rows failing the text-contrast matcher (inactive controls are
exempt). The device bucket (TalkBack phrasing, ink clipping at the card
radius, ro, the AOSP 200 % curve, gesture-bar clearance, the refold's feel,
the fling after "Show less") goes to the final device check.

**D45 — the S4b review's rulings (lead, 2026-10-31; two medium).** A
report folded on the span's last day folds *as of the day after it*
(`today: spanEnd + 1`): on the last day itself an unmarked assume-present
session is pending (D31) and most users never mark the sessions they went
to, so a Sunday pass would have armed Monday's words one session short with
nothing to refold them; folded from the fire's side, the event's own
default decides the last day exactly as a pass after midnight would, and a
later mark still rewrites the words. The report's period words sit
mid-sentence on the hub's fire rows and in the editor's caption ("{count}
events {period}"), so they are lowercase with their prepositions — en "last
week" / "last month", de "in der letzten Woche" / "im letzten Monat", ro
"săptămâna trecută" / "luna trecută" — and join the caption's height
templates. Entering "The week just ended" from an upcoming cadence seeds
the anchor to the week's first day (a Sunday anchor kept from an upcoming
weekly digest would report the week that ended seven days earlier). The
summary of an every-category report drops the "{categories} — " prefix
("Events — 12 events" read twice); a named selection keeps
`digestCategoriesLabel`'s rule (names up to two, a count past that — D43's
"past two" corrected). Count placeholders of the report's plural keys take
`decimalPattern`. The footer's Send row is disabled at the ten-digest cap
(the hub hides its Add row there) and its default time is
`kDefaultAlertDayMinute`, not a literal 08:00; `_sendReport` respects the
page's picker guard too. de "Der abgelaufene Monat". Tests: a literal
upcoming signature pinned byte for byte, the fold-throw fallback, the
disabled Every / Covers rows' 38 % and semantics and height, de 2.0 with a
report Shows, a fixed clock in the caption test, a hub fire row for a
report digest; the alerts flow scrolls the sheet back up to the Shows row
before tapping it.

**D46 — the S5a review's rulings (lead, 2026-10-31; one medium).** Share
and the ⋮'s export share one in-flight slot and refuse a second start
while one is pending (`CalendarExportController.isPending`) — share_plus
completes a pending share as unavailable when a second one starts and
clears its cache on every share, so two taps stacked two choosers and
wiped the first copy. The browser page's export listener ignores the
calendar's and the report's operations (their controllers own the words;
it opened its loading dialog over the report and queued a second failure
bar — the `.ics` export suffered the same). Event titles and category
names are Markdown-escaped in the share (``\ ` * _ [ ] # < >`` and a
leading list marker — "# Plan" became a heading, "*Leg* day" emphasis, "1.
Squats" a nested list); the share asserts a missing event as the page does
(D38) and skips it in release; `exportText` asserts its file-name contract
(a bare name with the format's extension) and removes a half-written file
on failure. Counts in `tileValue` and `groupFacts` go through
`ReportLabels.count` (the subtitle already grouped "1,234 events"). Count
deltas take plural keys (`reportDeltaMoreCount` / `reportDeltaFewerCount`)
so ro agrees ("cu 2 mai multe / mai puține", "cu 1 mai mult / mai puțin")
and the hours keep the mass forms. de Send labels "Wöchentlich zusenden" /
"Monatlich zusenden" — two lines at 2.0 on 360 and the subscription sense
kept (S5a's "Wochenbericht senden" read as a one-off). The group header's
fold glyph is `FormTrailingGlyph` too. Tests: the Ahead section, a
cross-month row, a 12-hour clock and a caption-less trend in the Markdown;
a failing write; the browser page's ignored operations; the page's share
text equal to `ReportMarkdown.render` of the shown report with its
comparison; a double tap; Markdown characters; the semantics pin with no
pump between the jump and the push. Recorded as built: "Report exported"
also shows when the share sheet is dismissed (the `.ics` path too);
`anta-context`'s import-export reference gains the text export (the lead).

**D47 — the S5b review's rulings (lead, 2026-10-31; the guide topic).**
The guide's own rules win over the lead's draft: a page's lead is one
sentence of at most 75 characters ("“Report” counts a week, a month or a
year, category by category."); a sentence never retypes a label — the
Categories tooltip, the Custom row, "Mark as present", both Send labels,
Shows and its week entry, Share go in as quoted placeholders; the preview
count and the category cap come from `ReportMetrics`, never a literal; the
digest row says the tap *opens* a digest to save (nothing exists until
Save) and names the month label too, since the page opens on This month;
"the numbers update", not "refold"; the keys follow the sibling pattern
(`calendarGuidePageReport`, `…Caption`); the caption no longer repeats the
lead. The Report page is the one task page without a "Try it" card — its
practice is the real page and the guide's demos hold no report — and the
`calendar-events` rule line now says so. Tests gain the 412 size loop, the
lead in de and ro, the view-menu lines in the practice page's walk, and a
Report-first pick on the screen card.

## 4. The spec

### 4.1 The three shapes of event

Every event in the chosen categories is one of three shapes, read from fields
it already has. The shape decides what the report can say about it; the
category decides where it is grouped.

| Shape | Rule | Yields | Example |
| --- | --- | --- | --- |
| **Routine** | `EventPresence.appliesTo` (recurring and `tracksPresence`) | attended / missed per past day, streak, hours of kept days | Gym, Run, Mobility flow |
| **Repeat** | recurring, not tracked | happened days; the count label per day (`RecurrenceFormatter.countLabel`: the age under `elapsed`, "Week N" under `numbered`) | Ana's birthday · 32 years; Rent; a program |
| **One-off** | `OneTimeRecurrence` or `SpecificDatesRecurrence` | happened days (a day each); hours when timed; task progress from the description | Dentist 09:00 · 1 h; Weekend in Sibiu (2 days); Tax form · 4 of 4 tasks |

Public holidays and fasting days are not events and never appear. A skipped
day is not an occurrence (skips are subtracted inside `occursOnUtcDay`). A
tracked `SpecificDatesRecurrence` event is a routine: `EventPresence.appliesTo`
is the one gate and routine wins over the one-off column (D31).

### 4.2 The page

- **Idiom**: the calendar's panel cards — `rowGroup` cards on `pageGround`
  with `FormSectionLabel`s — the overview's look. Light / dark from
  `AppTheme`; every number from `FormMetrics`, `RowMetrics`, `AppBarMetrics`
  or the new `ReportMetrics` (`lib/constants/report_metrics.dart`).
- **Bar** (`AppBarMetrics`, 48 dp): ← · the title button "Report ▾" (the view
  menu: Calendar · Overview · Report, `CalendarViewPage.report`) · a Categories
  button with a count badge on the glyph (the ui-language badge rule) · ⋮ (the
  shared `CalendarOverflowMenu`).
- **Band**: `AgendaPeriodNav` with the Period menu as its title; ◄ / ► step by
  the period's own length (`OverviewPeriod.stepped`), Today returns to the
  period as picked; the one-line subtitle "31 events · 3 missed" — in the
  future tense (T) "10 planned · 9 h 30".
- **Body**: one scroll of cards, in this order, each drawn only with content
  (H): Totals · Categories · Over time · Missed · Ahead · the footer rows; in
  the future tense (T) Totals · Categories · the footer rows — the Categories
  groups are the plan (W). One `Scrollable` on the page, never a scroll
  inside a card (X). Bottom clearance `max(viewInsets, viewPadding)`.
- **Refold**: a presence mark or a category change re-folds the report from
  the same samples; the previous render holds at reduced opacity, no skeleton.

### 4.3 The cards

- **Totals** — a 2-column grid of stat tiles (`ReportMetrics.tileColumns`), an
  odd last tile full-width; the set per O: Events · Attended ("21 of 24", the
  percentage under it) · Missed · Hours ("18 h 30") · Tasks ("9 of 12"). Each
  tile: label (sentence case), value (proportional figures, semibold), delta
  as plain text against the previous period of the same length (D). Caption:
  "To 30 October · 2 skipped · 2 ahead". In the future tense (T) the set is
  Planned · Hours · Tasks and the caption is absent (nothing to today, nothing
  skipped).
- **Categories** (W) — the one place the period's events live, so fifty
  events never make a fifty-row page. One group per chosen category with a
  happened count, groups in descending count, folded past
  `ReportMetrics.maxCategoryRows` (7) into "n more categories ›" (V). The
  header is the category row: avatar glyph, name, a 4 dp meter in the category
  tint (the new form primitive, L) scaled to the largest count, "count ·
  hours" (" · n missed" for a category with routines) and a fold glyph. Under
  an open header its rows, inset to the header's text: routines first as
  aggregates ("Gym · 8 of 10 attended · 8 h", by occurrences), then the
  period's repeats and one-offs as dated rows, oldest first ("PT session ·
  Thu 8 · 17:00 · 1 h", "Ana's birthday · Thu 29 · 32 years", "Groceries ·
  Fri 30 · 5 of 8 tasks" — the subtitle: day · time · duration · the count
  label · "n of m tasks"). A group opens at `ReportMetrics.groupPreviewRows`
  (4) rows; "n more ▾" expands the rest in place, "Show less ▴" folds back
  (X); a header tap closes or opens the group; the state is per visit. Every
  child row opens the detail sheet in place through `EventSheetsFlow` (where a
  task is ticked, M). The header's tap no longer focuses the report (E
  superseded): the bar's Categories picker narrows the scope. Colour never
  carries identity alone — the built-in palette fails the colour-vision check
  on two adjacent pairs (cardio / rest ΔE 2.9 deutan; birthday / mobility ΔE
  6.7) — so every mark sits beside its glyph and name, and text never wears
  the tint. The widget is `ReportCategoryGroup`, a calendar widget on
  `RowMetrics`, used by Categories, Missed and Ahead alike.

  ```
   CATEGORIES   ▾ Gym          14 · 13 h 10 · 2 missed
                    Gym · 8 of 10 attended · 8 h                  10
                    Legs day · 3 of 3 attended · 3 h 30            3
                    PT session · Thu 8 · 17:00 · 1 h
                    Stretch · 2 · 40 min                           2
                    2 more ▾
                ▸ Cardio        6 · 3 h 20 · 1 missed      (closed by a tap)
                ▾ Mobility      4 · 2 h
                    Mobility flow · 4 of 4 attended · 2 h          4
  ```
- **Over time** — one series, happened occurrences in `primary`, the routines'
  missed part in `outlineVariant`; legend only while both parts exist. A week
  or month: one column per day; a year, last 12 months or any span over 31
  days up to 26 weeks: one per week; longer: one per month. Columns ≤
  `ReportMetrics.columnMaxWidth` (24), a 2 dp surface gap, 4 dp rounded data
  end, square baseline; a hairline at the peak with its value; every fourth
  label or the Mondays. Caption per F. Drawn per Q.
- *Routines* and *Happened* as cards of their own (S) are superseded by W:
  their rows live inside the Categories groups. "What did I do last week?" is
  answered per category — the three hangouts under Friends, the birthday
  under Birthday, the to-dos under To do — and in day order one tap away
  through Show as list.
- **Missed** — the routines' missed days to today, grouped by category with
  the same `ReportCategoryGroup` (W), the rows faded 0.35, each with the
  presence button (G); a mark writes `EventSheetsFlow.setOccurrencePresence`
  and re-folds.
- **Ahead** — the period's occurrences after today (N), every shape, routines
  included (S), grouped by category (W), dated rows oldest first within a
  group: "Gym · Sat 31 · 10:00 · 1 h", "Ioana's birthday · Sat 31 · 7 years".
  No presence button (nothing to mark yet). In the future tense (T) there is
  no Ahead card: the Categories groups hold the plan, and "what do I do next
  week?" reads as four gym sessions, two evenings with friends, two to-dos, a
  birthday and a run.
- **Footer** — `FormActionRow`s: Show as list (the overview in List mode on
  this period and these categories) · Share report (K, S5) · Send me this
  report weekly / monthly (J, opens the digest editor pre-filled).

### 4.4 Three worked periods

**Period 1 — October 2026 · Gym, Cardio, Mobility, Rest, Measurement,
Birthday** (the mock). Tiles Events 31 · Attended 21 of 24 (88 %) · Missed 3 ·
Hours 18 h 30; Categories: Gym 14 · 13 h 10 · 2 missed open at four rows (Gym
8 of 10 · 8 h, Legs day 3 of 3 · 3 h 30, PT session Thu 8 · 17:00 · 1 h,
Stretch 2 · 40 min, "2 more"), then Cardio 6 · 3 h 20 · 1 missed, Mobility 4 ·
2 h, Rest 4, Measurement 2, Birthday 1; Over time 31 day columns; Missed
grouped (Gym 2, Cardio 1) with buttons; Ahead: Gym Sat 31, Ioana's birthday.

**Period 2 — October 2026 · Birthday, Holiday, Friends** (viewed on 30 Oct;
"Friends" is a user category):

```
 TOTALS                               Events          Hours
                                      6  +2 vs Sept   5 h 30  +3 h
                                      To 30 October · 1 ahead
 CATEGORIES    ▾ Friends     2 · 5 h 30 ▬▬▬▬▬▬▬▬
                   Dinner at Tudor's · Fri 9 · 19:30 · 3 h
                   Brunch at Mara's · Sun 25 · 11:00 · 2 h 30
               ▾ Birthday    2          ▬▬▬▬▬▬▬▬
                   Ana's birthday · Sat 3 · 32 years
                   Mihai's birthday · Thu 22 · 40 years
               ▾ Holiday     2          ▬▬▬▬▬▬▬▬
                   Weekend in Sibiu · Sat 17
                   Weekend in Sibiu · Sun 18
 AHEAD         ▾ Birthday    1
                   Ioana's birthday · Sat 31 · 7 years
```

No Attended / Missed tiles (nothing tracked, O), no Over time (Q), the age from
the count label when the event counts occurrences in the `elapsed` style; a
Markdown share of this page is a month's diary (K).

**Period 3 — This week · To do** (viewed Wednesday 28 Oct):

```
 TOTALS                               Events                Tasks
                                      3  −1 vs 19 – 25 Oct  9 of 12 · 3 open
                                      To 28 October · 2 ahead
 CATEGORIES    ▾ To do       3          ▬▬▬▬▬▬▬▬
                   Tax form · Mon 26 · 4 of 4 tasks
                   Dentist · Tue 27
                   Groceries · Tue 27 · 5 of 8 tasks
 AHEAD         ▾ To do       2
                   Call the bank · Thu 29
                   Garage · Sat 31 · 0 of 3 tasks
```

No Hours tile, since none of these to-dos carries a duration (O); the Tasks
tile counts to today, Ahead carries the open ones (M, N).

**Period 4 — Last week · every category** ("what did I do last week?", viewed
Monday 2 Nov; Mon 26 Oct – Sun 1 Nov; "Friends" is a user category):

```
 TOTALS        Events 11        Attended 4 of 5 (80 %)   Missed 1
               Hours 10 h 50    Tasks 6 of 9
               To 1 November · 1 skipped
 CATEGORIES    ▾ Gym         4 · 4 h · 1 missed
                   Gym · 4 of 5 attended · 4 h                               5
               ▾ Friends     3 · 6 h 10
                   Coffee with Ioana · Mon 26 · 10:00 · 1 h
                   Dinner at Mara's · Tue 27 · 19:30 · 3 h
                   Hike with Radu · Sat 31 · 09:00 · 2 h 10
               ▾ To do       2 · 40 min
                   Groceries · Fri 30 · 5 of 8 tasks
                   Tax form · Sun 1 · 09:00 · 40 min · 1 of 1 tasks
               ▾ Birthday    1
                   Ana's birthday · Thu 29 · 32 years
 MISSED        ▾ Gym         1
                   Gym · Wed 28 · 18:00                                     [✓]
```

Over time has eleven occurrences, so it is drawn (Q) with one missed column.

**Period 5 — Next week · every category** ("what do I do next week?", viewed
Sunday 1 Nov; Mon 2 – Sun 8 Nov; the future tense, T):

```
 TOTALS                       Planned             Hours              Tasks
                              10  −1 vs this week  9 h 30  −1 h 20   0 of 3
 CATEGORIES    ▾ Gym         4 · 4 h
                   Gym · Mon 2 · 18:00 · 1 h
                   Gym · Tue 3 · 18:00 · 1 h
                   Gym · Thu 5 · 18:00 · 1 h
                   Gym · Sat 7 · 10:00 · 1 h
               ▾ Friends     2 · 5 h
                   Dinner at Tudor's · Fri 6 · 19:30 · 3 h
                   Brunch · Sun 8 · 11:00 · 2 h
               ▾ To do       2
                   Call the bank · Wed 4
                   Garage · Sat 7 · 0 of 3 tasks
               ▾ Birthday    1
                   Mihai's birthday · Tue 3 · 40 years
               ▾ Cardio      1 · 30 min
                   Run · Fri 6 · 07:00 · 30 min
```

No Attended / Missed, no Over time, no Ahead card: in the future tense the
Categories groups are the plan (W, T), and a plan has nothing to grade yet.
Stepping ◄ from here lands on Period 4 and the page changes tense once; the
day-by-day order is Show as list.

### 4.5 Report digests

- `DigestCadence.weeklyReport` and `monthlyReport` (I). `DigestPlanner.spanFor`:
  the week (from `calendarWeekStart`) or the calendar month ending before the
  fire day; `leadDays` ignored, the editor's Covers row disabled at 38 %, never
  hidden. The horizon rule (`kDigestHorizon`) is unchanged.
- The editor gains one row, **Shows ▾**: Upcoming (today) · The week just ended
  · The month just ended; Every / On stay the fire schedule.
- The two questions on the shade: "what do I do next week?" is the **existing**
  weekly digest (Shows Upcoming, Every week, On Sunday, Covers 7 days) and
  changes nothing — its tap still lands on the overview's List; the report's
  future tense is its on-demand twin. "What did I do last week?" is the new
  `weeklyReport` cadence fired on Monday morning.
- Words at arm time (`digestNotificationContent`) from the same pure builder as
  the page over `EventAgenda.occurrencesInRange` + `EventPresence.isMissed`:
  a summary line, then per-category lines (P), `kDigestMaxLines` kept. When the
  arm runs before the span has closed the body is the generic line and the
  numbers wait for the next reconcile; a presence or skip write requests
  `reconcileAllQuietly` unawaited after its chain (the `deleteCategory`
  precedent), so a Sunday-night mark refreshes Monday's words.
- Tap: `AlertPayload` gains an additive `page` key (`report`); absent means the
  overview, so an older build lands on the List as today. `OpenOverviewIntent`
  carries it to `AppNavigator.toCalendarReportLook({start, end, categoryIds})`.
- Examples: "Weekly report · Gym, Cardio, Mobility — 5 of 6 attended · 6 h 10 ·
  1 missed / Gym · 4 of 4 · 5 h / Cardio · 1 of 2 · 40 min · missed Thu 29 Oct
  / Mobility · 1 · 30 min"; "Monthly report · Birthday — 3 birthdays / Ana 32 ·
  Mihai 40 · Ioana 7"; "Weekly report · To do — 4 happened · 9 of 12 tasks /
  open: Garage (3), Call the bank".

### 4.6 Copy (en; de / ro at implementation, every key in all three ARBs)

Report · Totals · Categories · Over time · Missed · Ahead · "{n} more"
(plural) · Show less · "{n} more categories" (plural) · Events · Attended ·
Hours · Tasks · "{attended} of {total}" · "{ticked}
of {total} tasks" (plural) · "To {date}" · "{n} skipped" (plural) · "{n} ahead"
(plural) · "{delta} vs {period}" · "Most on {weekday}" · "usually {from} –
{to}" · "All {n} routines" · Show as list · Share report · Send me this report
weekly · Send me this report monthly · Shows · Upcoming · The week just ended ·
The month just ended · "Last week's report is ready" · "Last month's report is
ready" · This week · This month · Last week · Next week · Last month · Next
month · Planned · "{n} planned" (plural). Final key names are the l10n
skill's.

### 4.7 Architecture and performance

The layering (U), top to bottom, and why each piece sits where it does:

- **One model, three readers.** `CalendarReport` (tiles, category rows, trend
  buckets, routines, happened, missed, ahead, the caption facts) is built only
  by `CalendarReportBuilder.fold(...)`; the page renders it, the digest words
  are written from it, the Markdown share prints it. A number exists in one
  place in code, so the notification and the page can never disagree.
- **Samples cross the boundary, not scans.** `CalendarReportService` turns the
  facades into `ReportSample(eventId, dayUtc, missed)` lists —
  `EventAgenda.occurrencesInRange` (clamped at 366 days, so a report is
  bounded by construction), `EventPresence.isMissed`, skips already
  subtracted — plus the description texts to count tasks. The builder never
  touches a service, a clock or a formatter: `today`, the week start and the
  strings are arguments. That is what makes it testable from the five §4.4
  fixtures and callable from the planner, which runs with no bloc alive.
- **Cost model.** A fold is O(events × days) `occursOnUtcDay` probes plus
  O(samples) aggregation — the calendar's existing scan shape (the perf
  roadmap's Phase 3 cut a cold month to about 2,000 probes); a 366-day span
  over 50 events is some 18,000 probes, well inside one frame on the UI
  isolate, so **no isolate** (the app spawns one only for folder search). The
  previous-period delta is a second fold of the same shape and is the memo's
  hit when the owner steps ◄, so a step costs one fold, not two.
- **Memo and invalidation.** The service keeps `ReportMetrics.memoFolds` (4)
  results keyed by `(period, categoryIds, membershipRevision,
  occurrenceRevision, presenceRevision, today)` — the counters `CalendarBloc`
  already carries (`calendar_state.dart:47, :61, :82`); a presence mark bumps
  `presenceRevision` and the bloc refolds; `today` in the key means midnight
  never serves yesterday's split. Nothing survives `DatabaseLifecycle.reset`.
- **Fold off the build path.** The bloc folds in its handler, never in
  `build`; the page keeps the previous model at reduced opacity until
  `ReportReady` (the overview's between-frames precedent) and the route's
  first frame never waits for a fold — the bar, the band and dimmed tiles
  appear at once.
- **Task counts.** `MarkdownListSyntax` runs per line of each description once
  per fold and is cached per `(eventId, day?, description text)` inside the
  service; under per-day scope only occurrences with their own text
  (`OccurrenceDescriptions.descriptionFor`) are parsed.
- **Bounded UI.** W's groups and V's caps: until the owner opens a group's
  "n more", a page holds at most seven groups of one header and four rows;
  the trend has at most 31 day, 27 week or 14 month columns (D31); every card is a sliver of
  constant-height rows (`captionMaxLines: 1`, the overview's row rule) behind
  a `RepaintBoundary`, so an expanded 200-row group scrolls at frame rate;
  formatters are created once per fold, never per row. One `Scrollable` on the
  page: a group expands the page and never scrolls inside it (X, the
  2026-10-30 `GuideStageSlot` trap).
- **Digest arming.** `DigestPlanner` asks the service for the span's model at
  arm time: ten digests, one fold each, on the UI isolate at reconcile — the
  cost class of today's `digestEntries`; the words come from the model, so a
  wording change lives in one place.
- **Growth this leaves open, with no schema change.** Year-over-year and a
  two-selection comparison are two folds and a diff of two models; streak
  tiles per routine are `PresenceAdherence` over the same samples; a saved
  report is `(period, categoryIds)` beside `overviewViews`; a home-screen
  glance later reads the memoized model.
- **Accessibility and finish.** The chart's one semantics node reads the
  caption, and the By category rows are its table twin (every chart has a
  table view); a tile announces "Attended, 21 of 24, 88 percent"; an empty
  period dims Totals and says so in one caption; a selection with nothing
  tracked never shows Attended; at text scale 2.0 a tile value wraps to a
  second line and is never clipped (the designer measures this before S2).

### 4.8 The designer's spec (2026-10-30, Opus 5.5; the lead accepted every default A–X)

Rendered with real Roboto and MaterialIcons in `AppTheme.light()` / `dark()`
at 360 and 412 wide, text scale 1.0 / 1.3 / 2.0 linear and 2.0 on the AOSP
200 % curve, en and de: the real bar, `AgendaPeriodNav`, `FormSectionLabel`,
`FormRowGroup`, `FormActionRow`, `FormCaption` and `AgendaDayListRowBuilder`
rows, plus the tile, header, child, disclosure and chart as scratch widgets.
The structure is the mock's; no new mock. New `ReportMetrics` names are in
bold; tolerance ±1 dp unless a test pins it.

**What the mock left open (judged on the renders).** (1) Tiles broke at the
mock's sizes: "88 % · +2 vs September" wrapped at 360 en 1.0 and "of 24"
grew the line box; "18 Std. 30 Min." took four lines at de 2.0 in two
columns. (2) "vs September" in every tile said one fact five times. (3) The
header and the child row read alike (both 15/400 over a caption). (4) Missed
rows at 0.35 measured 2.17:1 light / 2.75:1 dark on `rowGroup` — a contrast
failure that separated nothing, since every row in that card is missed. (5)
The chart's missed part in `outlineVariant` is 1.62 / 1.74 on `rowGroup`
(dataviz WARN; `outline` would reach 4.33 / 5.14 but fails the normal-vision
ΔE floor against `primary` in light, 13.5 < 15) — it stays, relieved by the
legend, the Missed tile and the Missed card. (6) A `Row` legend overflowed by
39 px at de 2.0. (7) The totals caption broke at "· 2 ahead" / "2 / anstehend".

**Bar** (`AppBarMetrics`, unchanged geometry, measured 48): exactly the
overview's `AppBar` (`titleSpacing: CalendarViewMenu.titleSpacing`,
`toolbarHeight` 48, icon themes 22 `onSurface`, `pageGround`, transparent
`surfaceTintColor`, `scrolledUnderElevation` 0, `excludeHeaderSemantics:
true`), the default back button; title `CalendarViewMenu(page:
CalendarViewPage.report)` — the menu gains one radio row "Report", glyph
`Icons.bar_chart_rounded`, id `calendar-report-open`; the Categories button
`AutomationId(report-categories-open, IconButton(tooltip: l10n.calendar
Categories, isSelected: narrowed, iconSize: AppBarMetrics.glyphSize, icon:
ExcludeSemantics(Badge.count(count: categoriesInScope, isLabelVisible:
narrowed, child: Icon(narrowed ? Icons.filter_alt_rounded : Icons.filter_alt
_outlined)))))`, 48 × 48; ⋮ `CalendarOverflowMenu(identifier: 'report-more')`.

**Band** (`AgendaPeriodNav`, unchanged): pinned under the bar, never scrolls;
ids `report-nav-previous` / `-next` / `-today` / `-title`; `onTitleTap` opens
the Period menu through `showFormMenu(alignment: FormMenuAlignment.center)`,
item ids `report-period-<this-week|last-week|next-week|this-month|last-month|
next-month|this-year|last-12-months|last-90-days|custom>`; `titleTemplates`
over the report's menu labels, the twelve month names and the week spans, as
the overview builds its own. Subtitle "31 events · 3 missed" / "10 planned ·
9.5 h" under the nav's existing one-line shrink rule (fit 1.00 at 1.0 and
1.3; at 2.0 en 0.86, de 0.76). Nav height 52 / 64 / 146 at 360 (two title
lines at 2.0, existing behaviour), 95 at 412 2.0. No overview totals line.

**Body**: one `CustomScrollView`, id `report-body`; padding `fromLTRB
(RowMetrics.groupInset, FormMetrics.bodyTop, RowMetrics.groupInset,
FormMetrics.bodyBottom + max(viewInsets.bottom, viewPadding.bottom))` through
`MediaQuery`. Order, past or current tense: TOTALS label → Totals card →
caption → `groupGap` 18 → CATEGORIES → groups → 18 → OVER TIME → chart → 18 →
MISSED → groups → 18 → AHEAD → groups → 18 → footer card (no label). Future
tense: TOTALS → card (no caption) → CATEGORIES → groups → footer. Box cards
(Totals, chart, footer) are `SliverToBoxAdapter(RepaintBoundary(card))`;
group cards are a `SliverList` of `FormRowShell` rows (first / last corners,
hairline at the child's indent, `trailingGap` on the card's last row), lazy,
with the delegate's own repaint boundaries. Section labels are plain
`FormSectionLabel`, no `headingLevel` (W, as the overview).

**Totals card**: one `rowGroup` card, radius `RowMetrics.groupRadius` 14,
clipped; tiles are flat cells, not sub-surfaces, separated by 1 dp
`rowDivider` hairlines full bleed (vertical between the columns, horizontal
between rows). Columns: `tileColumns` (2) while the widest value template
fits one line in half the card — `widest ≤ (cardWidth − 1) / 2 −
tilePadding.horizontal`, the templates 888, "888 of 888" and 888.8 hours laid
out by `TextPainter` with the page's `DefaultTextStyle` and the current
scaler, decided by locale, scale and width, never by the value (C) —
otherwise one column; in two columns an odd last tile is full width.
Measured: en 96.7 / de 107.2 against a half of 131.5 at 1.0 → 2; at 1.3 en
125.0 → 2, de 138.5 → 1; at 2.0 en 190.9 / de 211.6 → 1 (AOSP 149.8 / 168.4
→ 1); at 412 the half is 157.5, so de 1.3 keeps 2. **`tilePadding`**
`fromLTRB(16, 12, 16, 12)`. Label: caption role 13 / `captionLineHeight` 18,
`onSurfaceVariant`, sentence case, wraps. Gaps `RowMetrics.lineGap` 2 between
label, value and detail. Value line: `Text.rich` with `StrutStyle(fontSize:
tileValueSize, height: tileValueLineHeight / tileValueSize, forceStrutHeight:
true)`; figure runs (`[+−-±]?\d+([.,]\d+)?` and "—") at **`tileValueSize` 28 /
`tileValueLineHeight` 34**, w500, `onSurface`, `FontFeature.proportional
Figures()`; every other run (units, "of 24") `FormMetrics.labelSize` 15 /
w400 `onSurfaceVariant` (D). Detail: caption role, the share and the bare
delta — "88 % · +2", "3 open · +2", "+4", "+1.2 h" (A) — a slot that always
reserves one line. Tile height 98 / 118 / 168 (143 AOSP); the value stayed on
one line in every matrix cell. Card of five tiles 296 / 356 en 1.3 / 594 de
1.3 / 844 at 2.0 (719 AOSP). "—": the figure style in `onSurfaceVariant`,
detail blank. Empty period: every value `onSurfaceVariant`, no opacity (F),
the caption "Nothing happened in October", no other card, the footer drawn
with Share disabled. Caption: `FormCaption(padding: FormMetrics.groupCaption
Padding)` under the card (E), wrapping, segments joined with " · " and a
count bound to its word with a no-break space ("2 skipped"): "To 30
October · against 1 – 30 September · 2 skipped · 2 ahead" (44 at 1.0,
116–188 at 2.0). Semantics per tile: `Semantics(container: true, identifier:
report-tile-<events|attended|missed|hours|tasks|planned>, label: "Attended,
21 of 24, 88 percent, 2 more than 1 – 30 September")` over
`ExcludeSemantics`, not a button. **Refold** (R): during `ReportFolding` the
body (not the bar, not the band) dims to **`refoldOpacity` 0.6** after
**`refoldDimDelay` = `Durations.short3`** (150 ms), absorbs pointers while
dim, un-dims at once, no skeleton. Hours everywhere in the report (tiles,
header facts, aggregate captions, the subtitle) read as decimal hours
"18.5 h" (B — "18 Std. 30 Min." forced one column at de 1.0); a single
occurrence keeps the duration grammar ("17:00 · 1 h").

**The new primitive `FormMeterRow`** (`form_rows.dart`, a `FormDividedRow`):
`FormMeterRow({required Widget leading, required String label, String?
caption, double? fraction, Color? meterColor, Widget? trailing, required
VoidCallback? onTap, String? semanticsLabel, bool? expanded, String?
identifier})`. Padding left `RowMetrics.groupInset` 16, right `FormMetrics.
rowEndPadding` 12, top and bottom 9 (`RowMetrics.twoLinePadding`), minimum
height `FormMetrics.twoLineRowMinHeight` 62. Leading: a 40 dp box
(`FormMetrics.rowLeadingSize`) holding an `EventAvatar` (radius 20, icon 24,
α 0.16), then `FormMetrics.gap` 14. Label 15 / 20 **w500** `onSurface`, at
most 2 lines with an ellipsis. Caption: the caption role on one line inside a
box of `textScaler.scale(captionLineHeight)`, `FittedBox(scaleDown,
centerLeft)` — `AgendaPeriodNav`'s count rule: shrinks, never truncates,
never grows (fit 1.00 to en 1.3; de 1.3 0.87, en 2.0 0.85, de 2.0 0.72).
**Meter**: only when `fraction != null`; **`meterGap` 6**, then a
**`meterHeight` 4** track in `rowDivider`, radius 2; the fill `meterColor`
(the category colour), width `max(meterHeight, fraction × width)` above
zero, nothing at zero; `fraction` = count / the card's largest count.
Trailing: `FormMetrics.gap` 14 before it; for a group header `Icons.expand_
more_rounded` 20 (`FormMetrics.trailingIconSize`) `onSurfaceVariant`,
rotated half a turn when open over `Durations.short4` with `Easing.standard`
(0 under `disableAnimationsOf`) (M). One `InkWell` over the row; divider
indent `FormMetrics.dividerIndentTitle` 70. Semantics one node:
`Semantics(button: true, expanded:, label: semanticsLabel, identifier:)`
over `ExcludeSemantics`, the label spelled out ("Gym, 14 events, 13.2 hours,
2 missed"). Heights with a meter 66 / 77.4 / 104 (AOSP 94), without 62 at
1.0. `form_rows_test` gains: one node with its expanded flag, the caption
never taller than one line, the fill's minimum width, no meter at null.

**Group header** (`ReportCategoryGroup`, a calendar widget on `RowMetrics`):
a `FormMeterRow` with the fold glyph (I). Categories card: facts "14 · 13.2 h
· 2 missed" and a meter; Missed card: "2 missed", no meter; Ahead card: "1 ·
1 h", no meter. Id `report-group-<categories|missed|ahead>-<categoryId>`.
Opening or closing inserts or removes the rows below the header at once;
only the glyph animates.

**Child rows** (inset to the header's text at x 70; one geometry per kind;
J). *Dated row*: `AgendaDayListRowBuilder`'s entry row with three additive
changes to the builder — `entryRow(BuildContext, AgendaDayListEntry)` public
and unshelled, `avatars: false` keeping the 40 dp slot empty, `fadeMissed:
false` dropping the 0.35 — with `captionMaxLines: 1`, `singleLineTitles:
true`, `onEntryTap` opening the detail sheet through `EventSheetsFlow`; in
the Missed card only `onEntryPresence` / `presenceIdentifier` (the
`event_available_rounded` button with the "Mark as present" tooltip in a
48 dp sibling node), rows at full opacity (G). Caption: day · time · duration
· count label · "n of m tasks"; the month joins the day only when the period
spans more than one calendar month (U). 62 / 67 / 94 (AOSP 89), the builder's
own extents. Ids `report-row-<eventId>-<yyyy-MM-dd>`, presence `report-row-
presence-<eventId>-<yyyy-MM-dd>`. *Routine aggregate row*: a twin of
`_eventRow` — `FormPickerRow(leading: a blank 40 box, label: title, value:
'$happened', caption: '8 of 10 attended · 8 h', captionMaxLines: 1,
singleLine: true, showChevron: false)`; the value is the happened count so
the column sums to the header (K, D26); the tap opens the detail sheet on
the routine's latest happened day in the period (V); the dated row's
heights; id `report-routine-<eventId>`. *Disclosure rows* (L): a
`FormActionRow` variant — the label at x 70 (`dividerIndentTitle`), 15/500
`primary`, a trailing glyph of 20 in `primary` at `rowEndPadding`, minimum
48, indent 70, button semantics: "2 more" (`expand_more_rounded`, expanded
false, label "2 more in Gym"), "Show less" (`expand_less_rounded`, expanded
true, "Show less of Gym"), both on one id `report-group-more-<card>-
<categoryId>`; "5 more categories" (`chevron_right_rounded`, opens the
sub-sheet, id `report-categories-more`); 48 at 1.0 and 1.3, two lines at de
2.0. After "Show less" the scroll jumps by the removed rows' extent
(clamped) so "n more" lands where the finger was (S).

**Over time**: a `rowGroup` card with **`chartPadding`** = `tilePadding`. Top
row: the legend in `Expanded(Wrap(spacing: legendItemSpacing 16, runSpacing:
2))` only while both parts exist — a dot of `RowMetrics.labelDotSize` 10,
**`legendDotGap` 6**, caption-role "Happened" / "Missed" — then a 14 gap and
the peak value right-aligned in the caption role. **Plot**: `chartTopGap` 4,
then **`chartPlotHeight` 80**, a 1 dp `rowDivider` hairline at the top (the
peak) and at the baseline. Columns: slot = W / n, width = `min(columnMaxWidth
24, slot − columnGap 2)` centred in its slot; `primary` from the baseline,
square there; the missed part (`outlineVariant`) stacked above with a
**`columnGap` 2** surface gap; only the top segment rounded, **`columnRadius`
4** capped at width / 2; an empty column draws nothing; columns are not
tappable (Q). Axis: a 4 gap, caption-role labels in a box of `scale(18)`,
each centred under its column, laid out unseen first, one closer than 4 dp
to the last drawn label skipped. Labels per unit: days of a month — the
columns where a week starts (`calendarWeekStart`), as day numbers (X); days
of a week — `DateFormat.E`, or `EEEEE` when E does not fit; weeks — the
column holding a month's 1st, as `MMM`; months — `MMM`, else `MMMMM`.
Caption: **`chartCaptionGap` 12**, then the caption role, wrapping. Card 178 /
216 / 268 en and 342 de at 2.0 (two legend lines); AOSP 259 / 331; a 31-day
column is 7.6 dp at 360. Contrast: `primary` on `rowGroup` 6.12 / 9.56,
against `outlineVariant` 3.78 / 5.48. Semantics: one node `report-trend`,
label "Over time. Most on Mondays, usually 18:00 – 19:30" (or "Peak 2 on
Monday 5 October" with no caption), the plot excluded, no tap targets; the
table twin is the group headers.

**Footer**: a `FormRowGroup` of three `FormActionRow`s (48; 52 at 2.0): Show
as list (`view_list_rounded`, `report-show-list`) · Share report
(`share_rounded`, `report-share`, `onTap: null` at 38 % until S5 and in an
empty period; T) · Send me this report weekly / monthly
(`notifications_rounded`, `report-send`).

**New `ReportMetrics` constants**: `tilePadding` (as built: `tilePadding
Horizontal` / `tilePaddingVertical`, plain doubles — the file sits in the
builder's pure import closure and imports no Flutter), `tileValueSize` 28,
`tileValueLineHeight` 34, the template values 888 / 888.8, `columnMaxWidth`
24, `columnGap` 2, `columnRadius` 4, `chartPlotHeight` 80, `chartPadding`
(as built: two doubles equal to the tile padding), `chartTopGap` 4,
`chartCaptionGap` 12, `legendDotGap` 6, `legendItemSpacing` 16, `axisGap` 4,
`axisLabelMinGap` 4, `refoldOpacity` 0.6, `refoldDimDelay` 150 ms.
`meterHeight` 4 and `meterGap` 6 live in **`FormMetrics`** (as built: a form
primitive's numbers are named there first, and `form_rows.dart` never
imports a calendar constants file).

**Stays, and why**: `AgendaPeriodNav`, its subtitle rule and id pattern;
`AppBarMetrics` and the overview's bar; `AgendaDayListRowBuilder`'s extents
and callers (the three changes additive, defaulting to today's behaviour);
`EventAvatar`, `FormSectionLabel`, `FormRowShell`, `FormActionRow`'s shape;
the category palette; `outlineVariant` for the missed part; the 0.35 fade
everywhere outside the report's Missed card.

**Risks**: de 1.3 at 360 goes to one column (a 594 dp Totals card is the
first screen; 412 keeps two); header facts shrink to 0.72 at de 2.0 (about
18.7 px, still larger than at 1.0); child captions are cut at de 2.0 (the
semantics carry the full text; one line keeps a refold from moving the
Missed card under the finger); the chart's missed part is near-invisible in
dark (1.74:1) — the owner should see it on a device; meter fills are low
contrast for holiday in light (1.94 / 1.58) and competition in dark (2.31 /
1.74), decorative since the count is always in the text; the nav takes
146 dp at 2.0 on 360 (existing); the 2.0 numbers are linear, the AOSP curve
about 15 % smaller; not checked: ro diacritics and emoji, TalkBack phrasing
of `expanded`, the refold timing, ink.

**Defaults the designer took (all accepted by the lead)**: A bare deltas +
one caption naming the comparison · B decimal hours · C column count by
measured template · D big figures, small units · E the caption under the
card · F an empty period mutes, never fades · G Missed rows unfaded · H
`outlineVariant` stays · I stacked header, name w500, facts shrink · J child
rows without avatar, inset 70 through additive builder flags · K the
aggregate's number is the happened count · L disclosure rows are a
`FormActionRow` variant · M `expand_more` rotating · N the band pinned, no
totals line · O `filter_alt` with a badge only while narrowed · P
`bar_chart_rounded`, `calendar-report-open` · Q columns not tappable · R the
refold dims to 0.6 after 150 ms and absorbs pointers · S "Show less"
compensates the scroll · T Share disabled, not hidden · U the month joins a
row's day only across months · V an aggregate opens its latest happened day
· W no `headingLevel` · X a month's axis labels the week starts.

**For the design-reviewer, after S3**: states — Period 1 (October, past and
current, five tiles, groups open and closed, "2 more" then "Show less", "5
more categories"); Period 3 (no Hours tile); Period 4 (Missed); Period 5
(future, three tiles, no chart, no Missed or Ahead); an empty period; a "—"
tile; the refold dim; the single-series chart; a week, a 27-week and a
14-month chart. Matrix: 1.0, 1.3, 2.0 (+ the AOSP 200 % curve) × light and
dark × en and de × 360 × 780 and 412 × 915. Assert with `getRect`, ±1 dp:
bar 48; Categories button 48 × 48; nav 52 / 64 / 146; tile 98 / 118 / 168;
Totals card of five 296 / 356 en / 594 de 1.3 / 844; header with meter 66 /
77.4 / 104, without 62; child rows 62 / 67 / 94; disclosure and footer rows
≥ 48; chart card 178 / 216.4 / 268 en 2.0; columns 2 at en and de 1.0 and
en 1.3, 1 at de 1.3 and every 2.0 at 360; header facts never taller than
one caption line. Also: no `takeException` (de 2.0 is the case that
overflowed before); expanding a group moves nothing above the tapped row and
"Show less" keeps "n more" under the finger; one `Scrollable`; the tile,
header, chart and "n more" semantics labels; no avatar slot painted in child
rows; Missed rows at full opacity. Colour measurements: `onSurfaceVariant`
on `rowGroup` 8.88 / 9.56; `outline` 4.33 / 5.14; `rowDivider` 1.23 / 1.33;
category tints against the track, light 1.58 (holiday) to 5.43
(competition), dark 1.74 (competition) to 6.01 (holiday). Not measured: the
built page, ink and pressed states, the refold timing, TalkBack, ro — a `qa
screenshot` and an accessibility dump on `emulator-5556` once S3 lands.

## 5. Behaviour

**Must not change**

- `AgendaDayListMode` (shared with the day-list sheet, two persisted keys) and
  `OverviewModeChips.modes` (drawn by the page and the guide card, D59).
- `OverviewPeriod.encode` values (`thisYear`, `preset:<name>`, null) and the
  thisYear fallback for every unreadable value; new choices are additive.
- `OverviewLook = ({start, end, categoryIds})` and `pendingOverviewLook`.
- `EventDigest`'s stored keys and the unknown-cadence → `enabled = false`
  decode; `kDigestHorizon(perDigest: 2, maxDigests: 10)`; `kDigestMaxLines`;
  `AlertMode.notify` for every digest; `AlertPayload` additive-only;
  `digestArmSignature`; `kAlertArmGrammarToken`.
- `EventPresence.appliesTo`, `isMissed` (no wall clock), `assumeAbsent`; the
  skip filter inside `occursOn`; `EventAgenda.occurrencesInRange`'s 366-day
  clamp; `compareWithinDay` as the one same-day order.
- `AgendaMonthStore`'s contracts (resolve on navigation, `forget(month)`,
  twelve-month runs); `AgendaDayListEntry`'s fields; `AgendaDayListRowBuilder`
  as the one dated-row renderer; `EventSheetsFlow` as the one trip through an
  event's sheets.
- `NavDestinationKind` names already persisted; the built-in category palette
  (`calendar_categories.dart`) — the report adapts to it, never the reverse.
- `CalendarBloc`'s revision counters (`occurrenceRevision`,
  `membershipRevision`, `presenceRevision`) and what bumps them: the report
  reads them as a memo key and never bumps one.
- The guide's surfaces (`docs/calendar-guide-page.md` §7, committed in
  `2f29b797`): the practice card's mode row, the coach copy ("three ways to see
  the same events") and the sandbox seams; the report adds a topic page in S5
  and nothing else there.

**Deliberately changes**

- The title view menu gains a third page; `NavDestinationKind` a stamped
  `calendarReport`; `OverviewPeriodChoice` two choices; `DigestCadence` two
  values and the editor one row; `AlertPayload` one additive key;
  `form_rows.dart` one primitive (the meter row). New classes:
  `CalendarReportBloc`, `CalendarReportService`, `CalendarReportBuilder`, the
  `CalendarReport` model and `ReportMetrics` (U).

## 6. Facts from the tree

Verified 2026-10-30 (re-grep before editing):

- `lib/constants/calendar_categories.dart:30–64` — the nine built-in seeds:
  gym, cardio, rest, holiday, competition, measurement, mobility, birthday,
  other, each with its icon key and colour.
- `lib/models/upcoming_agenda_filters.dart:10` — `AgendaEventType {all,
  recurring, oneTime, none}`: the recurring / one-time split already exists.
- `lib/models/calendar_event.dart:44–60` `OccurrenceCountStyle {numbered,
  elapsed}`; `:127` title; `:181` `tracksPresence`; `:191` `assumeAbsent`;
  `:201–205` per-day description scope; `:249–253` `description` (markdown
  source); `:260` `noteId`; `:278–282` `priority`; `:228–240`
  `removeAfterAlert` — there is **no done / completed state** on an event.
- `lib/services/recurrence_formatter.dart:48` — `countLabel(event, day, l10n)`
  returns null unless `countOccurrences`; the age under `elapsed`.
- `lib/services/day_summary_resolver.dart:252–264` — the dated row's subtitle
  already leads with the count label.
- `lib/utils/markdown_list_syntax.dart:12, :22, :97–114` —
  `MarkdownListKind.task`, the `- [ ]` / `- [x]` parse with the state char:
  the one task grammar the counter must reuse (markdown-engine: one grammar
  per syntax).
- `lib/constants/event_priorities.dart:13` — `EventPriorities` glyphs and
  labels for P1–P5.
- `docs/presence-tracking-roadmap.md:591` — "Presence on one-time events. An
  event that fires once has nothing to track — the gate excludes it on
  purpose."
- `lib/widgets/calendar_header_menus.dart:78–87` (`CalendarViewPage` labels),
  `:136–159` (the view menu's `FormMenuChoiceItem`s and their semantics ids),
  `:283–315` (overflow rows Alerts · Export · Guide · Settings).
- `lib/models/overview_period.dart:14` `OverviewPeriodChoice`; `:33`
  `thisYear` factory ("what every unreadable stored value falls back to");
  `:90–91` `stepped` (All time → null); `:188–197` encode; `:209` decode
  fallback.
- `lib/services/settings_service.dart:844` — `SettingsKeys.calendarWeekStart`.
- `lib/bloc/calendar/calendar_state.dart:47, :61, :82` —
  `occurrenceRevision`, `membershipRevision`, `presenceRevision`: the memo
  key's counters (§4.7).
- `lib/utils/agenda_month_store.dart:19–35` — the store takes a `resolve`
  callback, an optional `resolveMarks` and `maxBars`, and keeps month-keyed
  maps of entries, bars and tallies: the precedent for a resolver injected
  from the page and a per-month `forget`; the report's service follows the
  shape but keys on the fold, not the month.

Agent-reported 2026-10-30 (two Opus explorations; verify each before use):
`lib/models/calendar_event.dart:83–84` `EventTime`, `:503` `occursOnUtcDay`,
`:514` skips; `lib/constants/event_presence.dart:79, :93, :112`;
`lib/utils/presence_stats.dart:60` `PresenceAdherence.compute`;
`lib/utils/event_agenda.dart:29` `occurrenceCountInWindow`, `:265`
`occurrencesInRange`; `lib/utils/digest_planner.dart:80` `plan`, `:128`
`spanFor`; `lib/utils/digest_notification_content.dart:45`;
`lib/widgets/digest_editor_sheet.dart:497–598`; `lib/models/event_digest.dart:10`
cadence, `:35` fields, `:147` payload, `:205` unknown → disabled;
`lib/services/alert_scheduler.dart:715` digest entries, `:2007`
`AlertMode.notify`; `lib/utils/alert_payload.dart:206–230`;
`lib/navigation/app_navigator.dart:46` `OverviewLook`, `:592`
`toCalendarGuide` (the stamped-push precedent), `:698` `pendingOverviewLook`,
`:708` `toCalendarOverviewLook`; `lib/pages/calendar_overview_page.dart:1264–1294`
totals, `:2202` `_serveOverviewLook`, `:2226` `_listLook`, `:2585`
`_buildModeChips`; `lib/widgets/overview_mode_chips.dart:17–28`;
`lib/widgets/agenda_period_nav.dart:112–130`; `lib/constants/alert_constants.dart:64`
`kDigestHorizon`; `lib/constants/overview_list_metrics.dart` (`syncMonths`
24, `batchMonths` 12, `maxEntries` 20000). Nothing to retire: the report adds
beside the overview and replaces no widget.

## 7. Slices

Each: one `implementer` (Opus 5.5), one `reviewer` (Opus 5.5), the gate, a
check-in. The guide work is committed (`2f29b797`), so no file is off limits
beyond §5.

| Slice | Builds | Tests |
| --- | --- | --- |
| **S0 Periods** | `OverviewPeriodChoice.thisWeek` / `thisMonth` (B, D25): `OverviewWeekPeriod` / `OverviewMonthPeriod`, factories, `stepped` to the true neighbour, encode / decode, the saved views' codec, the overview's menu rows, labels in three ARBs; the week start from `calendarWeekStart`. The four relative menu entries (R) are the report page's and land in S2 as the This preset stepped once, nothing new persisted. | `overview_period_test.dart`: the new choices encode / decode, step and fall back; a stepped week and month are the true neighbours; the DST rule (`DateTime(y, m, d)`, never midnight + `Duration`). |
| **S1 Builder and service** | `CalendarReportBuilder` (pure, `lib/utils/calendar_report_builder.dart`): shapes (§4.1), the tense (T), samples `(eventId, dayUtc, missed)` + `eventsById` + skip days + the description texts → the `CalendarReport` model (tiles, by-category, trend buckets, routines, happened (S), missed, ahead (S), previous-period deltas, the task counts through `MarkdownListSyntax` — complete; V's folds and caps are the page's, D31); `CalendarReportService` (`lib/services/`): samples from the facades, the fold memo keyed on the calendar revisions, the task-count cache (§4.7); `ReportMetrics`. | A focused suite against fakes: the five worked periods of §4.4, a span crossing today, a wholly future span, a skipped day, per-day descriptions, custom task states, the 366-day clamp, no `DateTime.now()` or formatter inside the builder; a fold-count assertion on a 366-day, 50-event fixture; a memo hit on step-back and a miss after a presence bump. |
| **S2 Bloc and page** | `designer` spec first → `CalendarReportBloc` (sealed events and states, `Equatable`, folds in handlers only) and `CalendarReportPage`, the stat tiles, the column chart, the meter row primitive (L), the Categories badge, the view menu's third entry on the calendar page and on the overview (which hands over its period and categories), `NavDestinationKind.calendarReport` + restore, `AppNavigator.toCalendarReport`, `SemanticsIds`, ARBs, a flow file; `design-reviewer` after. | Page suite: light / dark, `de` at 2.0 and 360 × 780, tiles per O, cards per H / Q, the clearance test; `form_rows_test.dart` gains the meter row. |
| **S3 Groups, rows and sheets** | `ReportCategoryGroup` (W, X): the header row with its fold glyph, child rows inset to the header's text, the preview of four, "n more ▾" / "Show less ▴", no nested scrollable; Categories, Missed and Ahead built from it, their rows through `AgendaDayListRowBuilder` and `EventSheetsFlow`; the presence button (G) and the refold; Show as list. `qa-runner`: the calendar pass + the new flow. | A twelve-event group shows four and "8 more"; expanding moves nothing above the tapped row; the page has one `Scrollable`; row taps open the sheet in place; a mark re-folds without a layout shift; `AlertKeepNotice` counted, never taken. |
| **S4 Report digests** | The two cadences, `spanFor`, the Shows row, words per P from the service's model (U), the stale-span generic line, `reconcileAllQuietly` after presence / skip writes, the `page` payload key and `toCalendarReportLook`, the footer's Send rows (J), hub rows. `qa-runner`: the alerts pass. | Planner and content suites: span never before the fire day, words only when `now >= spanEnd`, an unknown cadence still decodes disabled, the payload round-trips with and without `page`. |
| **S5 Share and docs** | Share report as Markdown (K), a guide topic for the report (the guide's hub gains one row; its practice card and coach copy untouched), the `calendar-events` subsystems reference and the `docs/calendar-events-feature.md` addendum. | The share text golden; the guide topic page test; the saved passes stay green. |

### 7.1 As built (2026-10-30, appended per slice)

- **S0 — built, reviewed, fixed.** `OverviewWeekPeriod` / `OverviewMonthPeriod`
  per D25; the overview's Period menu reads This week · This month · This
  year · Last 12 months · Last 90 days · All time · Custom; the saved views
  store a week or month holding today as the rolling kinds `thisWeek` /
  `thisMonth` and others pinned (`{kind: week, start}` / `{kind: month, year,
  month}`); `OverviewViewService` reads the week start through a reader set
  at construction (`forTesting(db, weekStart:, weekStartReader:)`). The
  review found two staleness defects, both fixed in a fix pass: (1) a saved
  rolling view was decoded once at load, so after a week or month boundary
  with the app alive the bookmark unlit, the caption showed last week and
  applying it persisted a null period that cleared the stored This week (the
  same had been true of This year across New Year) — `OverviewView.periodOn
  ({today, weekStart})` is now the one live read (the apply path, `matches`,
  the views sheet's caption and tick); (2) a week-start change while the
  overview was open left the page on the old week — `_resumeUncovered`
  re-derives `_home` and `_period` when each is a week holding today
  (`_followWeekStart`). Also: a week over the 1900 edge titles its clamped
  days; the two "This week" / "This month" labels left `_titleTemplates`
  (never a title — a week's title is a span, a month's its name; the twelve
  `yMMMM` names stay). Suite after the fix pass `+11337`, analyze clean,
  `untranslated.txt` empty. Owed to a later slice: the `calendar-events`
  skill's period lines (S5 docs); a device look at the seven-row menu at
  text scale 2.0 (S3's calendar pass).
- **S1a — built, reviewed, fixed.** `lib/models/calendar_report.dart` (the
  model, `ReportSample(eventId, day, missed, pending)`, `ReportInput`,
  `ReportTotals`, `CalendarReport.tenseOf` / `countedToOf`), `lib/utils/
  calendar_report_builder.dart` (`foldTotals`, `fold`), `lib/utils/task_count
  .dart` (`countTasks` over `MarkdownListSyntax.parse`, an LRU of 256 texts),
  `lib/constants/report_metrics.dart` (the logic numbers), and `lib/utils/
  within_day_order.dart` — `compareEventsWithinDay`, the body of
  `EventAgenda.compareWithinDay`, which now delegates to it, so the builder's
  import closure stays off the service and widget layers (the source test
  walks the relative imports transitively; two known edges are stepped over
  and pinned: `recurrence_rule.dart → public_holidays.dart → l10n`, and
  `markdown_line_shape.dart → markdown_constants.dart → material`). The
  builder takes a `categoryOf` map from the sampler rather than calling
  `CalendarCategories.resolve` (that file imports Material and l10n). The
  review's rulings are D31's paragraph; the fixtures of §4.4 are the suite's
  (Period 1's Stretch is an untracked set of dates and so two dated rows;
  ties keep the catalogue order; Period 2's trend is drawn at six
  occurrences; Period 5's Hours delta compares plan against plan, −2 h 20).
  Suite after the fix pass `+11378`, analyze clean.
- **S1b — built, reviewed, fixed.** `lib/services/calendar_report_service
  .dart`: `ReportRequest` (a plain class — never value-compare `allEvents`),
  `CalendarReportService.report` / `sampleInput` / `foldCount` / `clear`;
  the allowlist goes to `occurrencesInRange` as the digest planner passes it
  (the stored id, D32), grouping resolves the id; one LRU of `memoFolds`
  reports (D34) keyed on the sorted ids, the three revisions, today, the
  week start, the events list by identity (an event edit emits a fresh
  `allEvents` and bumps no revision), `CalendarCategories.revision` and
  `PublicHolidays.revision` (workday and holiday rules read a facade that
  changes with no bloc event); the clamp keeps a span's last 366 days (D33)
  and normalises both ends date-only; per-day texts are
  `UnmodifiableMapView`s over the facade's maps, every day; `skippedDays`
  counts skip days in the counted range where `CalendarEvent.wouldOccurOn
  UtcDay` holds (new, the skip-free half of `occursOnUtcDay`, which now
  calls it); a plan's previous totals clear `pending` first. Review
  findings fixed in one pass (the holiday revision, the allowlist, stale
  skips, an inverted local-time span, the long-span clamp, the useless
  totals memo, the Equatable request). Benchmark after the fix pass: 366
  days × 50 events with 45 skips, per-day task overrides and five
  assume-absent routines = 5,721 samples plus a real previous-year fold,
  first fold 56 ms, memo hit 0.5 ms (Windows, debug VM). Suite `+11389`.
- **S2a — built (review in progress).** `lib/bloc/calendar_report/`
  (`CalendarReportBloc` over a `FutureOr<SettingsService>` as `CalendarBloc`
  takes its service; eight events; `ReportLoading` / `ReportFolding
  (previous)` / `ReportReady`; events handled one at a time so a step
  pressed during a fold's one-frame yield starts from the settled period;
  `ReportResumed` re-reads the week start and asks the memo with no Folding
  state, emitting nothing when the report is the same), `lib/models/report_
  period_choice.dart` (the ten rows, `periodFor`, `checkedFor`; an overview
  look on All time arrives as Last 12 months), `lib/utils/report_labels.dart`
  (`ReportLabels`: decimal hours, figure / unit runs, delta, detail, the
  spoken tile label, caption, subtitle — no widgets, S4 and S5 reuse it),
  `lib/widgets/report_totals_card.dart`, `lib/pages/calendar_report_page.dart`
  (bar, band, Period menu, body, footer, refold dim; `forTesting(service:)`),
  `NavDestinationKind.calendarReport`, `ReportLook` / `toCalendarReport` /
  `switchToCalendarReport`, the view menu's third row (both existing pages
  now switch on the picked page; the overview hands its shown period and
  categories), `SettingsKeys.reportPeriod` (`calendar_report_period`) and
  `reportCategoryIds` (`calendar_report_categories`) read in one statement
  with the appearance keys, 36 `report…` ARB keys. Loading draws two "—"
  tiles; "against …" names the previous period's `menuValue`. The page
  suite pins the tile at 98 / 118 / 168, the five-tile card at 296, two
  columns at en 1.0 and one at de 1.3 and 2.0, bar 48, the Categories button
  48 × 48, the bottom padding under a fake inset, one `Scrollable`,
  `foldCount` 1 through frames, de 2.0 clean. Suite `+11428`. Left to later
  slices: the QA flow (S3), the guide's sandboxed `CalendarViewMenu`s now
  list Report but treat it as Overview (S5, the guide slice), a navigator
  restore test (none exists for any kind). The review's rulings are D36;
  the fix pass landed them all: `AppNavigator.switchCalendarView` collapses
  with one transition onto a calendar view reached through calendar views
  only (`returnOrPush` stays the hub's rule); `toCalendarOccurrence` keeps a
  report above the calendar as it keeps an overview; a fold yields
  `SchedulerBinding.endOfFrame` (injectable); a throwing fold undoes the pick
  and re-emits the last Ready; a pick equal to the shown period re-emits
  Ready so Today follows; relative rows persist their base preset; the
  overview's Month mode hands its month; `ReportFolding` carries the
  previous period and categories so the caption, the comparison, Show as
  list and the Send label describe the report they came from; calendar
  states coalesce to the newest; a resume while covered asks nothing and a
  new day re-reads the settings; `ReportLook` is a model; the empty caption
  is composed ("{period} · Nothing happened"); de "Termine", ro "rămas /
  rămase"; minutes under an hour; `comparisonName` names the counted span in
  the current tense; `ReportTotalsCard` memoizes its column decision; the
  band's blank subtitle is a no-break space (an empty string measured 1 px
  short at 1.3 and grew the band under the finger — a new test pins the
  band's height through a step and a refold at three scales). Suite
  `+11512`. Two of §4.8's numbers did not survive the build: the Totals
  template widths (D37) and the band's 52 / 64 (the title box is the
  overview's two-line box; constant, which is the rule that matters).
- **S2b — built (review in progress).** `FormMeterRow` in `form_rows.dart`
  (`meterHeight` / `meterGap` in `FormMetrics` — a form primitive's numbers
  live there; one semantics node with `container`, `button`, `expanded`,
  `onTap` over `ExcludeSemantics`; the caption in `AgendaPeriodNav`'s shrink
  box), `lib/widgets/report_trend_chart.dart` (the formatters and every axis
  `TextPainter` in `build`; the painter draws hairlines and rounded
  rectangles only; weekday and month labels switch to their narrow pattern
  when any short one is wider than a column; "usually at {time}" when there
  is a start and no durations; de "gewöhnlich"), `ReportLabels.peakOf` /
  `trendCaption` / `trendSemantics`, `report-trend`, six ARB keys, the
  OVER TIME sliver after the Totals caption, and the settings suite S2a
  left out. The suites pin the chart card at 178 / 216.4 / 268 en and 342
  de 2.0 and the meter row at 66 / 77.4 / 104 and 62 — the designer's
  numbers exactly. Suite `+11473`. Review findings fixed in one pass (D37's
  paragraph lists them): the axis fit subtracts the label gap (This year at
  360 en 1.0 and ro at 412 draw twelve labels), a missed part is at least
  `columnGap` tall, axis labels are measured with bold text and sit in a
  shrink box, each label is laid out once and `ReportLabels.trendWords`
  computes the facts once for the caption and the spoken label, column
  edges and hairlines snap to device pixels (vertically relative to the
  plot's origin, which a fractional card offset can still straddle — a
  device check), the spoken peak has one phrase per unit
  (`reportTrendPeak` / `-Week` / `-Month`) and never says "Peak 0",
  "üblicherweise", a non-finite meter fraction is zero, and the Totals card
  picks one of D37's three stages (pinned: en 1.0 stage 1 two columns and
  296; de 1.0 stage 2 two columns, value "30", detail "von 31 · …", 296; en
  1.3 stage 2; de 1.3 stage 3 one column 594 — the hours template is wider
  than half the card there; 2.0 stage 3, 844). Suite `+11531`. S2 closed.
- **S3a — built and reviewed; the fix pass is below.**
  `lib/widgets/report_category_group.dart` holds `ReportGroupRows`, a row
  builder in `AgendaDayListRowBuilder`'s shape (`rowCount`, `build(context,
  index)`, each row in its own `FormRowShell`) so the page lays every card's
  groups into one `SliverList`, builds only the rows on screen and never
  scrolls inside a group (X). The header is a `FormMeterRow` — `EventAvatar`,
  the facts caption per card (`groupFacts`: "14 · 13.2 h · 2 missed" /
  "2 missed" / "1 · 1 h"), the meter on Categories only, an
  `AnimatedRotation` fold glyph, one node with `expanded` and the spoken
  facts; routine aggregates are `FormPickerRow`s with a blank leading slot
  and the attended count as the value (K, D26); dated rows go through the
  builder's `entryRow`, made public and unshelled, with the additive
  `avatars: false` and `fadeMissed: false` flags; "n more" / "Show less" /
  "Show as list" are `FormActionRow.disclosure` rows (the label at
  `dividerIndentTitle`, a trailing glyph, one node carrying `expanded` and
  "2 more in Gym" / "Show less of Gym", one id both ways). `ReportLabels`
  gained `ReportCard`, `groupFacts`, `groupSpoken`, `routineCaption`,
  `rowSubtitle` and `hoursSpoken`; five id helpers; nine ARB keys. The suite
  pins the header at 66 / 77.4 / 104 and the child rows at 62 / 67 / 94 —
  the designer's numbers — and de 2.0 on 360 in both themes. Suite `+11553`
  from the lead (the implementer's own run hung on the editor save test's
  ten-minute timeout, the known runner hang). The review found no blocker,
  seven defects and eight nits — the spoken hours disagreeing with the shown
  figure, the German day label, the borrowed day-panel subtitle, the ro
  plural, the aggregate's missing tap day, the unaddressable in-group "Show
  as list", a test asserting nothing — ruled in D38 and fixed in one pass
  with the review's missing-coverage list added to the suite. The fix pass
  (suite `+11582`) found two more things on the way: `FormRowShell` wraps
  only a *last* row in its gap `Padding`, so a header going from closed
  (last) to open changed widget shape, lost its `AnimatedRotation` state and
  never animated — the report's rows carry the gap in a keyed `Padding` of
  their own around `FormRowShell(trailingGap: false)`, and the shared shell
  is a §9 item; and intl's `E` / `MMM` skeletons are `ccc` / `LLL`, German's
  standalone "Do" / "Okt", so the day and month names come from the date
  symbols' format forms ("Do., 8. Okt."). 1203 minutes draws "20.1 h" (intl
  rounds 0.05000…0711 up) and is pinned as drawn. The pinned subtitles:
  "Thu 8 · 17:00 · 1 h", "Thu 29 · 32 years", "Fri 30 · 5 of 8 tasks",
  "Thu 8 · 18:00 · 1 h · Week 3", "Thu 29 Oct · 32 years" across months.
- **S3b — built (review below).** The page's body is now Totals · caption ·
  CATEGORIES · OVER TIME · MISSED · AHEAD · footer, a card drawn only with
  content — a plan gets Categories alone because the builder leaves `missed`
  and `ahead` empty in the future tense, no tense switch on the page (H, T).
  The fold state is the page State's, per visit, keyed by card and category
  (`_open`, absent = open; `_expanded`), kept across steps and refolds. The
  Categories card shows `maxCategoryRows` groups and then one "n more
  categories" disclosure row in its own shell, disabled until S3c opens the
  sub-sheet from it (V); the meter's fraction is the group's count over the
  card's largest (0 over 0 is 0); the month joins a row's day when the span
  crosses a month (U); a group's Show as list hands the overview the folded
  span and that one category; the Missed card's presence button writes the
  static `EventSheetsFlow.setOccurrencePresence` and the report bloc refolds
  on the calendar bloc's next state by itself; the row taps wait for S3c.
  **One deviation from the brief: each group is its own `SliverList`** under
  a `GlobalKey` per (card, category), not one list per card — after a fold
  the sliver re-anchors its built children by index, and with one list per
  card a later group's rows took the offsets of the rows folded away ("n
  more" landed 7 px off above another long open group); a group's own list
  either keeps exact offsets or re-lays out from its own index 0. Rule S:
  "Show less" reads the height of a built child row (and of the "Show as
  list" row when the group is capped) from the group's
  `RenderSliverMultiBoxAdaptor`, computes the removed extent, and jumps the
  one `ScrollController` *before* `setState`, so the folded frame is laid
  out once at the corrected offset — no second-frame jump, no jump when
  nothing is built. New keys `reportSectionCategories` and
  `reportMoreCategories` (plural, ro one / few / other); id
  `report-categories-more`. Twelve page tests pin the order on a 360 × 2400
  surface, four rows + "8 more" → twelve + "Show less" with the header and
  the rows above unchanged, "Show less" at y 500 → "26 more" at 500 ± 1 after
  one frame (and a clamp to 0), seven headers + "2 more categories" disabled
  for nine categories, fractions 1.0 / 0.5, a Missed mark recorded exactly
  once with one more fold and the offset held, a group's Show as list
  handing `{rest}`, de 2.0 and dark; the suite's bloc is a recording
  subclass that drops the real presence write (a `BlocObserver` is read at
  construction, and the write reached the database and hung FakeAsync).
  Suite `+11594`. The review found no blocker, two defects (the end-of-page
  clamp after a mark or a header close; the "Show less" jump reading one
  row kind's height for both) and twelve nits, ruled in D39 and built into
  S3c together with the sheets flow.
- **S3c — built (review below).** D39 applied: the page ends in
  `_EndSlack` / `_RenderEndSlack`, a childless, paintless sliver placed
  *after* the body's `SliverPadding` (inside the group it would overshoot by
  `bodyBottom` and the clearance) — armed by `_toggleOpen` on a close, by
  `_keepMoreInPlace` before its `setState`, and by `build` when the shown
  report instance changes under the *same* look (a step or a pick never
  arms: at the end of a long month a step to a short week would otherwise
  leave the viewport on blank ground, since the band, not the content, was
  pressed); its first armed layout remembers `scrollOffset +
  remainingPaintExtent` and every layout after keeps the minimum, so the
  room only drains. The pins: a mark on the last Missed row at the page end
  keeps the MISSED label, the header and the offset (`maxScrollExtent ==
  offset`); a drag back of 100 / 200 moves the header by exactly that, and
  `maxScrollExtent` then equals a fresh page's; a mark that empties Missed
  and a long Ahead group closed by its header at the end hold too. The two
  child-row kinds are pinned to one height with tolerance 0 (they were
  equal). The clamp test asks offset 40 with E > 40 → 0 and "2 more" at
  tapY − (E − 40); "nothing above moves" is asked with the header off
  screen; the "Show less" pins are re-checked after `pumpAndSettle`; the
  recording bloc's `landMark()` emits what production emits. The presence
  mark clicks behind the haptics setting and drops a repeat tap until the
  next `ReportReady`; Ahead's in-group Show as list starts at `countedTo +
  1`. The behaviour: `getCalendarReportSettings` carries `palette` and
  `hapticFeedback` (one statement, two more keys) and `ReportShown` holds
  them; the page owns a `SheetGuard`, `_keepsHeard` and an `EventSheetsFlow`
  reading appearance and palette from the bloc's state at call time;
  `AlertKeepNotice` is counted and answered with a reload while pending,
  never taken; a dated row opens the detail sheet on its day and a routine
  aggregate on `latestDay`, the event read from the `CalendarBloc`'s loaded
  list (the overview's rule — `report.events` still holds a deleted event
  during a held refold); nothing is parked, the bloc coalesces. Eighteen
  tests (page 61 → 76, settings + 2, bloc + 1). Suite `+11608 ~11 -5`: the
  known Windows failure and four failures in files the slice never touched
  (`calendar_alert_countdown_test`, `calendar_guide_practice_page_test`,
  `calendar_guide_try_cards_test` × 2 — a Saturday-after-midnight run; an
  explorer traced all four to `DateTime.now()` in those tests: the guide's
  events try card seeds Yoga on today's weekday and the ro Saturday caption
  "Săptămânal · sâm. · 18:00 – 19:00" clips at 2.0, the practice demo's
  weekly events hang off today's weekday, and the countdown test leaves the
  calendar page's prewarm `scheduleTask` pending — the owner's call, outside
  this feature). Noticed: a group list estimates its extent from the
  rows built, so `maxScrollExtent` wobbles by about 1 px with the scroll
  position — no pin may rely on an exact end. The review found two medium
  findings (an armed slack lifting the visible rows when a same-look refold
  removed extent above the viewport; held slack surviving a step) and four
  low ones, ruled in D40 and built into S3d with the sub-sheet.
- **S3d — built (review below).** D40 as built: a same-look report arms
  the slack only while one of the page's own marks is pending; a look
  change *releases* it; a shrinking bottom clearance arms (checked in
  `didChangeDependencies`, which runs before the rebuild); all of it lives
  in the bloc listener and `_buildBody` only reads. The slack sliver takes
  counts (`EndSlackSliver(arms:, releases:)`) rather than flags, because a
  one-shot flag would have to be reset in `build`. The group-stack
  machinery is lifted into `lib/widgets/report_group_stack.dart`
  (`ReportGroupFolds`, `ReportGroupStack` — one keyed `SliverList` per
  group inside a `SliverMainAxisGroup`, the lazy key map, the header toggle,
  "n more" / "Show less" with its jump, `onShrink` — and
  `EndSlackSliver`), one stack per card on the page, the 76 page tests
  green through the lift with renames only (the cap row's pin flipped from
  disabled to enabled). `ReportMoreCategoriesSheet` (V) is the filler the
  day list sheet is: the fixed box on `pageGround`, ✕ `report-more-close`
  and the title "More categories", one `CustomScrollView`
  (`report-more-list`) of the groups past the seventh through the same
  stack with its own slack, bottom padding `bodyBottom + max(viewInsets,
  viewPadding)`; it answers with a sealed `ReportSheetResult` — a dated row
  `ReportSheetPick(eventId, day)`, a routine aggregate its `latestDay`, a
  group's Show as list `ReportSheetShowList(categoryId)` — and the page,
  which opened it through its one `SheetGuard` slot, opens the detail sheet
  or hands the overview the span and that category; the sheet takes the
  card's largest count so its meters compare with the page's. Eighteen
  tests (page 9, sheet 8, the clearance entry); the three D40 pins fail
  with their mechanism disabled (610 vs 225, 330 vs 267, 640 vs 577). Suite
  `+11626 ~11 -5`, the same five. The QA flow `28_report.txt` (the lead):
  the view menu's third entry, Last 90 days, the Strength group closed and
  reopened, the Lifting aggregate's detail sheet, the Missed Other group's
  "n more" and "Show less", the footer's rows, back through the view menu.
  The review found one medium finding (the keyboard arm re-measuring the
  whole reach) and four low ones, ruled in D42 and built in a fix pass
  after S4a (the two shared the page file). **Device pass 2026-10-31
  01:37** (`qa pass calendar -d emulator-5558` — the owner's Pixel 9 Pro XL
  held the default port, so the second fleet guest ran it): 27 of 29 green;
  `11_tier1_sheets` red on the `{{longdate+2}}` month-page trap (31 October
  + 2 has no cell — the flow's, not the app's); `28_report` red twice on its
  own `expect`s of ids below the fold (`expect` never scrolls, and even This
  month fills a phone with the seed's groups) — the checks moved behind the
  `scroll-to`s that reach them and the flow went green on a rerun; `qa
  errors` clean. The screenshots match the mock: the four tiles with their
  deltas against May 5 – Aug 2, the caption "To October 31 · against … · 1
  ahead", Strength and Gym groups with meters and the Lifting aggregate "7
  of 8 attended · 10.5 h", the weekly chart with its missed part and "Most
  on Monday · usually 6:00 PM – 7:30 PM", the Missed Other group's Standup
  rows with their presence buttons. **The D42 fix pass** (suite `+11665`):
  the slack credits the clearance's shrink per layout (`EndSlackSliver`
  takes `clearance`), the mark's arm is keyed on a pending `(eventId, day)`
  leaving the Missed rows, a release clears a pending arm and the clearance
  credit, the sheet shares `_folds`, a sheet row's second activation is
  dropped (red before the fix only through `SemanticsAction.tap` twice — a
  pointer pair is absorbed by the popping route), the counts ride a
  `ValueNotifier`. Two premises did not hold in the harness: an offstage
  page's viewport is still laid out (a relayout boundary), so the old arm
  was spent harmlessly offstage; and a refold cannot be made to land in the
  frame of a keyboard close through the robot — forced by hand, a 300 px
  one-frame close still lifts the footer by that frame's whole credit (a
  real close animates over ~250 ms, so the residual is one frame's slice; a
  signed slack that also debits growth would zero it at the price of giving
  up the hold after a scroll into the keyboard's padding — not taken, §9).
  A mark whose write fails keeps its row quiet until a later report drops
  the row (the existing test now pins that instead of a second tap).
- **S4a — built (review below).** `DigestCadence.weeklyReport` /
  `monthlyReport` after `monthly` with `isReport`; `fromName` and the decode
  seam untouched (both names pinned readable and enabled on this build, an
  unknown name still disabled); `clampAnchor` like the twins. `_fireDays`
  shares the weekly / monthly branches; `spanFor(digest, fireDay, {weekStart})`
  — a weekly report is the week holding the fire day stepped back seven
  days, a monthly report `utc(y, m − 1, 1)`..`utc(y, m, 0)`, `leadDays`
  never read; the scheduler's `_reconcile` passes the week start, the hub
  and the editor keep the Monday default (an S4b item: a Sunday week start
  would show the hub a span other than the armed one).
  `digestNotificationContent(…, {CalendarReport? report})` sends report
  cadences to `_reportContent`: title "Weekly report · {categories}", the
  summary line as the text and the first line, one line per category after
  it (P), `kDigestMaxLines` and "+n more" kept; without a report the one
  ready line; `digestPeriodOf` "Last week" / "Last month"; `digestDescribe`
  two cases ("Weekly report on {weekday}, {time}"). The scheduler folds
  through one lazily created `CalendarReportService` per pass only when
  date-only now is past the span's end (no previous span, the digest's
  categories, the pass's events; a throwing fold logs and falls back to the
  ready line), resolves `EventPresenceService` quietly when an enabled
  report digest exists (the fold reads the presence facade), and stamps
  `page: report` (`AlertPayloadKeys.page = 'pg'`, `AlertPayload.reportPage`,
  written only when set, a wrong type reads as absent). Routing:
  `AppNavigator.toDigestTarget({payload, span})` — `main.dart` calls it —
  sends `page == report` to `toCalendarReportLook`, which publishes
  `pendingReportLook` and collapses onto a live stamped report or pushes
  `CalendarReportPage(look:)`; `reportPeriodOf` (seven days → week, a
  calendar month → month, else custom); `servesReportLook`. The bloc's
  `ReportLookArrived(look)` sets period and home, the allowlist and folds,
  persisting the allowlist when it changed and never the period — what the
  overview's `_listLook` persists for a served look; the pushed path goes
  through `ReportOpened(look)` (the period persists only as a kept kind,
  which a closed week or month never is). `CalendarBloc` requests
  `reconcileAllQuietly` after a presence write, gated on an enabled report
  digest; skips already run `_reconcileAlerts`, a full re-plan, so no
  second pass. The words pinned (en): "Events — 2 of 3 attended · 4.5 h · 1
  missed", "Birthday — 2 events", "Gym · 2 of 3 · 2.5 h", "Birthday · 2 ·
  Ana, Mihai" (each title once), "To do · 2 · 2 of 3 tasks", "Mobility · 1
  · 2 h", "Last week's report is ready"; eight categories fold to five and
  "+3 more". `digest_editor_sheet.dart` got a compile-only mapping (the
  Shows row is S4b's). Twenty-nine tests; suite `+11655 ~11 -5`, the same
  five. The review found two medium findings (the fold gate one day late;
  "0 of 0 attended" beside three birthdays) and six low ones, ruled in D43
  and built into S4b with the Shows row.
- **S4b — built (review below).** The editor's **Shows** row before Every
  (`digest-shows`; `digest-shows-upcoming` / `-week-report` /
  `-month-report`), read from the cadence: a report Shows sets the cadence
  to `weeklyReport` / `monthlyReport`, Upcoming restores the last upcoming
  cadence (weekly when the sheet opened on a report); under a report Every
  reads "Week" / "Month" disabled and Covers is disabled, On / At / Also
  when empty stay; the anchors are seeded for the report cadences and the
  On branches gated on both twins (D43); the caption plan takes the week
  start. The hub's `digestEntries()` reads the week start (Monday on a
  failed read), so a Sunday-start row describes the armed span. The
  footer's Send row opens the editor through the page's `SheetGuard` with
  a draft (`id: ''`, the cadence by the period's kind — a custom or year
  period is monthly —, the anchor the week start's weekday or the 1st,
  08:00, the folded allowlist) and dispatches `SaveEventDigest` +
  `AlertPermissionCheck.afterSave` as the hub does; the sheet now treats an
  id-less `initial:` as a new digest (title, no Delete, Save returns it,
  the cap applies) — before, any `initial:` was an edit. D43 in the
  scheduler: the fold from the span's last day; the words inside the try
  with a retry on `report: null`; `page` in the arm signature only when set
  (upcoming digests keep their hash — §5); the summary through
  `digestReportSummary` with `reportAttendedOf` only when the tile counts;
  a routine line's hours from its rows; `ReportLabels.count`. The alerts
  flow walks the Shows row (three items, a week report leaves every row in
  place, Upcoming back, On "1st") and saves nothing. Twenty-three tests;
  suite `+11689 ~11 -5`, the same five. The review found two medium
  findings (a last-day fold leaving that day's unmarked assume-present
  sessions out with nothing to refold them; "5 events Last week"
  mid-sentence) and ten low ones, ruled in D45 and built in the S4c fix
  pass. **S4c** (suite `+11717`): `_closedReport` folds as of the day
  after the span (a Sunday 20:00 pass over a Mon / Wed / Fri / Sun tracked
  hour reads "4 of 4 attended · 4 h" unmarked and "3 of 4 · 1 missed" with
  Sunday marked); the period words lowercase with prepositions ("5 events
  last week", "5 Termine im letzten Monat") and in the caption's
  templates; the week report's weekday is held apart (`_reportWeekday`,
  seeded to the week's first day, an edited week report keeps its own) so
  the Upcoming weekday survives a round trip; the every-category summary
  is the facts alone and a named selection keeps the prefix
  (`digestCategoriesLabel` names one category and counts from two — D45's
  "names up to two" corrected to what every digest title does);
  `decimalPattern` on the seven report plural keys ("1.200 von 1.234
  anwesend"); the Send row null-tapped at the cap, its default minute
  `kDefaultAlertDayMinute` (09:00, `event_alerts.dart`), `_sendReport`
  respecting `_pickerOpen` and the pickers `_sheetGuard.isOpen`; de "Der
  abgelaufene Monat"; the arm signature of an upcoming payload pinned byte
  for byte (`'ctx~d#617d4234'`, a null `page` adds no element); the
  fold-throw fallback (`AlertScheduler.forTesting(reportService:)`); the
  disabled Every / Covers rows at 38 % with disabled semantics and their
  height; de and en 2.0 with the long Shows values; fixed clocks
  (`DigestEditorSheet(now:)`); a hub fire row "5 events last week"; the
  alerts flow scrolls the sheet body (`digest-sheet-body`) back up to the
  Shows row.
- **S5a — built.** Share report as Markdown (K): `ReportMarkdown.render`
  (`lib/utils/report_markdown.dart`; every word through `ReportLabels`,
  every group and row, no cap; a plan stops after Categories; Over time
  only with a caption) and `ReportMarkdown.fileName(span)`
  (`anta_report_<yyyyMMdd>-<yyyyMMdd>.md`); `ImportExportService.exportText`
  beside the `.ics` writer; `ExportTextRequested({fileName, text, format,
  share})` and `ImportExportOperation.exportText` with their own
  "Report exported" / "Could not export the report" words
  (`exportingReport`, `reportExported`, `reportExportError`);
  `CalendarExportController.startText` remembers which operation it
  started so one `onState` answers either export; the footer's Share row is
  disabled on an empty report and otherwise blurs and starts the export
  with the page's labels, 24-hour setting, period name and comparison. The
  golden (en, 24-hour): `# Report · September 2026` / `31 events · 3
  missed` / `*To September 30 · against August 2026 · 2 skipped*` / `##
  Totals` with `- Attended: 21 of 24 · 88 % · +2` … / `## Categories` with
  `### Gym · 14 · 13.2 h · 2 missed` and `- Gym · 8 of 10 attended · 8 h`,
  `- PT session · Thu 10 · 17:00 · 1 h` … / `## Over time` / `## Missed`.
  D44: the Hours tile speaks "45 hours, 3 hours more than …"; de "Termine"
  on the tile; a bare count says "1 event"; `reportDeltaFewer` for counts
  (de the same words, ro "mai puține" against the mass "mai puțin"); the
  Send labels de "Wochenbericht senden" / "Monatsbericht senden" (the
  briefed "Bericht wöchentlich senden" measured three lines at 2.0 on 360)
  and ro "Trimite raportul săptămânal" / "lunar", pinned at two lines;
  `FormTrailingGlyph` (`trailingIconSize`, `onSurfaceVariant` default) is
  the disclosure row's glyph part. **The dropped semantics frame (D44) was
  not reproduced** in about seventy variations of the page suite (de 2.0,
  412 × 915, three pixel ratios, every route, the slack armed, semantics on
  before / after the jump); reading the SDK, the null at
  `_buildSemanticsSubtree` is a semantics *node's* geometry, which the
  childless slack sliver never forms — the Flutter 3.44 class behind
  `FormSheetSemanticsRefresh` (a node's geometry cleared while its nearest
  clean ancestor is blocked); one dropped frame that recovers, pinned as a
  no-throw case and left in §9 with the design reviewer's harness to
  recover. Sixteen tests; suite `+11705 ~11 -5`, the same five. Noticed:
  `OptimizedFolderContentPage` listens to the app-wide `ImportExportBloc`
  with no route guard, so an export under a calendar page shows its
  loading dialog and failure snackbar twice (the `.ics` export already
  did; §9). The review found one medium finding (no in-flight guard on
  Share) and eleven low ones, ruled in D46 and built in the S5c fix pass.
  **S5c**: Share and the ⋮'s export return while one is pending (two taps →
  one request; a Share during a pending `.ics` export adds nothing); the
  browser page's listener returns for `exportCalendar` and `exportText`
  before its dialog, bar and reset (a control pins `exportNote` still
  heard); `ReportMarkdown.escapeMarkdown` on titles and category names
  (``\ ` * _ [ ] # < >`` anywhere, a leading `+` / `-` / `digits.` /
  `digits)`; a marker mid-text left alone; a `*Lifts*` category and a
  `# Plan` title pinned); a missing event asserted with the page's wording
  and skipped in release; `exportText` asserts a bare name with the
  format's extension and cleans a half-written file up itself (the bloc
  has no path when the write throws; a `writeExportText` seam fails a
  write mid-file in the test); `tileValue`, `detail`'s "of N" and
  `groupFacts` through `count()` ("1,234 of 2,345", de "1.234");
  `reportDeltaMoreCount` / `reportDeltaFewerCount` (`decimalPattern`) for
  every non-hours tile — ro one "cu 1 mai mult / mai puțin", few and other
  "cu {n} mai multe / mai puține" with no "de" (the number qualifies the
  comparative, "cu 25 mai mulți") —, the hours keep the mass forms,
  `reportDeltaFewer` removed; de "Wöchentlich zusenden" / "Monatlich
  zusenden" at two lines; the header's fold glyph a `FormTrailingGlyph`;
  the Markdown's Ahead section with "Thu 8 Oct" / "Sun 1 Nov" and a
  12-hour clock, a caption-less trend left out, the page's share text
  equal to `ReportMarkdown.render` of the shown report with its
  comparison, the D44 pin with no pump between the jump and the push. Suite
  `+11751 ~11 -6` with one test of its own red (a listener test pumped
  once; fixed with a two-pump `hear()`, the three files re-run green —
  the lead's final run confirms). Noticed: `ReportLabels.delta` prints
  "+1234" ungrouped and `_figure` would split "1,234,567" into two runs;
  the browser's `_progressMessage` / `_failureMessage` keep two
  unreachable arms; `exportCalendar` still has the half-written-file gap.
- **S5b — built (review below).** `CalendarGuideTopic.report` (slug
  `report`, `bar_chart_rounded`, after `attendance` so the hub's "How do I"
  lists it right after "did I go"; no "Try it" card, like `good`): title
  "See what happened", caption "A week, a month or a year, by category", a
  lead quoting the page's name through a placeholder, and **four** read
  rows — the guide's own rule caps a page at four, so the lead's seven
  lines were merged: `report-open` "Opening it" (the title's three pages,
  the period between the arrows), `report-categories` "Which categories"
  (the filter button, one group per category with a meter against the
  biggest, four rows then "3 more" in place, a header tap folds),
  `report-missed` "What you missed" (marked or assumed absent; the button
  beside a row marks it present and the numbers refold), `report-digest`
  "Every week by itself" ("Send me this report weekly" → last week's
  numbers on the first day of each week, a digest with Shows = The week
  just ended; "Share report" writes the page as Markdown) — every app label
  in them an existing key through a placeholder (`reportGroupMore(3)`,
  `reportSendWeekly`, `reportShare`, the period names). Eleven
  `calendarGuideReport*` keys; §7.5's keep list gains the four slugs; the
  hub counts thirteen rows. The two sandboxed view menus now say what the
  picked page would open (`_openPage(CalendarViewPage)` on the practice
  page and the try screen; the Report line sized into the band and the
  slot). Guide suites `+429 −3` (the three Saturday cases). The review
  found three medium findings (the lead at 176 characters against the
  guide's one-sentence 75; the digest row quoting only the week label the
  page does not show on its default month; the one task page without a
  "Try it" card — accepted: its practice is the real page, the skill's rule
  amended) and eleven low ones (labels retyped against D5, "four rows" as a
  literal, "refold", a ro antecedent, key names off the sibling pattern,
  the 412 size loop, the skills' "ten topic pages"), ruled in D47 and built
  in the S5d pass: the lead "“Report” counts a week, a month or a year,
  category by category." (64 characters); every label a quoted placeholder
  (`calendarCategories`, `upcomingPeriodCustom`, `eventMarkPresent`, both
  Send labels, `digestShows`, both Shows values, `reportShare`); the
  preview count and the category cap from `ReportMetrics` with
  `decimalPattern`; the digest row names both labels and the save; "the
  numbers update"; `calendarGuidePageReport` / `…Caption` ("Totals, missed
  days and what is ahead" — the lead's last edit, so the hub row's title
  and caption do not both say "what happened"); `swap_horiz_rounded` and
  `notifications_rounded` glyphs; the 412 size loop, the lead in de and ro,
  the view-menu lines in the practice page's walk, a Report-first pick on
  the screen card. Guide suites `+436 −3`.
- **The final gate (the lead, 2026-10-31 03:50):** `dart analyze lib test`
  clean; `flutter gen-l10n` with `untranslated.txt` = `{}`; the whole suite
  `+11759 ~11 -5` — the Windows-only `host_devices_test` and the four
  Saturday clock-dependent guide and alert tests (the S3c note), nothing
  else; 83 uncommitted files, every one the report's.

## 8. Definition of done

- `dart analyze lib` clean; the whole `flutter test` green; `untranslated.txt`
  empty; §5 re-read against the final diff.
- The three worked periods of §4.4 render as sketched from the suite's fakes
  (light, dark, `de` at 2.0 on 360 × 780, no overflow, no clipped label).
- A period that ends in the future shows "n ahead" in the caption and an Ahead
  card; one wholly past shows neither.
- Last week (R) opens on Totals · By category · Over time · Routines ·
  Happened · Missed with the hangouts and the birthday in Happened, oldest
  first; Next week opens on Planned · Hours · Tasks · By category · Ahead with
  every shape in Ahead, the gym sessions included (S, T); ◄ / ► between them
  changes the tense once.
- ◄ then ► serves the memoized model with no second fold (the service's fold
  counter in the test); a presence mark folds exactly once; no fold runs
  inside `build` (a widget test pumps the page and asserts the counter).
- The 366-day, 50-event fixture folds within the probe budget S1 records; the
  Categories card of a 40-category selection shows seven groups and one "33
  more categories" row; a 300-row group expands to 200 and "Show as list".
- A category with twelve events shows four rows and "8 more"; a tap expands
  them in place below that row and nothing above it moves; "Show less" folds
  back to four; a header tap closes the group; the page has exactly one
  `Scrollable` (W, X).
- A mark on a Missed row re-folds the tiles in place; the scroll offset holds.
- A report digest armed before Sunday midnight fires the generic line; one
  armed after fires the numbers; its tap lands on the Report page for that
  span and those categories; an older payload without `page` lands on the
  overview's List.
- `qa pass calendar -d emulator-5556` and `qa pass alerts -d emulator-5556`
  green with the new flow; `qa errors` clean.
- `OverviewPeriod` stored as `thisWeek` (D25) decodes on this build and falls
  back to This year on the previous one.

**Verified 2026-10-31 (the lead).** Every line above holds in the suites
except as noted: the gate (analyze clean, `untranslated.txt` empty, the
whole suite `+11759 ~11 -5` with the five known failures only); the three
worked periods, the plan, the empty period and the Missed card rendered in
the page suite and by the design reviewer across the matrix (D44); "n
ahead" and the Ahead card on a period ending after today; ◄ ► between Last
and Next week changing the tense once; the memo on a step back (the fold
counter), one fold per presence mark, no fold in `build`; the 366-day,
50-event fixture within budget; nine categories → seven groups and a cap
row (the 40-category and 300-row shapes are approximated by nine and 273);
four rows and "8 more", in place, "Show less", the header tap, one
`Scrollable`; a mark re-folding with the offset held, at the page's end
too (D39–D42); the report digest's generic line before the span's last
day and the numbers from it on (D43/D45), the tap landing on the Report
page for the span and categories, an older payload on the List;
`thisWeek` decoding. The passes, on `emulator-5558` because the owner's
Pixel 9 Pro XL held 5556: `qa pass calendar` 28 / 29 (`11_tier1_sheets`
red on the `{{longdate+2}}` month-page trap of 31 October, the flow's
problem, not the app's), `qa pass alerts` 5 / 5 with the Shows walk, `qa
errors` clean; screenshots of the Report page in de · dark · 200 % and in
ro under `build/qa/shots/20261031_0351*`. Not verified on a device:
TalkBack phrasing, ink clipping, the AOSP 200 % curve, the refold's feel,
the fling after "Show less" (D44's device bucket, for the owner's phone).

## 9. Deferred

- **Alarm-tier report digests** — digests have no tier (`AlertMode.notify`
  hard-coded at `alert_scheduler.dart:2007`); the digests record §11 deferred
  it; the owner's "set an alarm" is read as the scheduled notification.
- **A Done flag on one-offs** (M option 3) — `done` column + migration + backup
  + CRDT + a sheet button; only if the task-list count proves insufficient.
- **A silent re-arm at span end** so a weekly report never fires the generic
  line when the app was closed all Sunday — an alarm-manager wake with no UI;
  belongs to the scheduler, after S4 shows how often the generic line fires.
- **Public holidays and fasting days** as "days off" counts — not events;
  would need `PublicHolidays` and `FastingSchedule` reads in the builder.
- **Comparing two category sets** side by side, and streak tiles per routine
  (`PresenceAdherence` already computes them for one event).
- **Sharing a period as `.ics`** — the calendar exports everything today;
  a filtered export is a different feature.
- **Fixing the built-in palette's colour-vision collisions** — the owner's
  palette; the report routes around it (§4.3).
- **An isolate fold** — only if S1's measurement shows a fold crossing a frame
  on a low-end device; the builder is pure, so the move is one `compute` call
  around it and nothing else.
- **Year-over-year and two-selection comparison, saved reports, a home-screen
  glance** — each a second fold or a stored `(period, categoryIds)`, no
  schema change (§4.7).
- **`FormRowShell`'s conditional gap `Padding`** (S3a fix pass) — the shell
  wraps only a last row in `Padding(bottom: groupGap)`, so any stateful row
  that flips between last and not-last (a header whose group opens) loses
  its `State`. The report works around it locally (a keyed `Padding` of its
  own); the shared fix is an always-present `Padding` with a zero bottom in
  `form_rows.dart`, checked against the overview's exact extents and the
  `form_rows_test.dart` pins — an app-wide change for the `ui-language`
  master record, not this feature's.
- **A dated row's year** — the row's day is "Thu 8 Oct" at most (D38); only a
  366-day span can show the same day-and-month twice (its first and last
  day). Add the year to `reportRowDayMonth` only if a reader is ever misled.
- **A signed slack** — the end-of-page slack credits a clearance's shrink
  per layout (D42); a refold landing in the very frame of a large one-frame
  keyboard close still lifts the footer by that frame's credit. A signed
  `remembered` that also debits growth would zero it, at the price of
  giving up the hold once the reader has scrolled into the keyboard's
  padding and then closes it. Real closes animate, so the residual is one
  frame's slice; revisit only if a device shows it.
- **A midnight re-plan for report digests** — the words are folded from
  the span's last day on (D43) and rewritten by the next pass (a mark, a
  launch, a resume); a report armed on Saturday with the app untouched all
  Sunday fires Monday with Saturday's numbers. A day-change
  `reconcileAllQuietly` gated on an enabled report digest belongs to the
  scheduler, after S4 shows how often it happens.
- **The day list sheet's double activation** — a sheet row activated twice
  in one frame through semantics pops twice, the second pop taking the page
  beneath (`agenda_day_list_sheet.dart`); the report's sheet drops the
  second (D42), the day list sheet is the owner's call.
- **The dropped semantics frame** (D44) — the design reviewer saw
  `flushSemantics` throw `geometry!` null once (then recover) when a route
  was pushed in the frame right after an unsettled scroll jump at de 2.0 on
  412 wide; S5a could not reproduce it in about seventy variations and the
  SDK read points at a semantics node's geometry cleared under a blocked
  ancestor (the class `FormSheetSemanticsRefresh` works around for sheets),
  not at the slack sliver. Recover it with the reviewer's exact harness
  (the nine-category fixture, offset 3065, the sheet or a plain dialog
  pushed with no settle, `transientCallbackCount` 3) before changing code.
- **The browser page's unguarded export listener** —
  `OptimizedFolderContentPage` listens to the app-wide `ImportExportBloc`
  with no route guard, so an export started under a calendar page shows
  the browser's loading dialog and failure snackbar as well (the `.ics`
  export already did; the report's share inherits it). A route-aware guard
  on that listener is an app-wide change for `anta-context`'s owner.
- **One spoken separator** — `tileSemantics` and `trendWords` still join
  their spoken lists with a literal `', '`; `groupSpoken` uses
  `ReportLabels.spokenSeparator`. Move the other two when either is next
  touched.
