# Calendar analytics — design record (2026-11-03)

**Status: IN PROGRESS — scheduled by the owner on 2026-11-04.** Fable 5.1
wrote this with the owner on 2026-11-03 from the question "a complete,
configurable analytics system for every kind of real-life event, not just
the gym"; the owner answered the eight questions in §4. On 2026-11-04 the
owner scheduled the build ("with the focus on quality"), granted commits and
pushes to `main` at every slice boundary and as many sessions and agents as
the work needs, and named the same Fable session the lead: one Opus 5.5
implementer and one reviewer per slice (the `delegation` roster), the
designer and design-reviewer around the visual slices, the suite from the
lead. §12.2 records each slice as built; this line moves to COMMITTED when
S9's device pass is green.

This record extends `docs/calendar-report-roadmap.md` (the Report, COMMITTED
2026-10-31) and never replaces it: one page, one pure builder, one model.

Contents: 1 How to run this · 2 Why · 3 What the big apps do · 4 The
owner's answers · 5 Decisions A–Z · 6 The model (6.1 vocabulary · 6.2 kinds
· 6.3 measures · 6.4 dimensions · 6.5 one mark for every shape · 6.6
targets and goals · 6.7 insights · 6.8 due soon · 6.9 by tag · 6.10 when
and balance · 6.11 compare · 6.12 year in review) · 7 The surfaces · 8
Architecture and performance · 9 Data · 10 Behaviour (ten walkthroughs) ·
11 Facts from the tree · 12 Slices and the kick-off prompt · 13 Definition
of done · 14 Deferred.

## 1. How to run this

- **Session model.** The implementing session runs on **Opus 5.5 at high**;
  this Fable session ends at the approved plan. The lead implements nothing
  over ~50 lines itself: it briefs one `implementer` per slice (5–8 ids, the
  files and the record section named), runs the suite itself (an agent's
  background `flutter test` has hung before), then one `reviewer` per slice
  told to report by its 60th turn, then the same implementer resumed for the
  fix pass. Visual slices (S3–S6) take `designer` → the owner's yes on the
  lettered defaults → `implementer` → `reviewer` + `design-reviewer`.
  `qa-runner` runs the device pass once, in S9. No workflow, no `fable-max`,
  no second reviewer.
- **Skills.** `calendar-events` + `calendar-ui` + `ui-language` for every
  slice; `drift-migrations` for S0 and S1; `l10n` wherever copy changes;
  `flutter-principles` for the builder; `verify` for the gate; `qa-emulator`
  for S9. References and this record are read **by section** — the slice
  table in §12.1 names the sections each slice needs.
- **The gate per slice.** `dart analyze lib` clean, the whole suite green
  (one run at a time, from the lead), `flutter gen-l10n` with an empty
  `untranslated.txt` when ARBs changed, `dart format` clean, the
  must-not-change list below re-read against the diff. Then the as-built
  note into §12.2 and a ready commit offered — the owner commits.
- **Must not change.** Everything the report record's §8 pins: the card
  order for a category with no profile, the memo contract, the four nullable
  readers on `ReportRequest` (the guide's seam), `ReportMarkdown` for an
  unprofiled report, the digest's generic line; the overview's totals slot;
  `qa pass calendar` (30 flows) and `qa pass alerts` green; presence, skip
  and description semantics (soft deletes, CRDT fields, `noteId == ''`
  for global counters); the `gym_notes` directory; backup import of every
  earlier archive version.
- **Stop rules.** A red suite not green after one fix pass → stop at the
  slice boundary and write the red case into §14 with the file and the
  intended fix. The owner's "low usage" → finish the step in flight, launch
  nothing new, write what is left into §14, give a three-line check-in, stop.
- **2026-11-04 addendum — commits.** For this run the owner granted commits
  and pushes to `main` at slice boundaries, so the lead commits after each
  slice's gate (analyze, the whole suite, gen-l10n, format, the
  must-not-change list re-read) and reports the hash in §12.2; a slice may
  be split into lettered sub-slices (S0a, S0b, …) so no brief exceeds eight
  ids and independent sub-slices can build in parallel on disjoint files.
  Everything else in this section stands.

## 2. Why

The Report grades every category the same way: count, hours, attended /
missed, tasks. That is the shape of a training log. The owner's calendar
holds the rest of a life — dentist visits, rent, work hours, dinners with
friends, birthdays, trips, the car's service, vacation days, pills — and for
each of those the useful number is different:

| What is kept | The useful question | What the Report says today |
| --- | --- | --- |
| Gym, run, mobility | am I keeping the rhythm I set? | attended / missed, no target, no pace |
| To-dos, reminders, errands | how much got done, how much is overdue? | ticked boxes; an undone one-off is invisible |
| Work hours, meetings | how many hours, over the line, on weekends? | hours of timed events only |
| Rent, bills, subscriptions | paid? due soon? what does the year cost? | a count; money only through a linked note |
| Friends, family, dates | how long since I saw Ana? | a count |
| Birthdays | who is ahead this month? | a dated row |
| Trips, vacation days | days away this year, days of leave left? | a count of days |
| Dentist, car service, boiler | due? overdue? | nothing — no gap is read |
| Medication | missed doses, streak | attended / missed |
| Passport, insurance, licence | expires when? | nothing |

Two things are missing, not ten: **per-category semantics** (what to measure,
against what, with which verb) and **a mark on one-time events** (done,
paid, attended). Everything else — tags for people and projects, pace,
streaks, due dates, insights, a year in review — is folding the same samples
differently once those two exist.

## 3. What the big apps do

Checked against each product's own documentation:

| Product | Groups by | Measures | Needs from the user |
| --- | --- | --- | --- |
| Google Calendar Time Insights | colour | hours per colour, hours in meetings, breakdown by day | nothing; colour is the label |
| Microsoft Viva Insights | meeting vs focus vs after-hours | hours, focus-time goal, "quiet days" | a goal |
| Reclaim.ai | habit · task · meeting | hours per kind; habit adherence against a target frequency | a target per habit |
| Apple Fitness / Health | ring per metric | move / exercise / stand against a daily goal; streaks; trends vs 90 days | a goal per ring |
| Streaks, Loop, Habitica | habit | done / planned, streak, completion rate, weekday strength | a target per habit |
| Toggl, Clockify | tag / project / client | hours per tag, against a weekly goal; billable money | tags on entries |
| Todoist, Things | project / label | completed per day and week, overdue, carry-over, "karma" | nothing; done is a state |
| YNAB, Monarch | category | spent vs budget per month, upcoming bills, subscriptions' yearly cost | a budget per category |

Three things are common to all of them: **the user supplies the grouping,
never the inference** (no product reads a title and decides it is work);
**the measure is a short fixed menu** (time, count, completion, adherence,
money); **a goal turns a number into a judgment** (rings, pace, streaks,
budgets exist only where the user stated a target). What none of them has
is one place where the gym, the rent, the dentist and the friends are graded
each by its own rule — because each app owns one domain. A personal
calendar owns all of them; that is the opening.

## 4. The owner's answers (2026-11-03)

| Question | Answer |
| --- | --- |
| Sources | **Calendar events and what they link** — marks, skips, task boxes in descriptions, the money ledger of linked notes. Not notes outside the calendar, not counters. |
| "Done" on one-time events | **One mark for every shape** — the presence mark extends to one-offs; the verb follows the kind. |
| Second dimension | **#tags in the title and the description** — people, projects, places, cars. |
| Configuration | **Kinds + overrides** — a kind per category presets everything; every field stays overridable. |
| Where | **The Report page grows** — no new destination. |
| Nudges | **Digests only** — goals and due-soon ride in the weekly / monthly report digest; no new alert kind. |
| Life areas | **All four** — health & body; work, study & money; people & family; home, travel & admin. |
| The prompt | **A kick-off prompt, written now, not run now** — only design and documentation in this session. |

## 5. Decisions

Lettered so a later session can cite them. The owner's answers are decisions
A–F; the rest are the lead's defaults, reversible until the slice that
builds them ships.

- **A — Sources are the calendar's.** Events, `EventPresence`, `EventSkips`,
  `OccurrenceDescriptions`, the task syntax over description texts, and
  `NoteMoneyLedgerService`'s per-note net for linked notes. No note-date
  dimension, no counter history (§14).
- **B — One mark for every shape.** `EventPresence.appliesTo` and
  `EventSkips.appliesTo` stop excluding `OneTimeRecurrence`; a one-off whose
  category's kind marks (§6.2) tracks presence by default and can be
  cancelled. The mark's verb — Done, Paid, Attended, Taken, Met, Renewed —
  is the kind's; the storage, the facade, the sample and the report path are
  the ones routines use today. No second mark system, no `done` column.
- **C — Tags are the second dimension.** `MarkdownTagSyntax`'s token rule
  runs over the title, the description and the per-day texts at fold time;
  a tag is a person, a project, a place or a thing by the owner's
  convention, never typed. No schema, no tag table: text already stored.
- **D — A kind per category, with overrides.** The kind is a preset row in
  a static catalogue (`CategoryKinds`, §6.2): default area, primary
  measure, mark verb, whether new events track presence and assume absent,
  which targets the goal sheet offers, which insight rules run, whether the
  category counts toward hours and balance, a suggested "counts as". The
  profile stores the kind and only the fields the owner overrode; the
  *effective profile* is the kind's row under the overrides, resolved in one
  pure function. A category without a profile is kind **Custom with nothing
  overridden**, which renders exactly today's report.
- **E — The Report grows.** New cards join the one scroll under the same bar
  and band; new period presets join the period menu. The view menu stays
  Calendar · Overview · Report.
- **F — Digests carry the judgments.** The weekly / monthly report digest
  gains a goals line, a due-soon line and the top insight. No due-soon or
  pace notification is armed; nothing new in the alert tiers.
- **G — The profile is its own table, `calendar_category_profiles`**, the
  `calendar_category_alerts` precedent (v42 migration, `_syncedTables`,
  backup `categoryAlerts`): the same CRDT columns and `ownerId`, one row per
  category, absent until the owner sets a kind. The categories table and
  the categories rework's pins are untouched.
- **H — Eleven measures, folded for every category; one primary leads.**
  Count · Events · Hours · Attendance · Cancelled · Tasks · Money · Last
  seen · Lead time · Timing · Days until (§6.3). The primary is the header's
  number, the meter's scale, the goal's unit and the digest's word.
- **I — Untimed occurrences earn hours only through "counts as".** A kind
  *suggests* a nominal duration (Work 8 h, Task 30 min, Chore 30 min); the
  editor shows the suggestion as the row's hint and the owner confirms it
  with one tap; until then untimed occurrences yield no hours. A number the
  owner never set must never appear in a total. Nominal hours are flagged in
  the model and footnoted on the page.
- **J — One target per category, four kinds.** *At least N per period*, *at
  most N per period* (periods: day · week · month · year), *at most N days
  between* (the gap), *budget* (at most N money per month; Money primary
  only). The unit is the primary measure's. Percent-adherence targets and
  rolling windows are deferred (§14) — a calendar period has a "by Sunday"
  to pace against; a rolling window does not.
- **K — Pace, not scolding.** A current period shows done, expected-by-today
  at an even rate, and what remains; an *at most* target says "9 h left"
  and, past the line, "4 h over" in plain words — a limit informs. A past
  period is met or not, one word. Streaks count consecutive complete
  periods met (G of the first draft), beside the routine's day streak
  `PresenceAdherence` already computes.
- **L — Insights are an enumerated rule library** (§6.7): each a pure
  function of the folded model, with a severity, the category or tag it
  points at and a tap target; ranked; three on the page, one in the digest;
  never a sentence a tile already says. Thresholds are constants in
  `AnalyticsMetrics`, never literals.
- **M — Balance is by life area, derived from the kinds.** Every kind has a
  default area (health · work · money · people · home · leisure · other),
  overridable per category; the Balance card is hours by area. The roles
  enum of the first draft is withdrawn: the kinds already carry the
  taxonomy. Custom splits (Work vs Life as the owner defines them) are
  Compare over two saved overview views.
- **N — A year is a span like any other.** The report already clamps a
  Custom span at 366 days (its D33); a calendar year fits one fold. The
  Year in review cards (§6.12) draw when the span is a whole calendar year
  and read the same model. "All time" stays the overview's.
- **O — Due soon is a card and a measure, not a scheduler.** Gap targets and
  Expiry events fold into "due in n days / overdue by n", ordered; the card
  is the real-life "what needs doing" view; nothing arms (F).
- **P — Money is read, never recomputed.** `moneyFor(eventId)` returns the
  ledger's net for the linked note; the builder sums per category and per
  tag in the global currency and splits spent (negative) from received
  (positive). A category with no linked notes never shows Money.
- **Q — Lead time reads `createdAt`.** The column exists on the events
  table and is not on the Dart model; S0 surfaces it (no schema change).
  Lead time = days from creation to the first occurrence day, one-offs
  only; the median per category.
- **R — No persisted rollups.** Every new number is an O(samples) pass over
  the list the report already builds, plus one lookback probe per category
  that reads a gap. The builder stays pure so the escape, if a device
  measurement ever demands it, is one `compute` call.
- **S — Backup version 8 accepts 7 and every earlier version.** Profiles
  export beside `categoryAlerts`; `importX` preserves stamps; a profile
  whose category the archive does not hold is dropped with a count in the
  summary.
- **T — Working days and public holidays are caption context.** The Totals
  caption of a month or year names "22 working days · 1 public holiday";
  `PublicHolidays` is pure Dart and the Leave and Work kinds read better
  against it. Fasting days stay out (the report record's deferral stands).
- **U — Kinds pre-fill a new event's switches, never rewrite an old one.**
  When the owner picks a category in the event editor for a *new* event,
  "tracks presence" and "assume absent" take the kind's defaults; an
  existing event keeps what it has. The template editor does the same.
- **V — The guide is untouched until goals have been used.** The screen
  stage renders the real Report from a seed with no profiles, so it is
  pixel-identical; a guide card for kinds and goals is S8's call.
- **W — Settings hold the card list and nothing else.** Settings → Calendar
  → Report: a reorderable list of cards with a switch each, through
  `SettingsKeys`; the profile itself lives with the category, never in
  settings.
- **X — Counters are not a source.** `CounterValues` holds a value without a
  date; a counter history is a feature of its own.
- **Y — A tag is `#name`, untyped.** The By tag card shows the top tags by
  the page's primary measures with their last-seen day; a tag's tap expands
  its rows in place. No "is a person" flag, no tag table, no tag scope in
  the request for the first build (§14).
- **Z — Thresholds, caps and suggested durations are constants.**
  `lib/constants/analytics_metrics.dart` beside `report_metrics.dart`: the
  insight thresholds, the card caps, the late-hour line per kind, the
  suggested counts-as per kind. No literal in a rule or a widget.

## 6. The model

### 6.1 Vocabulary

| Word | Meaning |
| --- | --- |
| **Shape** | routine · repeat · one-off, as the report defines them from the rule and `tracksPresence`; unchanged, except that a one-off may now carry marks. |
| **Kind** | a preset row of the static catalogue (§6.2) chosen per category. |
| **Area** | one of health · work · money · people · home · leisure · other; the kind's default, overridable. |
| **Profile** | the stored row per category: kind + overrides. **Effective profile** = kind row under overrides. |
| **Mark** | the per-occurrence state a tracked event carries: kept (the verb), missed, or cancelled (a skip). |
| **Measure** | one number a category or a tag yields over a span (§6.3). **Primary** = the one that leads. |
| **Target** | the goal the owner stated on the primary (§6.6). **Goal** = a target evaluated over the span's periods. |
| **Insight** | one ranked sentence from a rule (§6.7). |
| **Tag** | `#name` in a title or a text; a person, project, place or thing (§6.9). |
| **View** | the overview's saved `OverviewView` (period, options, category ids); Compare folds two. |

### 6.2 Kinds — the catalogue

Static, in `lib/constants/category_kinds.dart`; the picker groups them by
area. A kind sets defaults only; every column is overridable in the profile
except the catalogue's own identity. "Marks" = new events in the category
track presence; "assume absent" = an unmarked past day counts missed
(`assumeAbsent` on the event, the v37 rule). "Hours" = the category counts
toward Hours and Balance. "Suggests" = the counts-as hint (I), never applied
unconfirmed.

| Kind | What goes in it | Usual shape | Verb · marks · assume absent | Primary (secondary) | Targets offered | Hours | Suggests | Area |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Routine** | any habit kept on a rhythm: stretching, journaling, cold shower | routine | Done · yes · yes | Attendance (Count) | at least / period; gap | if timed | — | health |
| **Workout** | gym, run, swim, class, PT | routine | Attended · yes · yes | Attendance (Hours) | at least / week; at most gap | yes | 60 min | health |
| **Medication** | pills, supplements, injections, exercises prescribed | daily routine | Taken · yes · yes | Attendance | at least / week | no | — | health |
| **Sleep** | the night, logged on its start day with its duration | timed one-off or daily | — · no · — | Hours (Timing) | at least / day | no (own card) | — | health |
| **Episode** | illness, symptom, migraine, cycle, flare | one-off, often multi-day | — · no · — | Count as days (Events, gap) | — | no | — | health |
| **Appointment** | doctor, dentist, therapist, vet, hairdresser, an office | one-off | Attended · yes · yes | Events (Last seen, Hours) | gap | yes | 60 min | health |
| **Work** | shifts, working days, work blocks | all-day or timed, recurring | — · no · — | Hours (Count as days) | at most / week; at least days / month | yes | 8 h | work |
| **Meeting** | calls, stand-ups, reviews | timed, recurring or one-off | — · no · — | Hours (Count) | at most / week | yes | 30 min | work |
| **Task** | to-dos, reminders, errands | one-off | Done · yes · yes | Tasks when boxes exist, else Count | at least / week | if confirmed | 30 min | work |
| **Deadline** | submissions, filings, returns | one-off | Done · yes · yes | Events (Lead time) | — | no | — | work |
| **Study** | courses, classes, practice, reading | routine or sessions | Attended · yes · yes | Hours (Attendance) | at least hours / week; at least / week | yes | 45 min | work |
| **Bill** | rent, utilities, subscriptions, insurance premiums | monthly repeat or one-off | Paid · yes · yes | Money, else Count | budget / month | no | — | money |
| **Income** | salary, invoices paid, rent received | monthly repeat or one-off | Received · yes · yes | Money | — | no | — | money |
| **Social** | dinners, calls, dates, visits, hangouts | one-off | Met · yes · **no** | Events (Last seen, Hours) | at least / month; gap | yes | 120 min | people |
| **Anniversary** | birthdays, name days, anniversaries | yearly repeat | — · no · — | Count | — | no | — | people |
| **Chore** | cleaning, laundry, groceries, plants, pet care | routine or one-off | Done · yes · yes | Count (Last seen) | at least / week; gap | if confirmed | 30 min | home |
| **Maintenance** | car service, inspection, boiler, filters, vaccines | one-off or yearly repeat | Done · yes · yes | Last seen (Money) | gap | no | — | home |
| **Expiry** | passport, ID, licence, insurance, domain, warranty | one-off in the future | Renewed · yes · no | Days until | — | no | — | home |
| **Trip** | travel, holidays away, weekends out | multi-day one-off | — · no · — | Count as days (Events as trips, Money) | at least trips / year; at least days / year | no | — | leisure |
| **Leave** | vacation days, days off, bridge days | all-day one-off or multi-day | — · no · — | Count as days | at most days / year (the allowance) | no | — | work |
| **Custom** | anything else | any | the owner picks | the owner picks (auto until then) | all | the owner picks | — | other |

Auto (Custom with no primary set) resolves as the first rule that holds over
the span's events: all tracked → Attendance; any timed or counts-as
confirmed → Hours; any task box → Tasks; all repeats → Count; else Count.

Notes on three of them. *Social* does not assume absent: an unmarked past
dinner happened; the owner marks only the ones that fell through. *Sleep* is
the only kind whose Hours are excluded from Balance by default (eight hours
a night would dwarf every area); it has its own card facts (average per
night, short nights, bedtime regularity from `Timing`). *Episode* carries
the gap statistics — average days between, longest, "next expected in about
n days" from the average — in neutral words; a cycle, a migraine and a cold
are the same arithmetic.

### 6.3 Measures

Every measure folds per category and per tag from the `ReportSample` list
(`eventId, dayUtc, missed`) the report already builds, a `cancelled` flag
the skips add per sample, and three readers (`moneyFor`, `createdAtOf`,
`textsOf`).

| Measure | Value | Denominator / unit | Reads | Applies to |
| --- | --- | --- | --- | --- |
| **Count** | kept occurrence-days | — | samples | every shape; a multi-day one-off counts a day per day (as today) |
| **Events** | distinct events with a kept day in the span | — | samples | one-offs: trips, appointments, deadlines |
| **Hours** | Σ `EventTime.durationMinutes` of kept timed days + confirmed counts-as of kept untimed days | minutes; the nominal part flagged | samples, events, profile | routine, one-off; repeats only when timed |
| **Attendance** | kept tracked days | tracked days to today; percent | samples | any tracked event, one-offs now included |
| **Cancelled** | skipped days | planned days incl. skipped; percent | skips | any skippable event |
| **Tasks** | ticked items | all items | texts (the existing cache) | one-offs; routines with per-day texts |
| **Money** | Σ net cents of linked notes whose event's start day is in the span | cents, global currency; spent / received split | `moneyFor` | any event with a `noteId` |
| **Last seen** | days from the last kept day before today to today | days | samples + one lookback probe | one-offs and repeats; the gap target's input |
| **Lead time** | median of (first occurrence day − `createdAt` day) | days | `createdAtOf` | one-offs |
| **Timing** | median start minute; days after the kind's late line; weekday histogram | minutes, count, 7 bins | timed samples | timed events |
| **Days until** | days from today to the next occurrence | days | ahead samples | Expiry, the next of anything |

Rules: a missed day contributes to Attendance's denominator only; a
cancelled day to Cancelled only; a future day to Count only in the future
tense; nominal hours never to a repeat (Anniversary) or to Sleep; Money
once per event per start day, never per recurrence (the ledger's rule).

### 6.4 Dimensions

Category (the page's groups) · kind · area (Balance) · event (rows inside a
group) · tag (By tag; §6.9) · weekday and hour band (When) · period bucket
(the trend: day / week / month by span length, as built) · tense (counted /
ahead). Every dimension is a bucketing of the same samples; none needs a
second scan.

### 6.5 One mark for every shape (B)

- **Gates.** `EventPresence.appliesTo` becomes `event.tracksPresence`;
  `EventSkips.appliesTo` becomes `true`. A one-off's day is its start day
  (its days, for a multi-day). Storage is unchanged: presence and skip rows
  are keyed by event id and UTC day already.
- **The editor's switch.** `_ruleHasManyOccurrences` stops gating the
  presence switch; the switch shows for any event whose category's kind
  marks, pre-set on for a new event (U), and under *Custom* for every event
  off by default. The template editor follows (`repeats && _tracksPresence`
  → the same rule).
- **The verb.** The detail sheet's presence button, the day rail's marker
  label and the Missed card's row read the kind's verb through one function
  `markVerbOf(effectiveProfile)`; routines keep "Attended" where their kind
  says so. The semantics label follows the verb.
- **Shapes.** `shapeOf` is unchanged — a tracked one-off is still a one-off
  (its row is dated, not aggregated); `ReportSample.missed` may now be true
  for it, so the Missed card lists "Dentist · Thu 8 · missed" and the
  Attendance measure counts it. The report record's §4.1 and D31 get an
  addendum line, not a rewrite.
- **Assume absent.** The kind's default (§6.2) applies to new events; the
  v37 rule (`assumeAbsent`, `assumeAbsentFrom`) is otherwise untouched. A
  Task left unmarked after its day is therefore missed — which is what
  "overdue" means.

### 6.6 Targets and goals (J, K)

```
target        kind: atLeast | atMost | maxGap | budget
              value: int   (occurrences, days, minutes, tasks, cents)
              period: day | week | month | year   (absent for maxGap)
ReportGoal    categoryId, measure, target
              periods: [start, end, value, expected, state]
                state: met | onPace | behind | over | notDue | future
              streak: consecutive complete periods met, back from the
                      last complete one, inside the 366-day lookback
              gap (maxGap): daysSince, limit, state: within | due | overdue
```

Periods align to the app's week start and to calendar months and years, in
local date-only terms built with `DateTime(y, m, d)` — never a midnight
`add`. `expected` for the current period = `value × elapsedDays /
periodDays`, rounded up. *At least*: met when value ≥ target, on pace when
value ≥ expected, else behind. *At most* and *budget*: within when value ≤
expected, over when value > target. *Max gap*: within when daysSince ≤
limit, due inside the limit's last fifth, overdue past it. A period's first
day with nothing yet is notDue; a period after today is future.

### 6.7 Insights (L)

Each rule is `(CalendarReport, effective profiles, today) → Insight?`,
deterministic and locale-free until rendering. Rank by severity, then by the
category's primary value descending, then by rule id. Three on the page,
one in the digest. Each carries a tap target: the category's group, the tag's
rows, the Due soon card, or the overview's list on the days in question.
Thresholds are `AnalyticsMetrics` constants (Z); the numbers below are their
initial values.

| Id | Fires when | Sev | Example |
| --- | --- | --- | --- |
| **G1** | an *at least* goal is behind with more than half the period elapsed | 3 | "Gym · 1 of 3 this week — two more by Sunday" |
| **G2** | an *at most* or *budget* goal is over | 2 | "Work · 44 h this week, 4 h over" / "Groceries · 1,340 of 1,200 this month" |
| **G3** | a goal is met before the period ends | 1 | "Run · 3 of 3 — done for the week" |
| **G4** | a period streak reaches a multiple of 4, or breaks | 2 / 1 | "Gym · 8 weeks in a row" / "Reading · the 5-week streak ended last week" |
| **G5** | a Leave allowance has under 20 % left with over a quarter of the year ahead, or days unused with under a month left | 1 | "Vacation · 3 of 25 days left, 4 months to go" |
| **D1** | a gap target is overdue | 3 | "Car service · 212 days since the last, the limit is 180" |
| **D2** | a gap target is due (last fifth) | 2 | "Dentist · due in 18 days" |
| **D3** | an Expiry is inside 60 days, or past | 3 / 2 | "Passport · expires in 42 days" / "Insurance · expired 3 days ago" |
| **D4** | a Bill or Deadline day has passed unmarked | 3 | "Rent · 1 November, not marked paid" |
| **D5** | an Episode's next expected day is inside a week (≥ 3 episodes with a regular gap, CV < 0.25) | 1 | "Migraine · the usual gap puts the next around Thursday" |
| **P1** | a routine's attendance by weekday differs by ≥ 40 points over ≥ 4 days each | 1 | "Gym · Tuesdays 90 %, Fridays 40 %" |
| **P2** | Work days after the late line ≥ 3 in a week, or weekend Work hours > 0 | 1 | "Work · three evenings past 19:00 this week" / "Work · 5 h on the weekend" |
| **P3** | Sleep: nights under the short line ≥ 3 in a week, or bedtime spread > 90 min | 1 | "Sleep · four nights under 7 h" |
| **P4** | Meetings' share of Work + Meeting hours ≥ 50 % | 1 | "Meetings · 54 % of your work hours this week" |
| **P5** | Cancelled ≥ 30 % of planned with ≥ 4 planned | 2 | "PT sessions · 3 of 8 cancelled" |
| **P6** | a Workout category has a rest gap ≥ 10 days in the span | 1 | "Run · 12 days without a run in October" |
| **T1** | the primary moved ≥ 30 % against the previous period, ≥ 5 occurrences or ≥ 2 h either side | 1 | "Work · 31 h, up 35 % on last month" |
| **T2** | the primary moved ≥ 30 % against the same period last year (Compare: last year chosen) | 1 | "Friends · 4 evenings, half of last October" |
| **T3** | a Bill's amount moved against its previous occurrence by ≥ 10 % | 2 | "Electricity · 312, up 18 % on last month" |
| **M1** | Bills ahead in the next 30 days | 0 | "Bills · 2,140 due in the next 30 days" |
| **M2** | a yearly span: recurring Bills' twelve-month total | 0 | "Subscriptions · 1,428 a year across 6" |
| **R1** | a tag's last-seen exceeds the category's gap limit, or 3× its median gap | 2 | "#ana · 41 days since the last dinner" |
| **R2** | the span's most-seen tag in a people category | 0 | "Friends · most evenings with #mihai (6)" |
| **L1** | an Appointment or Social category's median lead time < 2 days over ≥ 4 events | 0 | "Dentist · booked a day ahead on average" |
| **L2** | Deadlines done with ≥ 3 open past their day | 2 | "Deadlines · 3 open past their day" |
| **A1** | Anniversaries ahead in the span's remainder | 0 | "3 birthdays ahead this month" |
| **A2** | a Trip ahead | 0 | "Next trip · Sibiu in 12 days" |

Year in review adds its own record rules (§6.12). A rule whose sentence a
tile already says in the same words yields nothing.

### 6.8 Due soon (O)

One card, drawn when any gap target, Expiry or unmarked Bill / Deadline
exists: rows ordered overdue → due → upcoming, each "Car service · overdue
32 days", "Passport · 42 days", "Rent · 1 Nov · not marked"; a leading state
glyph (never colour alone); tap opens the event's detail sheet. Capped at
`AnalyticsMetrics.dueSoonRows` (6) with "n more ▾". In the future tense the
card lists the span's Expiries and Bills only.

### 6.9 By tag (C, Y)

Tags are extracted once per `(eventId, day?, text)` with `MarkdownTagSyntax`'s
rule — `#` at a word boundary, letters, marks, digits, `_`, `-`, inner `/`,
at least one letter — from the title, the description and the per-day
overrides, lower-cased for grouping, shown as typed. The card lists the top
`AnalyticsMetrics.tagRows` (8) tags by Events, each "#ana · 6 evenings ·
last Fri 24", scoped to the page's categories; a tag's tap expands its dated
rows in place. A tag in a people category drives R1 / R2; a tag in a Trip
category is a place ("#sibiu · 2 trips · 5 days"); a tag in Maintenance is
a thing ("#golf · 3 services · 1,240"). Nothing is typed: the sentence's
noun comes from the category's kind.

### 6.10 When and Balance (M)

- **When** — a 7 × 24 heatmap of kept timed days (rows from the week start,
  columns hours), one `CustomPainter`, drawn with ≥ 10 timed samples; the
  caption names the busiest weekday and hour band; its semantics node reads
  the caption and the Categories rows are its table twin. The designer specs
  the cell and a four-step sequential ramp from `primary`.
- **Balance** — `FormMeterRow`s, one per area with hours, scaled to the
  largest: "Work 38 h · Health 6 h · People 9 h · Home 4 h", Sleep excluded
  by default, Money kinds carrying no hours. Drawn with ≥ 2 areas. No pie.

### 6.11 Compare

The period menu gains *Compare with*: **Previous period** (today's deltas,
unchanged), **Same period last year** (a second fold over the span shifted
one year; the tiles' deltas read it; the trend draws it as a thin outline
behind the columns; T2 runs), **A saved view…** (the footer's "Compare with
Work / Life" folds the picked `OverviewView`'s category set over the same
span and shows a second Totals column — side by side at ≥ 600 dp, stacked
with the view's name as its section label on a phone). Every second fold
is a memo entry like any other.

### 6.12 Year in review (N)

When the span is a whole calendar year the page adds, after Totals:

- **Records** — busiest week and month (occurrences), longest day streak
  per routine (`PresenceStats.longestStreak`), the longest period streak,
  the most social month, the biggest money month, the longest trip, the
  longest gap in each gap-target category.
- **Months** — one 12-tile strip per category (≤ 7, "n more ›"), each tile's
  intensity the month's primary value — `MonthDotMatrix`'s year tiles are
  the painter precedent.
- **By area** — Balance over the year, with the previous year's bar as an
  outline when Compare: last year is chosen.
- **Top tags** — the By tag card over the year.
- **Firsts and lasts** — per category the first and last kept day of the
  year ("Run · first 4 Jan · last 29 Dec").
- **Goals met** — per target, "38 of 52 weeks" with the streak.

All from the one 366-day fold; nothing new is scanned.

## 7. The surfaces

- **Category editor** (`category_editor_sheet.dart`, today one section
  label, Alerts) gains two sections:
  - **Kind** — a `FormPickerRow` opening a grouped picker (areas as section
    labels, kinds as rows with a one-line example each); Custom last. The
    row's caption reads the kind's one-line meaning.
  - **Measure & goal** — *Measure* (Auto with its resolution as caption ·
    the measures the kind applies to) · *Counts as* (the kind's suggestion
    as the hint, confirmed by a tap; disabled with its reason under a
    repeat-only or Sleep category) · *Mark* (the verb, editable text with
    the kind's as default; "Off" for kinds that do not mark) · *Area* ·
    *Goal* (a `FormActionRow` to the goal sheet: kind, value in the
    measure's unit, period; "Remove goal" at its foot; the row's caption
    reads it back: "At least 3 a week", "At most 180 days between").
  - Semantics ids for every control; two flows in `qa pass calendar`.
- **Event editor** — the presence switch under the kind's rule (§6.5), the
  kind's defaults for a new event (U); no new rows.
- **Detail sheet, day rail, day list** — the mark's verb (§6.5); the
  one-off's cancel action where routines have theirs.
- **Report page**, the card order when everything has content: **Goals** ·
  **Insights** · **Due soon** · Totals (+ working-days caption, T) ·
  *[Year in review: Records · Months · By area · Firsts and lasts · Goals
  met]* · Categories (the header leads with the primary: "Work · 31 h · 12",
  "Friends · 23 days ago · 4") · **By tag** · Over time (+ last-year
  outline) · **When** · **Balance** · Missed (one-offs included) · Ahead ·
  Footer (+ Compare with…). Each card absent without content, so an
  unprofiled calendar renders today's page. The band's subtitle gains the
  goals' summary when any exists: "31 events · 2 goals on pace · 1
  behind".
- **Settings → Calendar → Report** — the card list with switches and drag
  handles (W); off cards are absent, never collapsed.
- **Digests** — the weekly / monthly report digest's words add, after the
  existing line, "Goals · Gym 3 of 3 ✓ · Work 42 h (over 40) · Friends 1 of
  2" (≤ 3 by severity), then "Due · Dentist in 18 days · Rent not marked"
  (≤ 2), then the top insight. The generic line is unchanged.
- **Share report** — `ReportMarkdown` gains the Goals, Insights, Due soon,
  By tag and Year in review sections in the same order as the page.
- **The guide** — untouched (V).

## 8. Architecture and performance

- **One model, every reader.** `CalendarReport` grows `goals`, `insights`,
  `dueSoon`, `tags`, `when`, `balance`, `year` and `compared`; per category
  a `ReportMeasures` record. `CalendarReportBuilder.fold(ReportInput)` is
  the only writer; the page, `ReportMarkdown` and the digest words read it.
  `ReportInput` gains `profiles` (effective, by category id), `moneyFor`,
  `createdAtOf`, `lastSeenBefore` (resolved by the service), `compared`
  (a second input or null) and the span's working-day facts.
- **Effective profile.** `CategoryProfile.effective(kindRow, overrides)` is
  one pure function in `lib/models/category_profile.dart`; the editor, the
  builder, the detail sheet's verb and the digest all call it. The kinds
  catalogue is a `const` list; a kind's row never changes at runtime.
- **Cost.** Measures: one O(samples) pass with per-category and per-tag
  accumulators. Goals: bucket samples by period index, O(samples) +
  O(periods). Insights: O(categories + tags) over folded numbers, plus P1's
  weekday histogram per routine (already in Timing). When: O(samples) into
  168 cells. Tags: one tokenisation per distinct `(eventId, day?, text)`,
  cached beside the task-count cache. Last seen: one `occurrencesInRange`
  over the 366-day lookback per category that reads a gap, cached per
  `membershipRevision`. Compare: a second fold through the memo. The report
  record measured 18,000 probes for 366 days × 50 events inside a frame;
  S2 pins the new fold at ≤ 1.5× that on the same fixture.
- **Memo.** `_ReportKey` adds `profilesRevision` (the profiles repository's
  stream bumps it, the alerts precedent) and the compare choice. A profile
  edit refolds once; a mark on a one-off bumps `presenceRevision` as a
  routine's does.
- **Layering.** *As built (S0, decision AA):* `CategoryProfileDao` (SQL,
  soft delete, CRDT stamping, merge) → `CategoryProfileService` (the lazy
  singleton on the `DatabaseLifecycle` contract: the cache, the workflow —
  save, clear, reload — the backup export and import) → the static facade
  `CategoryProfiles` (`revision`, `profileFor`, `effectiveFor` → `unprofiled`
  when none), which every synchronous reader uses: the report's memo key,
  the editor, the detail sheet. The calendar area has no repository layer
  (`EventAlertService` → `CategoryAlertDao` is the precedent), so none was
  added. The report bloc resolves profiles into the request as it resolves
  the category allowlist; `CalendarReportService` still reads no bloc, no
  settings, no clock.
- **Off the build path.** Folds in handlers; the previous model at reduced
  opacity until ready. Goals, Due soon, By tag and Balance are
  constant-height rows behind `RepaintBoundary`s; When and the Months strip
  are single painters; one `Scrollable`; the record's slack rule.
- **Sync.** The table joins `_syncedTables`; the same CRDT merge and
  `ownerId` scoping as category alerts. No new pattern.
- **The isolate escape (R).** Only on a device measurement; the builder is
  pure, so it is one `compute` around `fold`.

## 9. Data

```
calendar_category_profiles                 (the calendar_category_alerts shape)
  id              text  PK
  categoryId      text  unique among live rows
  kind            text  the catalogue key; 'custom' when unset
  area            text? override
  measure         text? override of the primary
  nominalMinutes  int?  confirmed counts-as; null = none
  markVerb        text? override of the verb; '' = off
  marksNew        bool? override: new events track presence
  assumeAbsentNew bool? override: new events assume absent
  countsHours     bool? override
  targetKind      text? atLeast | atMost | maxGap | budget
  targetValue     int?
  targetPeriod    text? day | week | month | year
  createdAt, updatedAt, hlcTimestamp, deviceId, version, isDeleted,
  deletedAt, ownerId
```

- **Migration**: the next schema version creates the table and adds it to
  `_syncedTables`; no data is moved. A category's soft delete soft-deletes
  its profile in the same transaction.
- **Backup**: `'version': 8`; `categoryProfiles` beside `categoryAlerts`;
  the reader accepts ≤ 8; S.
- **Events**: no schema change. `createdAt` surfaced on `CalendarEvent`
  (Q). The two `appliesTo` gates (B). Presence and skip rows for one-offs
  use the tables as they are.
- **Settings**: `SettingsKeys.reportCards` (the ordered list with
  enabled flags), beside `reportPeriod` and `reportCategoryIds`.

## 10. Behaviour — ten walkthroughs

1. **Nothing set.** The Report, the digest and the share are byte-for-byte
   today's (the golden in §13).
2. **Gym → Workout, at least 3 a week.** This week shows Goals first: "Gym ·
   2 of 3 · one more by Sunday", a meter at two thirds, "× 4" for four
   weeks met before; marking tonight attended refolds once → "3 of 3 ·
   done for the week"; Insights drops G1 and shows G3. Year in review: "Gym
   · 41 of 52 weeks met · longest streak 11".
3. **To-do → Task, counts as 30 min confirmed.** The Work group's header
   reads "Work · 6 h · 12" where it read "Work · 12"; the Hours tile's
   caption says "incl. 6 h counted as"; an unticked to-do left past its day
   is missed and appears under Missed as "Call the bank · Tue 28 · not
   done"; its presence button says *Done*.
4. **Rent → Bill, with a linked ledger note.** Categories: "Rent · 1,800 ·
   1"; Due soon: "Rent · 1 Nov · not marked paid" until the owner taps
   *Paid*; M1 in the monthly digest: "Bills · 2,140 due in the next 30
   days"; Year in review: M2 for subscriptions.
5. **Work → Work, 8 h confirmed, at most 40 h a week.** "Work · 31 h of 40
   · 9 h left this week"; P2 when three evenings pass 19:00; Balance: "Work
   38 h · Health 6 h · People 9 h"; the Totals caption: "22 working days ·
   1 public holiday".
6. **Friends → Social, at most 14 days between; #ana, #mihai in titles.**
   Goals: "Friends · 23 days · limit 14" overdue; D1 in Insights; By tag:
   "#mihai · 6 evenings · last Fri 24", "#ana · 2 · last 23 Sep"; R1:
   "#ana · 41 days since the last dinner". A dinner today clears the goal
   on the next fold; an unmarked past dinner counts as happened (no
   assume-absent).
7. **Birthdays → Anniversary.** Nothing changes but A1: "3 birthdays ahead
   this month"; no goal row, no hours, the Counts-as row disabled with its
   reason.
8. **Travel → Trip; #sibiu, #cluj.** "Travel · 14 days · 3 trips"; By tag
   "#sibiu · 2 trips · 5 days"; A2 "Next trip · Cluj in 12 days"; Year in
   review's Records: "Longest trip · 6 days, Sibiu".
9. **Car → Maintenance, at most 180 days between, #golf.** Due soon: "Car
   service · overdue 32 days" (D1); the detail sheet's button says *Done*;
   marking it writes the mark, the gap resets on the next fold; Money per
   tag "#golf · 1,240 this year".
10. **Vacation → Leave, at most 25 days a year.** "Vacation · 14 of 25 days
    · 11 left"; G5 in August: "11 of 25 days left, 4 months to go"; the
    trip in September adds 5 → "19 of 25".

Also: a profile edit refolds once (the memo's `profilesRevision`); Compare:
last year on October reads every delta against October 2025 and serves ◄
from the memo; text scale 2.0 wraps a goal row's value to a second line and
never clips; the When heatmap keeps square cells and thins its hour labels
to every sixth; an archive from before S0 imports with no profiles and no
warning; a sync between two devices converges on the newer profile.

## 11. Facts from the tree (2026-11-03)

- `lib/constants/event_presence.dart:79-80` — `appliesTo` =
  `event.tracksPresence && event.rule is! OneTimeRecurrence`.
  `lib/constants/event_skips.dart:48-49` — `appliesTo` =
  `event.rule is! OneTimeRecurrence`; the facade's `revision` :25,
  `isSkipped` :55, `daysFor` :67; writes in
  `lib/services/event_skip_service.dart` (`markSkipped` :219, `setSkips`
  :245, `unskip` :273). Skips table `calendar_event_skips`,
  `lib/database/tables/event_skips_table.dart:43`, PK `{eventId, day}` :63.
- `lib/widgets/event_editor_sheet.dart:2731-2732` — the presence switch;
  `_ruleHasManyOccurrences` :1174-1175 gates it; applied at :1725.
  `lib/widgets/event_template_editor_sheet.dart:762-763`, :395, :295 — the
  template's equivalent.
- `lib/models/calendar_event.dart` — `endDate` :146, `time` :152
  (`EventTime.startMinute` / `durationMinutes` :86-87), `countStyle` :173,
  `assumeAbsent` :194, `perOccurrenceDescriptions` :215, `noteId` :263,
  `priority` :285, `endDateUtc` :430; **no `createdAt` on the model**
  (column at `lib/database/tables/calendar_events_table.dart:128`).
- `lib/utils/markdown_tag_syntax.dart:18` — `MarkdownTagSyntax`, the token
  rule in its doc :10-14; `lib/utils/markdown_inline_grammar.dart:1362` —
  `InlineTag`. Event descriptions render through `SimpleMarkdownPreview`
  (`lib/widgets/event_detail_sheet.dart:988`;
  `lib/widgets/simple_markdown_preview.dart:8`). No tag index service
  exists for notes.
- `lib/models/overview_view.dart:17` — `OverviewView(id, name, period,
  options, categoryIds, sortOrder, rollsWithToday)`;
  `lib/services/overview_view_service.dart:24`; table
  `lib/database/tables/overview_views_table.dart:25`.
- `lib/widgets/category_editor_sheet.dart:59` — `CategoryEditorSheet`; its
  one `FormSectionLabel` (Alerts) at :628.
- `lib/utils/calendar_report_builder.dart:102` — `static CalendarReport
  fold(ReportInput input)`. `lib/models/calendar_report.dart:508` —
  `ReportInput(span, today, weekStart, events, categoryOf, samples,
  overrides, skippedDays, categoryOrder, previousSpan, …)`; `shapeOf`
  :40-47; `ReportTile` :50; `ReportTotals` :121.
- `lib/services/calendar_report_service.dart:29-100` — `ReportRequest` and
  its four readers; the memo and `_ReportKey` :130-152; `sampleInput` :157.
- `lib/utils/presence_stats.dart:12-16` — `PresenceStats(attended, total,
  currentStreak, longestStreak)`; `PresenceAdherence` :36, `windowDays` 30
  :40, `lookbackDays` = `EventAgenda.maxRangeDays` :44, `compute` :60.
- `lib/utils/digest_planner.dart:75` (`plan` :82); the report digest words
  `lib/utils/digest_labels.dart:34-38`; `lib/utils/report_markdown.dart:14`
  (`render` :21), called from `lib/pages/calendar_report_page.dart:819`.
- `lib/pages/calendar_settings_page.dart:34`;
  `lib/constants/settings_keys.dart` — `reportPeriod` :259,
  `reportCategoryIds` :263, the overview keys :232-253.
- `lib/widgets/form_rows.dart:2167` — `FormMeterRow(leading, label, caption,
  fraction, meterColor, trailing, onTap, semanticsLabel, expanded,
  identifier)`; `lib/widgets/month_dot_matrix.dart:14` (constructor :85;
  `selectedIndex`, `selectedColor`, `onDayTap` fields :72-83).
- `lib/services/backup_service.dart` — `categoryAlerts` export :118 / :172,
  import :541-545, `'version': 7` :133, reader `backupVersion < 7`
  :599-606. `lib/database/migrations/database_migrations.dart:1783` —
  `_syncedTables` (`calendar_category_alerts` :1794); the v42 migration
  :1687-1715 is the table-creation precedent.
- `lib/services/note_money_ledger_service.dart:22-31` — per-note
  `{balance, net, title}`; `docs/money-ledger-feature.md` §Calendar: net on
  the event's start day, once per event, global currency.
- `tool/qa/flows/calendar/00_open.txt … 29_categories_page.txt` (30 flows,
  `_prelude.txt`, `_suite.txt`, `_labels.txt`); seed `tool/qa/src/seed.dart:12`;
  fixture `tool/qa/fixtures/calendar.json`.
- `docs/calendar-report-roadmap.md` §4.1 (shapes), §4.3 (cards), §4.7 (cost
  model and "growth this leaves open"), §9 (deferred: the Done flag, YoY,
  two-selection compare, streak tiles, home glance) — this record takes
  those up.

## 12. Slices and the kick-off prompt

### 12.1 The slices

| Slice | Builds | Reads (by section) | Tests that prove it |
| --- | --- | --- | --- |
| **S0** | `calendar_category_profiles` (table, migration, DAO, repository, service, lifecycle reset, `_syncedTables`), backup v8, `CategoryKinds` catalogue, `CategoryProfile` + `effective()`, `createdAt` on the model, `AnalyticsMetrics` | §5 D G Q S Z, §6.2, §9, `drift-migrations` SKILL | migration from the previous version; backup round-trip; unknown-category drop; soft delete with the category; `effective()` per kind |
| **S1** | one mark for every shape: the two gates, the editor and template switch rule, kind defaults for new events, the verb in the detail sheet / day rail / day list, the one-off's cancel | §5 B U, §6.5, `calendar-events` references §presence | a one-off marked and missed; a one-off cancelled; a new event under Task tracks and assumes absent; an existing event unchanged; `shapeOf` unchanged; presence suite green |
| **S2a** | builder I: effective profiles in `ReportInput`, the eleven measures, tags, nominal hours flag, Money and lead-time readers, goals with pace and streaks, Due soon, Balance, When buckets | §6.3 §6.4 §6.6 §6.8–6.10, §8 | a fixture pair per measure and per goal state over both week starts and a DST month; the probe-count pin; memo invalidation on `profilesRevision`; the unprofiled golden |
| **S2b** | builder II: the insight library, Year in review aggregates, Compare (last year, saved view) in the service | §6.7 §6.11 §6.12 | a fixture pair per rule; ranking determinism; year records; two-fold compare served from the memo |
| **S3** | the category editor's Kind and Measure & goal sections, the goal sheet; l10n; semantics ids; two QA flows | §7 editor, `ui-language` SKILL §sheets | the sheet's suite; disabled rows with reasons; read-back captions at 1.0 / 1.3 / 2.0, en / de / ro |
| **S4** | report cards I: Goals, Insights, Due soon; the Categories header's primary; the Hours caption; Missed with one-offs; the band's goals summary | §7 report, §6.6–6.8 | widget tests per card and state; the unprofiled page pixel-pinned; the guide's stage pinned |
| **S5** | report cards II: By tag, When, Balance; Compare with… in the period menu and footer | §6.9–6.11 | heatmap semantics and square cells at 2.0; Balance ordering; compare column at 360 and 600 wide |
| **S6** | Year in review cards and the period preset | §6.12 | the five cards on a full-year fixture; the Months strip against `MonthDotMatrix` pins |
| **S7** | digests and share: the goals, due and insight lines; `ReportMarkdown` sections | §7 digests and share | words from the same fixtures as S2; the generic line unchanged; the Markdown golden |
| **S8** | Settings → Calendar → Report cards; the calendar-events and calendar-ui references, the feature doc's addendum, the report record's §4.1 / D31 addendum; the guide decision (V) | §5 W V | settings round-trip; off cards absent |
| **S9** | the device pass: new flows (kind picker, goal sheet, one-off mark, each new card), `qa pass calendar` and `qa pass alerts` green; this record's §12.2 complete | `qa-emulator` SKILL | the pass report |

### 12.2 As built

*(appended per slice by the implementing session: what changed, what was
verified, the reviewer's findings and their fate, the uncommitted file count
at the boundary)*

#### S0 — the data foundation (2026-11-04)

Built as three sub-slices — S0a and S0b in parallel on disjoint files, then
S0c — and one fix pass from the review.

- **S0a (pure Dart).** `lib/constants/category_kinds.dart`: `CategoryKind`,
  `LifeArea`, `MarkVerb`, `TargetPreset`, `CategoryKindRow`, the
  `CategoryKinds` catalogue (the 21 rows of §6.2, Custom last) and
  `CategoryProfileKeys`. `lib/models/category_profile.dart`:
  `ReportMeasure`, `TargetKind`, `TargetPeriod`, `ReportTarget`,
  `CategoryProfile` (the §9 row; `copyWith` with a `clearX` per override;
  tolerant `fromJson`), `EffectiveProfile` (`static const unprofiled` =
  Custom with nothing overridden) and the one pure resolver
  `CategoryProfile.effectiveOf(profile)` — §8's `effective(kindRow,
  overrides)` reads as this; Dart forbids a static and an instance member of
  one name, and the instance getter `effective` delegates to it.
  `lib/constants/analytics_metrics.dart`: every threshold and cap of §6.7–6.12
  with its why. `CalendarEvent.createdAt` (Q): set by `_rowToEvent`, carried
  by `copyWith`, not in `props` and not in the event's JSON (the export
  already carried `createdAtMs`).
- **S0b (database).** `calendar_category_profiles` (`CategoryProfileRow`),
  schema **v44** (`DatabaseSchema.v44CategoryProfiles`, a frozen `CREATE TABLE
  IF NOT EXISTS` carrying `owner_id`, `createCategoryProfileIndexes` on both
  paths), `CategoryProfileDao` (`getAllActive` ordered category then HLC,
  `getActiveForCategory`, `upsertForCategory`, `tombstoneForCategory` with
  RETURNING, `getByIdsIncludingDeleted`, `mergeRemoteCategoryProfile` — the
  alerts merge contract —, `deleteAll`, `importAll`), the cascade in
  `CalendarCategoryDao.tombstoneCascade` under the category's stamp,
  `SyncedTable('calendar_category_profiles')`,
  `CalendarCategoryProfilesBinding` (invalidation `SyncInvalidation.calendar`)
  after the alerts binding, the collection in `firestore.rules` and
  `firestore.indexes.json`.
- **S0c (wiring).** `CategoryProfileService` (lazy singleton, `reset()` also
  clears the facade; `save`, `clear`, `reload`, `refreshAfterCategoryRemoval`,
  `refreshAfterSync`, `exportCategoryProfiles`, `importCategoryProfiles(rows,
  knownCategoryIds:)` returning the dropped count, `clearCategoryProfilesForImport`),
  the facade `lib/constants/category_profiles.dart`, the tenth service in
  `CalendarBloc._onLoad`'s wrapped `Future.wait`, the refresh in
  `CategoryService.deleteCategory`, the reload in `_appReloadCalendar` before
  the calendar's external-change signal, backup **version 8** (`categoryProfiles`
  beside `categoryAlerts`; absent beside `calendarCategories` clears, absent
  with no categories is untouched; a ≤ 7 archive imports with no profiles and
  no warning), `effectiveOf` forcing `assumeAbsentNew` false when `marks` is
  false.

**Decisions taken on the way** (lettered on from Z; reversible):

- **AA — No repository layer.** The calendar area has none; the service sits
  on the DAO and publishes a static facade (§8 Layering reads as built).
- **AB — The table joins `syncedTables` and the binding registry**, not the
  migrations' `_syncedTables`, which only the frozen v43 backfill reads.
- **AC — `categoryId` is unique among live rows by convergence**, not by a
  unique index: two devices may each create a profile for one category and
  a merge must store both; readers keep the newest HLC per category and the
  next local save tombstones the rest.
- **AD — Targets are on the primary measure only** (J): Work's "at least
  days / month" and Trip's "at least trips / year" are not presets (§14).
- **AE — Custom is today's behaviour**: `countsHours` true, `marksNew` and
  `assumeAbsentNew` false; Task's and Bill's fallbacks are `primaryFallback`;
  a kind's suggested counts-as lives on its catalogue row (Z's intent — a
  constant, never a literal — holds; `AnalyticsMetrics` keeps thresholds, caps
  and the Work late line).
- **AF — The orphan count of a backup import goes to the log** (S): `ImportResult`
  carries success and error only.
- **AG — The sync reload never force-creates the profiles service**; it
  reloads a live instance (the alerts precedent force-creates).
- **AH — `importAll` mints fresh CRDT identity and keeps `createdAt` /
  `updatedAt`**, every `importAll`'s rule: a backup is not a sync channel.

**Review** (one `reviewer`, Opus 5.5, on S0a + S0b; S0c and the fix pass
reviewed separately below): eight findings. Fixed — the insert path crashing
on a tombstoned id (now revived in place, the alerts DAO's rule); the
model/wire key split (`createdAtMs` / `updatedAtMs`, `ownerId` carried); a
just-created event's cached model missing `createdAt`; a present `createdAt`
discarded on insert; UTC decoding against local rows; `TargetPreset` without
value equality; the binding's literal keys; the test gaps (a per-row
catalogue pin, the binding's codec case, the `createdAt` mapping, the
tombstoned-id and NULL-vs-`''` DAO cases, the owner-id round trip). Ratified
— AC. Accepted — the lossy decode of an unknown kind to Custom (the
`AlertMode` precedent; storage and wire keep the raw string).

**The owner's step.** v44 gates sync for v43 installs by design (the engine
pauses `appOutdated` below the space's schema), and `firestore.rules` gained
the collection: before a v44 build syncs from a phone, add `"firestore":
{"rules": "firestore.rules", "indexes": "firestore.indexes.json"}` to the
gitignored `firebase.json` and run `firebase deploy --only firestore:rules
--project alexs-note-tracking-app` from `frontend/anta`.

**Second review** (one `reviewer` on S0c and the first fix pass): thirteen
items, none a data loss on a path the app runs today. Fixed in a second
pass — the construction race on a database switch (`CategoryService`'s
generation guard, publishing only after the second check); profile ids are
the service's (`save` ignores a draft's id: the live row's or a fresh UUID,
and the DAO refuses a live row of another category under an id with an
`ArgumentError`); one raw encoder for the wire and the backup
(`CategoryProfileWire` beside the binding, `WireFields.row` for a backup
map), so an unknown kind pulled from a newer build survives a backup;
`_read` builds the map locally and `_adopt` swaps it whole, every write and
import on one `_serialize` chain; an import decodes every row before the
wipe and replaces in one transaction (`replaceAll`; an archive whose rows all
drop still empties the table — the alerts' documented rule, since the
restore has replaced the category ids); the revival keeps a present draft
`createdAt`; `CalendarEventService.upsert` reads `createdAt` back on every
cache miss; `forTesting` asserts one database; `ReportMeasure`, `TargetKind`
and `TargetPeriod` moved into `category_kinds.dart` so the constants no
longer import the model; the tests it asked for (a literal sixteen-key wire
pin, profiles on an archive-only custom and a hidden category, the three
`refreshAfterSync` cases, the concurrent-saves case). Accepted — the
`CalendarCategories.all`-empty edge on import (logged), the v7 archive case
proving the same as the clear case. Deferred — memoising `effectiveFor` per
revision (S2a decides when the fold reads it).

**Gate.** `dart analyze lib test` clean; the whole suite `+12540 ~11 -1`
(the one failure the Windows-only `host_devices_test` case; 12,419 at the
baseline, so 121 new cases); `dart format` clean on every slice file (three
files — `calendar_bloc.dart`, `app_sync_apply_hooks.dart`, the calendar
round-trip test — were already unformatted at HEAD and their old code was
left alone); no ARB touched. 45 files, committed in the next line's hash.

### 12.3 The kick-off prompt — written 2026-11-03, NOT RUN

The owner pastes this into a **fresh interactive Opus 5.5 session** from
`frontend/anta` when the roadmap is scheduled. Nothing in this record starts
it. If it is ever run under `claude -p`, remember that the Agent tool is
background-only there and the session ends at its final message: hold each
turn on the agent's result (TaskOutput / Monitor) before writing anything
final.

```
You are the lead for the calendar analytics roadmap of the ANTA Flutter app.
Work from frontend/anta on Windows (PowerShell; Git Bash for scripts; no
python; never perl -i or sed -i). Read CLAUDE.md, then load the skills
delegation, calendar-events, calendar-ui, ui-language, verify and
flutter-principles; load drift-migrations for S0 and S1, l10n for every
slice that touches copy, qa-emulator for S9.

The design is docs/calendar-analytics-roadmap.md. Read it BY SECTION, never
whole: §1 (how to run this, the must-not-change list, the stop rules), §5
(decisions A–Z), then for each slice exactly the sections §12.1 names for
it. The report it extends is docs/calendar-report-roadmap.md — read only
§4.1, §4.7 and §8 of it, once, before S2a.

Run the slices in order: S0, S1, S2a, S2b, S3, S4, S5, S6, S7, S8, S9. For
each slice:
  1. Brief ONE implementer (Opus 5.5) with: the goal and why, the record
     sections by number, every entry point as file:line from §11, the
     must-not-change list, "done means" (dart analyze lib clean; the tests
     the slice table names written and green; gen-l10n with an empty
     untranslated.txt when ARBs changed; no commit; no new docs; no scratch
     files), and a brief of 5–8 ids at most — split a slice rather than
     write a longer brief. The implementer does NOT run the whole suite.
  2. Run the whole suite yourself: flutter test, one run, never beside a
     flutter run. If it is red, resume the same implementer with the
     failing cases; one fix pass. Still red → stop at this boundary, write
     the red case into §14 with file and intended fix, and report.
  3. Brief ONE reviewer (Opus 5.5) with the slice's diff scope, the record
     sections, the must-not-change list, and the instruction to report
     every finding, CONFIRMED or PLAUSIBLE, by its 60th turn. Resume the
     implementer for the fix pass; rerun the suite.
  4. For S3, S4, S5 and S6 the designer runs BEFORE the implementer and
     returns one spec with lettered defaults; the design-reviewer runs
     AFTER the reviewer. Accept the designer's defaults unless one breaks a
     decision in §5; record what you accepted in §12.2.
  5. Append the slice's as-built note to §12.2 (what changed, what was
     verified, the findings and their fate), then stop and give the owner
     the number of uncommitted files and a ready commit (paths and a short
     natural message ending with the attribution line the session shows).
     NEVER commit; the owner commits. Continue only on the owner's word
     when the session is interactive; in an unattended run continue to the
     next slice and leave each slice's ready commit in the report.

S9 is one qa-runner call per suite (qa pass calendar, then qa pass alerts,
device emulator-5556); the new flows are written in S3–S6 by the
implementer of the slice that adds the control. A red flow after one
--only rerun is a finding for §14, not a reason to edit the flow.

Budget: one implementer and one reviewer per slice; no workflow; no
fable-max; no agent spawns another agent; explorer (Haiku) for any fact
hunt wider than two files. Read references by section. On the owner's
"low usage": finish the step in flight, launch nothing new, write what is
left into §14, give a three-line check-in, stop.

Report at the end of every slice and at the end of the run: slices done,
suite count and result, uncommitted files, open findings, what §14 gained.
```

## 13. Definition of done

- A category with no profile renders the Report, the digest and the share
  byte-for-byte as before S0 (a golden on the report record's §4.4
  fixtures, run in every slice).
- Every measure, goal state, due state and insight rule has a fixture pair
  (fires / does not fire); the effective profile is tested per kind.
- A one-off can be marked with its kind's verb, missed by assume-absent and
  cancelled; a routine's behaviour is unchanged; the presence and skip
  suites are green.
- The 366-day, 50-event fold with every category profiled and tagged stays
  within 1.5× the report record's pinned probe count and inside one frame
  on `emulator-5556`.
- Backup 7 imports clean; backup 8 round-trips the profiles; two devices
  converge on the newer profile.
- `qa pass calendar` (30 + the new flows) and `qa pass alerts` green.
- Text scale 1.0 / 1.3 / 2.0, light and dark, en / de / ro rendered and
  reviewed for the kind picker, the goal sheet, every new card and the
  heatmap; no colour carries a state alone.
- The report, categories and settings records each carry one addendum line
  pointing here; the calendar-events and calendar-ui references describe
  kinds, marks on one-offs and the new cards as built.

## 14. Deferred

- **Per-event overrides** (A, D) — a counts-as or an exclusion on one event;
  only if a category's events prove too mixed.
- **Task weighting** — minutes per ticked task; after counts-as has been
  used for a month.
- **Percent-adherence and rolling-window targets** (J).
- **A tag scope in the request** (Y) — filtering the page by a tag; after
  By tag shows which tags the owner follows.
- **"Done on time" for Deadlines** — needs the mark row's timestamp read
  against the day; after S1 shows the mark's `createdAt` is reliable
  across devices.
- **Counter history** (X) — a dated counter entries table; its own record.
- **Notes outside the calendar as a source** (A) — journal streaks, notes
  per folder per week.
- **Due-soon and pace notifications** (F) — two opt-in alert kinds; after
  the digests have carried the lines for a season.
- **A home-screen glance / platform widget** of Goals and Due soon — the
  memoised model makes it cheap; the widget is the work.
- **Hour-of-day targets** ("no work after 19:00") — reads the When
  buckets; after the heatmap has been looked at.
- **Fasting days as context** (T) — the report record's deferral stands.
- **An isolate fold** (R) — only on a measurement.
- **The guide's kinds and goals card** (V) — S8 decides after the owner has
  used them.
