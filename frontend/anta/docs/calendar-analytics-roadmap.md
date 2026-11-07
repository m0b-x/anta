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
S9's device pass is green. **COMMITTED 2026-11-05: S0–S9** (the last code commit
`b12314b4`; the device pass 35 of 35 calendar flows and 5 of 5 alerts
flows on `emulator-5558` — the S9 note at the end of §12.2; what stays
with the owner is listed there). **The closing review ran 2026-11-05**
(§13.1): every line of §13 checked at `94a55179` from the Fable lead
session; the closing commit `ab38ec61` carries the five rule-branch tests
it found missing, the two sister records' addenda and the §6 lines brought
to the code. **The closing fixes followed the same day** (§13.1's last
paragraph): the format drift, the fleet's storage, the guide suite's
clock with the timeline's overflow at 2.0 behind it, the backup import's
folder batch, the digest's currency, the fold measured on the device —
`985b7055` … `95f46b11`; what still waits for the owner is §14's first
bullets.

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
  unprofiled report (amended 2026-11-05 by S7: a calendar with no profile
  but a `#` word in a title gains the By tag section, the one exception the
  page itself has made since S5 — a tag needs no profile; the closing
  review names the other, older one: When draws for any calendar with ten
  timed samples, §6.10, so the page and the share of an unprofiled
  calendar with that many timed days gain the When card and section too),
  the digest's generic line; the overview's totals slot;
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
| **Timing** | median start minute; days after the late line (*as built, S2a: one line for every kind, `AnalyticsMetrics.workLateMinute`*); weekday histogram | minutes, count, 7 bins | timed samples | timed events |
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
                state: met | onPace | behind | over | missed | notDue | future
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
day with nothing yet is notDue; a period after today is future. *As built
(S2a-ii; the closing review brought this paragraph to `_goalState`):* a
closed *at least* period under its target is `missed`; *at most* and
*budget* read onPace while value ≤ expected, behind above expected but
still within the target, met when a closed period stayed within, over past
the target.

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
| **T3** | a Bill's amount moved against its previous occurrence by ≥ 10 % (*as built, decision AT: the Bill category's spent cents against the compared span, `billDelta`*) | 2 | "Electricity · 312, up 18 % on last month" |
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
card lists the span's Expiries and Bills only. *As built (S2a-ii):* four
states, `overdue → due → unmarked → upcoming` — an unmarked Bill or
Deadline is its own tier; only a gap target produces `due`, an Expiry
inside its 60 days is `upcoming` and past its day `overdue`, a Bill planned
in the span `upcoming`.

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

**Where the next session starts (rewritten 2026-11-05 after S9 —
the roadmap is COMMITTED).** Done and on `origin/main`: S0 (`2661c8de`),
S1 (`6a586668`), S2a (`0f5fae29`), S2b-i (`66efe1f1`), S3 (`fb9ae486`),
S2b-ii (`f29edf64`), S4 (`f3571ecf`), **S5** (`0abb2f69` … `8855bf29`,
docs `1e344277`), **S6** (`46680e15` … `9327da13`, docs `bf868227`),
**S7** (`8202b736`, `e19abc3a`, the fix pass `3885ef3d`), **S8**
(`c09ef7a7` … `b12314b4`; S8c's six documents and the S7 / S8 notes in
`ed010ff5`) and **S9** (the device pass: calendar 35 of 35 and alerts 5
of 5 on `emulator-5558`; flow 34's repoint and the S9 note in the last
commit). Nothing is queued. What stays with the owner: the Firestore
rules deploy before a v44+ build syncs from a phone (the S0 note); the
guide try-cards suite's clock pin (§14 — three cases red on the real
clock since 2026-11-05, with the Windows-only host-devices case the
suite's known noise); `anta_qa_1`'s storage (the install refused with
539 MB free); the device-only looks the three design reviews listed (the
S5, S6 and S8 notes); and §14's deferred items. A later session that
touches the analytics loads `calendar-events` (its Analytics section
points at `references/subsystems.md` "The analytics layer") and reads
this record by section. Each slice ran as: implementer runs of ≤ 8 ids by layer (words →
primitives and cards → page), the whole suite from the lead, two code
reviewers and the design-reviewer told to report by turn 60, fix passes
grouped by file, commit. The process that worked in S5 and S6 beyond
S4's: a parallel sub-slice in a worktree at a short
path (`C:\Temp\anta-wt-<id>`, `firebase_options.dart` copied, the branch
committed and squash-merged, the generated plugin registrants never
staged); where both sides touched one file, commit the branch, `git diff
main <branch> > patch`, `git add` the dirty file, `git apply --3way`; the
suite only from the lead with nothing else running, and a red case re-run
at the pre-slice commit in the spare worktree before blaming the slice
(the real-clock guide cases). The owner's pending step (the Firestore
rules deploy before a v44+ build syncs from a phone) is in the S0 note.

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
gitignored `firebase.json` and run `firebase deploy --only
firestore:rules,firestore:indexes --project alexs-note-tracking-app` from
`frontend/anta` (rules and indexes in one command — the sync record's §7
checklist is the full procedure).

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
left alone); no ARB touched. 45 files; commit `2661c8de`, pushed to
`origin/main` on 2026-11-04.

#### S1 — one mark for every shape (2026-11-04)

Built as S1a (the gates and their readers, nothing user-visible) and S1b
(the editor, the verb, the cancel), then one fix pass from two reviews and
one isolated backup change.

- **S1a.** `EventPresence.appliesTo` is `event.tracksPresence`;
  `EventSkips.appliesTo` is `true` (kept as the one place to ask);
  `CalendarEvent.occursOnUtcDay` subtracts a one-off's skip too (the inline
  one-time bypass removed — the agenda's one-time bucket now goes through
  it as well); `withExplicitDates` keeps presence on a single date (the
  repeat-only flags still drop); `EventTemplate.buildEvent` keeps presence;
  `shapeOf` and `PresenceAdherence.compute` keep `rule is! OneTimeRecurrence`
  inline, each with its why — a tracked one-off is a dated row with no
  adherence (§6.5 "Shapes"); `eventInDayRail`: auto membership is
  `EventPresence.appliesTo`, a stored `true` never rails an untracked
  one-off, `false` forces out; every other call site follows the new gate
  (the resolvers, the agenda, the timeline, the overview, the grid filters,
  the Missed card's `presenceTracked`). The sampler needed no change: a
  tracked one-off yields missed / pending / plain samples by tense and a
  cancelled day is dropped and counted. A cancelled one-off is omitted from
  the `.ics` export (a `METHOD:PUBLISH` snapshot, not an iTIP update);
  alerts never arm it (the planner decides every day through
  `occursOnUtcDay`; the scheduler cancels an armed registration on skip).
- **S1b.** The editor's switch rule `_presenceOffered` = series ∨ tracked ∨
  the kind marks, the save writing `tracksPresence: _tracksPresence`, the
  kind's defaults on init and on every category pick for a new event while
  the owner has not touched the switch (`_presenceTouched`); the template
  editor the same; `lib/utils/mark_verb_labels.dart` (`effectiveFor(event)`,
  `markVerbLabel`, `markAsVerbLabel`; "Present" / "Mark as present"
  unprofiled); nineteen ARB keys in en / de / ro (`markVerb*`, `eventMark*`,
  `eventMarkAsVerb`, `eventCancelEvent`, `eventCancelledState`,
  `eventRestoreEvent`, `eventCancelled`); the detail sheet's kept chip reads
  the verb, a one-off's Cancel (`eventDetailCancel`) writes in place through
  `onCancelChanged` and the sheet shows a Cancelled row sized by an
  invisible template of the presence row plus Restore
  (`eventDetailRestore`); the rows' and the day panel's mark tooltips per
  verb (`AgendaDayListEntry.categoryId`); `CalendarEvent.strandsSkipsOf`
  clears an event's skips when a save makes its rule one-time or moves a
  one-off's start day, in the editor and in the Dates sheet alike.
- **The fix pass.** Schema **v45** (`v45OneOffSkipSweep`): one UPDATE
  tombstoning every live `calendar_event_skips` row of a `rule_kind =
  'oneTime'` event with a stamp minted as the v43 backfill mints (before S1
  no surface could cancel a one-off, so each was a leftover of a conversion
  that would now hide the event; idempotent; queues nothing, v43's rule);
  the guide demo's own `isMissed` and `occursOn` follow the facades; the
  `CustomSnackbar` action drops to its own line when it does not fit beside
  the message (61 px over at de 2.0 × 360 before); the review's test gaps
  (the agenda, the bloc round trip, the explicit missed mark and
  `markSkipped` on a one-off, the untracked one-off's sheet, the Dates
  sheet's skip clearing through the flow's harness). A backup archive of
  version < 8 drops its one-time skip rows on import (archived leftovers;
  a version-8 archive keeps every row — a cancel is intentional there).

**Decisions taken on the way:**

- **AI — The switch is offered to a one-off only when its category's kind
  marks or the event is already tracked.** §6.5's "under Custom for every
  event off by default" would have put the Occurrences group on every
  one-off of an unprofiled calendar and pushed Priority below the fold on
  360 × 780, breaking the editor redesign's pin; for this run an unprofiled
  editor stays exactly today's and marks on one-offs arrive through a kind
  — the roadmap's own mechanism. One condition to add back
  (`_presenceOffered`) if the owner wants the other reading.
- **AJ — A one-off's cancel is in place, with Restore.** A skipped day
  vanishes from every surface by the calendar's oldest rule, and a one-off
  has no other day to be found on; so the sheet stays open and shows the
  state, the snackbar's Undo stands, and the Report's rows (S4) will open
  the sheet of a cancelled one-off again. A Cancelled listing in the
  overview is deferred (§14).
- **AK — A conversion clears skips.** `strandsSkipsOf`: all of an event's
  skips when its rule becomes one-time or a one-off's start day moves;
  one-off → series keeps them (the owner's skipped days survive the way
  they always did).
- **AL — The notice's Skip on a one-off still turns the alert off**, never
  cancels the event: a one-tap cancel from a notification has no way back.
- **AM — The fold keeps counting a missed one-off as kept until S2a.**
  `_isMissed` in the builder requires `_isRoutine`; the builder is S2a's
  (builder I) and the Missed card with one-offs is S4's, as §12.1 lays them
  out. Today's unmarked tracked one-off is `pending` → Ahead, D31's rule.

**Review** (one `reviewer` on S1a; one on S1b + the fix pass, below):
S1a's eight findings — the stale skip rows (fixed: v45 + `strandsSkipsOf`
+ the backup gate), an unknown rule kind decoding as one-time (accepted:
the sweep and the gate match the literal key only), the fold counting a
missed one-off as kept (AM), the Dates sheet's tracked one-off stripped by
the editor's next save (fixed by S1b's save rule), the guide demo's gates
(fixed), the docs (fixed: the calendar skill's rules and lineage, the
subsystems reference, the feature doc, the lifecycle contract list), the
test gaps (fixed), dead `EventSkips.appliesTo` conditions (accepted: the
one place to ask).

**Review of S1b and the fix pass** (one `reviewer`): no data loss on a
path the app runs today; ten items, all taken in a second pass — the v45
sweep's tombstones now queue themselves into `sync_outbox` under the
step's stamp (a fresh v45 device would otherwise pull the space's live rows
and hide its one-offs; `crdt_write_guard_test` carries the one named
exception); a cancel's cleared mark is captured by the sheet and handed
back on Restore and on the snackbar's Undo (`onCancelChanged(day,
cancelled, {restore})`, the flow writing it after the unskip); the editor's
switch term is latched to the value the sheet opened with so switching it
off never hides the row; an untracked one-off's cancel keeps the sheet's
geometry (the Restore row takes the Cancel row's slot with "Cancelled" as
its value); the guide's sandbox editor and sheet read `unprofiled`
(`profileOf` seam; decision V); a Save-as-template draft counts as touched;
de "Besucht" / "Stattgefunden", ro "Prezent" / "Văzut" /
"contramandat" / "Restaurează"; the pins it asked for (the sweep's units,
a pre-tombstoned row, a `specificDates` series, a soft-deleted event's row
— swept, since an undelete would bring the hidden day back; the editor's
moved one-off and one-off → series; the Restore row's 48 dp; the snackbar's
fitting action on the message's line). Accepted — every one-off's sheet
offers Cancel regardless of kind (decision B: the cancel is the shape's,
as a series' Skip is); the snackbar over a short sheet may cover Restore
while up (its own Undo does the same).

**Gate.** `dart analyze lib test` clean; the whole suite `+12632 ~11 -1`
on the implementer's undisturbed run and `-2` on the lead's with
`test/widgets/database_settings_page_test.dart`'s delete-all case red,
which passes alone (32 / 32) and is red only under a concurrent Dart
process — a Windows load flake, not the slice's; `untranslated.txt` `{}`;
`dart format` clean on every hunk (fourteen files already unformatted at
HEAD left as they were); the docs updated in the same change (the calendar
skill's presence rules and lineage header, `references/schema-lineage.md`
v44 + v45, `references/subsystems.md`, the feature doc's three gate
statements, the lifecycle contract list). 74 files; commit `6a586668`
(2026-11-04).

#### S2a — builder I (2026-11-04)

Built as S2a-i (the inputs, the eleven measures, the tags, the memo keys)
and S2a-ii (goals, due soon, balance, the when buckets), reviewed together.

- **S2a-i.** `ReportInput` gained `profiles` (every scoped category, the
  unprofiled ones included so the builder never consults the facade),
  `cancelled` (the skipped days as samples; `skippedDays` is their count),
  `money` (event id → the linked note's net cents from
  `NoteMoneyLedgerService.ledgerFor`), `lastSeenBefore`, `workingDays`,
  `publicHolidays`; `CalendarReport` gained `measures` (one `ReportMeasures`
  per category with an event, catalogue order), `tags` (`ReportTag`, the
  top `AnalyticsMetrics.tagRows` by events), `nominalMinutes`, the two
  day counts; `ReportTotals` gained `nominalKept` / `nominalAll`. The
  builder folds the measures in the one sorted walk it already makes
  (`_MeasureTally`, `_TagTally`); `_measuresOf` resolves the primary (the
  profile's, else Auto, then the fallback); `_minutesOf` applies counts-as
  to a kept untimed day of a routine or a one-off, never a repeat, never
  Sleep; the Hours tile counts a category only when its `countsHours` is
  true and includes the nominal part; `_isMissed` is `missed && !pending
  && tracksPresence` (AM — a missed one-off lands in `missed` as a dated
  row and the tile counts it; the attended / missed tiles appear once any
  event is tracked). `lib/utils/tag_extractor.dart` tokenises through
  `MarkdownTagSyntax` with an LRU (`AnalyticsMetrics.tagCacheSize`). The
  service resolves everything in `_input`; the last-seen lookback is one
  `occurrencesInRange` per gap category over the 366 days before the span
  with its own LRU (`lastSeenCacheSize`); `_Scope` and the bloc's
  `_FoldKey` carry `profilesRevision` and `ledgerRevision`; `scanCount`
  beside `foldCount` is the cost seam (today's fold: 2 scans — the span and
  the previous span — plus one per gap category; a memo hit 0).
  `NoteMoneyLedgerService.seedForTesting` for the suites. The unprofiled
  golden holds: every earlier case unchanged, the worked periods included.
- **Defaults taken (S2a-i, reversible):** "timed" = has a duration; lead
  time counts `OneTimeRecurrence` only and skips an event created after its
  day (a log, not a booking); `planned` = counted days to today, missed in,
  pending out, plus cancelled; in a plan the measures cover every
  occurrence and `lastSeenDay` falls back to the lookback; the lookback
  ends the day before the span or today, whichever is earlier, and drops
  cancelled, missed and today's pending day; `publicHolidays` counts
  weekend holidays too, `workingDays` is Monday–Friday minus holidays; a
  tag's label is its first spelling in sample order; money of 0 is ignored
  and counts once per event whose start day lies in the span; the
  Categories group headers' minutes are unchanged until S4 reads
  `measures`.
- **Noted for S4:** `ReportTile.hours`'s doc still says timed only; the
  bloc's `_FoldKey` never carried `CalendarCategories.revision` (a catalogue
  rename with no calendar change does not refold through the bloc —
  pre-existing; S4's resume refresh covers it).

- **S2a-ii.** `GoalState` (met · onPace · behind · over · missed · notDue ·
  future), `ReportGoalPeriod`, `ReportGoal(categoryId, measure, target,
  periods, streak, gap)`, `GapState` / `ReportGapState`, `ReportDueKind` /
  `ReportDueState` / `ReportDueRow`, `ReportWhen` (168 cells of minutes
  from the week start, `timedDays`, the busiest row and column, null under
  `whenMinTimedSamples`); `CalendarReport.goals`, `dueSoon`, `dueSoonMore`,
  `balance` (`Map<LifeArea, int>` minutes, `countsHours` categories only),
  `when`; `ReportInput.lookback` (kept and missed samples per category over
  the 366 days before the span — one scan per category with a target OR a
  gap, never two, the lookback LRU renamed `_lookbacks`; `lastSeenBefore`
  derived from it). Goal periods are bucketed by index inside the measures
  walk; the lookback samples get one walk of their own; the when cells fill
  in the same walk. `AnalyticsMetrics.lookbackDays` (pinned equal to
  `EventAgenda.maxRangeDays`).
- **Defaults taken (S2a-ii, reversible):** a period's value counts what was
  kept to today, a future period what is planned; `expected = ceil(target ×
  elapsed / days)` in integers, a closed period's expected is the target; the
  value per primary (Count → kept days, Events → distinct kept events, Hours
  → minutes with counts-as, Attendance → kept tracked days, Tasks → ticked,
  Money → cents spent for budget and *at most*, received for *at least*; the
  rest → kept days); `notDue` on the current period's first day at value 0
  for every kind; the streak never counts a period ending before the
  category's earliest event (an *at most* goal's empty pre-history would read
  as a year met); **a past span's last period that runs past the span's end
  is valued to the end and left out of the streak** (one 366-day lookback
  cannot also reach past the end; a current span loses nothing; exact would
  cost a second scan — §14); a gap row's event is the one kept on the
  last-seen day, its day the last kept day plus the limit; an upcoming
  Expiry is the first sample on or after today, else a one-off's start day
  past the span (a recurring Expiry beyond the span is unseen — §14); a
  passed Expiry lists every missed sample; "unmarked" Bills and Deadlines
  are `missed` samples; due ties break by days, catalogue order, day, event
  id; `when` nullable, set by every fold.

**Review** (one `reviewer` on S2a-i + S2a-ii): the golden confirmed by
diff (no pre-existing expectation edited; the §4.4 worked periods
untouched; the attended / missed tiles' rule differs only for a tracked
one-off); fourteen findings, taken in one fix pass. Fixed — **the days
after a past span** (`ReportInput.lookahead`: on a Last-month report
last-seen, the gap state and a trailing goal period were blind to the days
between the span's end and today; the service now scans `[span.end + 1,
today]` for every target-or-gap category on a past span, one more
`occurrencesInRange` each, in the same LRU; a trailing period is then
exact and closed only when its end is before today; the streak counts it;
scans: a past span 2 + 2 per such category, a current span 2 + 1;
`lastSeenCacheSize` 64); **a gap with no kept day in the lookback**
(`gap` null when nothing occurred up to today; `daysSince =
lookbackDays` with `beyondLookback` true when something occurred and
nothing was kept — "over a year"; a limit ≥ 366 can never read overdue;
`ReportDueRow.beyondLookback`); **AN — Expiry assumes absent** (an
expired, unrenewed Expiry is a missed day and reaches Due soon as
overdue; the catalogue row and its pin updated; Social is now the only
marking kind that does not assume absent); **the guide's Report folds
unprofiled** (`ReportRequest.profileOf`, the fifth reader of the guide's
seam, `report()` refusing it like the others; `calendar_guide_try_report`
passes `unprofiled` — decision V); Due soon orders overdue rows most
overdue first and the rest soonest first; `hasMoney` follows the ledger
(the money toggle off → Money falls back to Count); an Expiry due today
reads 0 days; no allocation per untagged kept sample (the event's own tag
keys once; the per-day set only when an override adds tags;
`extractTags` returns `const []` before the cache for a text without
`#`); tags skip a code span's and a bare URL's `#` as the inline grammar
does (`MarkdownLinkPatterns.matchBareUrlEnd`; the code-span rule a small
copy, since the grammar imports Flutter — `\#` escapes, `%%` comments,
ghosts, wiki links and autolinks are still counted, §14); the lookback
key's presence and membership invalidation pinned, the partial first week
pinned. **The cost pin**: a `benchmark`-tagged case folds the 366-day,
50-event fixture with every category profiled (targets, two counts-as, a
tag in every title) against unprofiled in interleaved rounds — the
fastest profiled / fastest unprofiled ratio 1.35–1.41 over three runs
(the bound 1.5; medians swung to 1.60 under load, so the estimator is the
minimum); the extra is the lookback scans (inherent to R) and the goal
walk, whose period lookup is memoised per day. Accepted — last seen
includes today's happened or kept day; the histogram counts every kept day;
one late line for every kind; a current span's future periods hold no
planned value; a plan's Cancelled is 0; a profile edit rescans the
lookbacks (rare). §14 — money once per event (P).

**Gate.** `dart analyze lib test` clean; the whole suite `+12713 ~12 -1`
(the known Windows-only case; 12 skipped with the new benchmark case);
`dart format` clean on every slice file; no ARB; the record's §6.3 / §6.6
/ §6.8 read as amended here (the lookahead, the gap floor, AN, the Due
soon order). 14 files; commit `0f5fae29` (2026-11-04).

#### S2b — builder II (2026-11-04)

Built as S2b-i (the insight library and the model shapes S4 asked for) and
S2b-ii (year in review, compare, T1–T3, the shapes S5 asked for).

- **S2b-i.** `InsightRule` (g1 … a2; T1–T3 wait for the compared fold),
  `InsightTarget` (categoryGroup · tagRows · dueSoon · overviewDays),
  `ReportInsight(rule, severity, categoryId?, tagKey?, eventId?, target,
  day?, dayEnd?, n1 … n4, minutes, cents, ratio?, alternate)` with the slot
  table per rule in its `///` (`alternate` marks a two-condition rule that
  fired on its second condition); `CalendarReport.insights` — every fired
  rule, ranked by severity, then the category's primary value, then rule
  order, then emission order; `lib/utils/report_insights.dart`
  (`ReportInsights.rank`, one pure function per rule, called at the end of
  `fold`; D1 and D2 share one, a gap reading one state). The measures the
  rules need, in the same walk on fixed arrays: `missedByWeekday`,
  `maxLateDaysInAWeek`, `weekendMinutes`, `maxShortDaysInAWeek`,
  `startMinuteSpread` (the shortest arc of the day holding every start, so
  23:30 and 00:30 read 60), `longestGapDays` (the days between two kept
  days), `leadTimeEvents`, the episode stats (`episodes`, `lastEpisodeDay`,
  `episodeGapMean`, `episodeGapCv` — kept days up to today, a same-day
  second event joining the episode, the lookback and lookahead walked only
  for Episode kinds); `ReportTag.medianGapDays`; `ReportGoal.brokenStreak`
  (G4's break is unreadable once `streak` is 0); `CalendarReport.money`
  (the selection's non-zero nets, for M1 / M2); S4's asks —
  `ReportMeasures.profiled`, `dueSoon` uncapped (`dueSoonMore` gone; the
  page caps).
- **Defaults taken (S2b-i):** **every rule reads only profiled
  categories** (P1, P5 and R1's median branch read no kind, so this gate is
  what keeps the unprofiled golden empty); P1–P6 skip a plan; D1 / D2 are
  graded only (the Due soon card's rule); "upcoming" (A1, A2, M1) is Ahead
  in a current span and the plan's groups in a future one; G2 / G3 read the
  current period only; G4's break is any closed period not met, `over`
  included; G5 requires value ≤ target; P1 needs two weekdays with ≥
  `weekdayMinDays` tracked days each in an all-routine category, percents
  rounded; M1 / M2 sum spent cents only; M1, M2, A1, L2 one insight per
  category, P4 and A2 one across categories (P4 points at the Meeting
  category with the most minutes); R1's limit from the first profiled
  `maxGap` category, else 3× the median gap; R2 the first tag in tag order;
  late and short days per sample; weekend minutes counts-as included.
- **Noted for S2b-ii / S4:** D3's upcoming branch reads `daysUntil`, which
  covers the span only (an Expiry past the span's end is in Due soon but
  fires no D3 — the page drops D3 beside Due soon anyway, decision H); D1
  cannot say "over a year" (no `beyondLookback` slot — S2b-ii adds one);
  M1 / M2 read the note's whole net once per event (P, §14).

- **Review of S2b-i** (one `reviewer`, with nine probes through the real
  builder in a snapshot and one mutation of the ranking): no data loss;
  eleven behaviour findings and a set of edge cases and test gaps, taken in
  two fix passes. **Pass one** — M2 counts a tracked recurring Bill
  ("recurring" = not one-off; `shapeOf` calls a tracked recurring event a
  routine); D3 reads the Due soon rows (one per Expiry event, with its id,
  so an Expiry past the span's end fires too); G5's "under" is strict on
  both branches; P4 needs Work hours (no Work → no "100 % of your work
  hours"); `tags` is uncapped in the model (the card caps) so R1 and R2 see
  every tag, and R1 runs only in the current tense (a past span's tags stop
  at its end while `since` runs to today — the lookahead is per
  target-or-gap category, not per tag, decision R); episodes join across
  events (a category's runs of consecutive kept days); P6 counts the rest
  still running in a current span; M1 reads the next thirty days through
  one more scan for Bill kinds (`ReportInput.billsAhead`; the monthly
  digest's thirty days lie wholly after its span), once per event, its
  target the overview's days; R2 picks by days; D4 once per event; the
  ranking pin carries a severity tie that the primary value decides and
  one that emission order decides (the primary values compare across units
  — cents, minutes, counts — as §6.7 states; accepted). **Pass two** — the
  bedtime spread as the 10th–90th percentile range of the Sleep category's
  starts (one late night in thirty gave 105 min); a short night needs a
  night-sized sample (`sleepNightMinMinutes`, a nap is not a night); P1
  compares exact percents and rounds for display; G4 skips a plan; A1
  counts occurrences; A2 ends on the trip's last day and skips a trip
  already under way; the episode walk runs for Episode kinds only; `///`
  on every `ReportInsight` field; the fire / just-under pairs one step
  apart (G5, P1 with `weekdayMinDays`, P5 with `cancelledMinPlanned`, L1's
  lead, D5's CV at and under 0.25 and 2 vs 3 episodes, P4 without Work, M2
  tracked). Accepted — L2 overlaps D4 for Deadlines (the page's filter H
  and the digest's one line keep it harmless). Pass two also added
  `AnalyticsMetrics.sleepNightMinMinutes` (180) and `bedtimeSpreadTrim`
  (0.1), the `beyondLookback` slot on `ReportInsight`, and a trip as a run
  of one event's consecutive days for A2.
- **Gate (S2b-i).** `dart analyze lib test` clean; the whole suite `+12777
  ~12 -1` (the known Windows-only case); `dart format` clean on every slice
  file; no ARB. 9 files; commit `66efe1f1` (2026-11-04).

- **S2b-ii** (2026-11-04, the second session; Fable leads, two Opus
  implementer runs, two Opus reviewers, one fix pass). Built: `ReportCompare`
  (previous · lastYear · view) on `ReportRequest` (`compare`, `compareView`)
  and in the memo key; the compared fold — `ReportInput.role`
  (`ReportFoldRole.main | compared`), `compare`, `compared`, `tileSet`;
  `CalendarReport.compare`, `compared`, `balanceLastYear`, `totals`,
  `withCompared`; `ReportTrend.lastYear`; T1–T3 (`InsightRule.t1..t3`
  after `p6`); Sleep out of When; `ReportTag.kind`; the year aggregates —
  `CalendarReport.year` (`ReportYear(records, months, spans, goalTallies)`,
  `ReportRecord(kind, categoryId?, eventId?, value, start, end?)`,
  `ReportRecordKind` in S6's order, `ReportGoalTally(met, closed,
  longestStreak)`), `AnalyticsMetrics.recordStreakMin` (3); the
  working-days gate (S4's model ask 3); `ReportMetrics.memoFolds` 4 → 8.
- **Decisions (S2b-ii):** **AQ** the compared fold is a second `fold` with
  the `compared` role — totals, tiles, measures, trend (columns only),
  balance, when, money; no categories, tags, goals, due rows, insights or
  year — and its own memo entry (its key: the fold's category ids, span,
  today, role, tile set, week start, the scope's revisions; a compared
  fold's own `compare` stays `previous`, so a calendar year's previous
  period and its last year share one entry); the service runs it when the
  tense is not future and (the mode is not `previous` or a profiled
  category is in scope), so an unprofiled calendar's default report folds
  once, exactly as before. **AR** Same period last year: a whole calendar
  year → the previous year; a whole calendar month → the same month a year
  earlier to its own last day; a span of 7 n days → 364 days earlier
  (weekdays align); otherwise both ends a year earlier with the day clamped
  (29 Feb → 28 Feb); clamped by D33 like the previous span; a compared span
  ending before the calendar's first day, and every plan, fold as
  `previous`; `report.previousSpan` is then the shifted span, so the
  "against …" caption needs nothing. **AS** like with like for the compared
  fold (D28 extended): its today is the real today for a past span and
  `previousCounted.end` for a current one, sampled with the real today and
  folded with the compared today; `previousTotals` = its totals (pinned
  equal to the old totals fold). **AT** T1 / T2 read seven additive
  primaries in their own unit (count, events, hours as minutes,
  attendance, cancelled, tasks, money as spent cents — received for
  Income), both sides > 0, either side ≥ `trendMinOccurrences` or ≥
  `trendMinMinutes`, |Δ| ≥ `trendDelta`; T3 (Bill kinds, `billDelta`)
  compares the category's spent cents against the **compared span** — not
  the bill's previous occurrence, which money per event cannot see (§14) —
  and names the latest counted bill whose start day lies in the span and
  whose net is negative; none of the three under `view`. **AU** When fills
  only samples whose profile counts hours and whose kind is not Sleep (the
  `_minutesOf` / Balance rule); `timedDays` counts the samples that fill a
  cell. **AV** `ReportTag.categoryIds` in catalogue order, then id, and
  `kind` from the first *profiled* one (else `custom`); R1 / R2 therefore
  read the catalogue-first category of a tag — a shift from first-seen
  order, accepted and pinned. **AW** `ReportTrend.lastYear` only when both
  trends share a unit (a shifted span that loses 29 Feb can change it);
  `balanceLastYear` under `lastYear` only. **AX** `year` is set by a main,
  graded fold whose span is exactly 1 Jan – 31 Dec, on any calendar (S6 N);
  records tie to the earliest; the busiest week is a week on the week start
  whose start lies in the year (the first partial week belongs to no week),
  clipped at 31 Dec; a trip is any Trip-kind event's run of consecutive
  kept days; money goes to the month of the event's start day and, like
  cancellations, is cut at today; a streak counts kept occurrences in a
  row (`PresenceStats`' rule); goal tallies count periods from the goal's
  `streakFrom` (a budget begun in July reads "n of 27 weeks", not 52) and
  "closed" means ended before today. **AY** `totals` on every fold; the
  benchmark's bound 1.5 → 1.75 (two folds by design: 1.40 → 1.49 on an idle
  machine). **AZ** working days and public holidays are resolved only for a
  whole calendar month or year whose scope holds a Work, Meeting or Leave
  kind, plans included (S4 P); every other span reads 0, so no unprofiled
  caption changes.
- **Reviews (S2b-ii).** Two `reviewer`s (compare half; year half), nine
  probes through the real fold in a snapshot. Taken in one fix pass: the
  goal tallies' `streakFrom` bound (CONFIRMED); `ReportTag.kind` from the
  first profiled category (`other` is the catalogue's first seed); the
  outline only under one unit; the shifted span clamped (a 366-day span
  shifted to 367 and lost its last day); T3's row attributed as its cents
  are; `compare == view` without a view resolves to `previous` in release
  (the assert stays; no test can build that request); four `///` fixes
  (`closed`, the records' ties, the months' cut, `_settled`'s displaced
  doc). Accepted as built: money months cut at today while the measures
  count a current span's later bills (§14); the first partial week; a
  leap-year quarter shifting 364 days (AR names months and years only);
  working days 0 for unprofiled spans; the compared memo key's `foldToday`
  (identical inputs fold identically). Pins added from both gap lists: T1
  per unit, T3 in a current span and with no event, T1 through the service,
  the shared year entry, an elapsed-day miss, the view refold on a tile-set
  change, working days on a 29-day February / a plan year / a D33-clamped
  span, Sunday and Saturday week starts, a trip and a streak across 1 Jan,
  two gap categories' order, a compared fold's totals, a streak tie.
- **Gate (S2b-ii).** `dart analyze lib test` clean; `dart format` clean;
  no ARB; the benchmark alone 1.49; the whole suite `+12917 ~12 -1` (the
  known Windows-only case). 10 files; the commit hash is in the hand-off
  at the head of §12.2.
- **Noted for S4 / S5 / S6:** an insight whose category has no Categories
  group (a money primary whose events lie after today; a cancelled-only
  category) is a read row (S4 G's rule); `months` and `spans` iterate in
  catalogue order while `categories` is ordered by count — the Months card
  iterates `categories` and looks up, and a category whose every day was
  missed has no `months` entry; the trend's last-year tick shows 0 after
  the compared today in a current span (like with like).

#### S3 — the category editor's profile sections (2026-11-04)

**The designer's spec** (Opus 5.5, from real-font renders of the current
editor and of the proposal at 1.0 / 1.3 / 2.0, en and de, 360 wide; no
mock, every structure an existing primitive; the spec and renders in the
session's scratchpad, the as-built below is the record): after Alerts, two
labelled groups — **Report**: Kind (`FormPickerRow` → the kind picker;
caption the kind's one-line example), Mark (`FormMenuRow`: the kind's verb
· "Own word…" through `AppDialogs.textInput` · Off), Area (`FormMenuRow`,
the seven areas); **Measure & goal**: Measure (`FormMenuRow` + caption:
Auto first, then the eight main measures), Counts as (`FormMenuRow` +
caption: Off · 15 · 30 · 45 · 60 · 90 · 120 · 240 · 480 min, the kind's
suggestion as the caption, the pick is the confirmation; disabled in place
with its reason under Sleep or a repeat-only category, decided once at
open), Goal (`FormPickerRow` → the goal sheet; the read-back in the
caption, which wraps — a value is cut at 2.0 de). Every row carries a
caption in every state (a caption costs 28 dp, so a row that gained one
would jump). `CategoryKindSheet`: the single-pick `CategoryPickerSheet`
shape, seven area labels in enum order over `FormCheckRow(exclusive)`
rows with a ≤ 28-character example each, Custom last, no search, opens at
the top. `CategoryGoalSheet`: ✕ · Goal · Done; TYPE as three exclusive
check rows (At least · At most · Days between, or Budget in place of At
most on a Money primary; the kind's presets first, an impossible type
disabled in place); TARGET as an editable `FormStepperRow` whose label
follows the unit, then Day · Week · Month · Year chips (disabled for Days
between, no "Per" label — it never fit one line); the read-back inside a
`FormCaptionSlot` sizer so the sheet never grows at runtime; "Remove goal"
at the foot only when a goal was stored. Two primitive extensions:
`FormMenuRow.caption`, `FormStepperRow`'s editable value.

**Its defaults, accepted by the lead:** A after Alerts · B the two labels
with Mark and Area under Report · C rows inline (the editor opens full
height, about 1,125 dp edited; a profile sub-sheet is the way back to a
short sheet) · D Auto plus the eight main measures · E no search · F a
kind pick resets the area, measure and mark overrides and keeps Counts as
and a still-valid goal · G no rows for the new-event switches or
counts-toward-hours (§14) · H opens at the top · I Done, the sub-sheet rule
· J seeds 3 / 3 tasks / 8 h / 30 days / 100, whole hours, step 1 · **K a
budget takes any period, Month preselected** (J's "per month" widened) · L
Remove goal only with a stored goal · M the durations menu, not the time
pad (which would read "1:00 AM" for 60 min on a 12-hour phone) · N the own
word through the text dialog, the other stock verbs not offered · O
Custom's Auto not resolved in the editor ("Auto picks per period") · P the
editable stepper. Built in a worktree (`C:\Temp\anta-wt-s3`, branch
`analytics-s3` from `6a586668`) beside S2a's review in the main tree, to
be merged at its boundary.

**Built** (Opus 5.5, in the worktree): the two sections after the alerts
caption with the profile draft seeded from `CategoryProfiles.profileFor`,
the profile in the dirty check, the save order category → profile → alerts
(`save`, or `clear` when the draft returns to Custom with nothing
overridden), the sandbox writing nothing, repeat-only read once at open
from the calendar bloc, every profile row in `ValueChangeHighlight` under
`FormIndentedRow(52)`; `CategoryKindSheet`; `CategoryGoalSheet` returning
`CategoryGoalSaved(ReportTarget)` / `CategoryGoalRemoved`; `FormMenuRow`
+ `caption`, `FormStepperRow` + `controller` / `focusNode` / `maxDigits` /
`fieldIdentifier`; `lib/utils/category_profile_labels.dart` with
`categoryGoalReadBack` shared by the row and the sheet;
`CategoryKinds.countsAsChoices` / `headlineMeasures`, `CategoryGoalUnit`,
`CategoryGoalLimits`; 107 ARB keys in en / de / ro; the suites (27 editor
cases, 10 kind sheet, 14 goal sheet, the primitives, the clearance test)
and the flows `30_category_kind` and `31_category_goal` (unrun until S9).
The builder's own deviations, accepted: the examples' wholeness at 2.0 is
the design review's real-font check, not a test-font pin; two container
ids (`category-editor-form`, `category-kind-list`) for `scroll-to --in`;
the en Workout example keeps the spec's four items.

**Reviews** — one `reviewer`: one real bug (a revert after a partial
save never written while the sheet popped as saved) and nine low items;
one `design-reviewer`: the pins hold (row heights, a caption in every
state, disabled rows in place with their reason, no example cut at 2.0,
one goal-sheet height per open, nothing above REPORT moved against a HEAD
snapshot) and four severity-2 findings. Taken in two fix passes — **A
(code)**: the save baseline moves with each successful profile write; a
non-whole stored value reads exactly ("7.5 h") and survives a Done that
changes only the period; Budget preselects Month unless the owner picked a
period; a stored type the measure does not list opens checked with its
reason; nothing opens while Save writes; a kind pick resets every override
except Counts as and a still-valid goal, the hidden three included; hours
formatted like counts; a stored non-headline measure reads as its own
name; de "Ablaufdatum", "Tabletten, Vitamine", "Gehalt, Honorare",
"Ferien, freie Tage", "z. B. Spaziert", "Zuletzt am", "Eigene Art",
"Eigenes Wort"; ro "Automat: …", "Ales automat pe perioadă", "… zile între
ele", "Interval în zile", "Zile rămase"; the one-height pin for hours,
count and tasks. **B (design)**: a `RowMetrics.groupGap` between the
alerts caption and REPORT (the digest editor's precedent; the label has
no top air of its own); the stepper decides beside-or-stacked from the
widest label among the offered types so a type switch moves nothing
(pinned by rect); the typed value gets the row's 48 dp hit height and a
tap anywhere in the box focuses it, with a visible edit affordance;
`AppDialogs.textInput`'s counter in `onSurfaceVariant` (it was the error
red for every consumer — pre-existing); **AO — a disabled row's reason
caption keeps full `onSurfaceVariant`** while the glyph, label and value
dim (1.94:1 was the faintest text in the sheet and the one line that
explains the state; applied to `FormMenuRow` and `FormPickerRow`); **AP —
a fixed goal-type order** (At least · At most or Budget · Days between)
with the kind's preset preselected, never reordered per category; the
period chips show no selection while Days between is chosen and remember
the last period; the guideline case at de 2.0 dark too. Accepted — the
goal sheet's measured heights replace the spec's table (429 / 490 / 490 /
575 with no stored goal, 495 / 556 / 556 / 645 with one; 623 for Tasks de
2.0). The device-only bucket (the menus at 2.0, the real keypad on the goal
field, TalkBack on the six rows and the uppercase labels, ink, ro
diacritics, the kind sheet's bottom inset) goes to S9.

**Gate and commit.** In the worktree after pass B: `dart analyze lib test`
clean, `flutter gen-l10n` with `untranslated.txt` `{}`, the whole suite
`+12716 ~11 -1`; committed on `analytics-s3`, rebased onto `66efe1f1`
without a conflict, fast-forwarded onto main as `fb9ae486` (36 files),
and the merged tree's gate from the lead: analyze clean, `+12860 ~12 -1`
(the known Windows-only case), `untranslated.txt` `{}`. The
`ui-language` reference `row-primitives.md` describes the typeable
stepper, `widestLabel` and the readable disabled caption (in the S2b-i
commit). The spec as accepted: `docs/calendar-analytics-specs/s3-design-
spec.md`.

#### S4 — report cards I (designed 2026-11-04, built after S2b)

**The designer's spec** (Opus 5.5, rendered from a `git archive HEAD`
snapshot with real fonts while the tree was mid-edit; the spec and renders
in the session's scratchpad): the current page and a missed one-off beside
a routine read right (nav 52 / 64 / 146, header 66 / 77.4 / 104, rows 62 /
67.4 / 94 — §4.8 of the report record holds), so Missed changes nothing.
Goals · Insights · Due soon come first, each a section label over a
`FormRowGroup` in a box sliver behind a `RepaintBoundary`, absent without
content, so an unprofiled page inserts no sliver and changes no string. A
goal row is `FormMeterRow` with three additive fields defaulting to today's
behaviour — `captionLines` (a wrapping caption whose line count comes from
templates written in 8s, never from the value, so a refold never changes
the card's height), `labelTrailing` (the state glyph at the end of the
name line), `compactLeading` (from 1.6 the avatar becomes the category's
glyph) — the meter in the category colour in every state, the streak as
the caption's last segment ("4 in a row": a trailing "× 4" broke names
mid-word), the glyphs met `check_circle_rounded` in `primary`, on pace
`timelapse_rounded`, behind / due `hourglass_bottom_rounded`, over / missed
/ overdue `error_outline_rounded` in `onSurface`, not started / planned
`radio_button_unchecked_rounded`; measured 66 / 84 at 1.0, 77.4 / 100.8 at
1.3, 104–176 at 2.0, five goals 370 dp at 360 en and 830 at de 2.0. An
insight is a `FormPickerRow` with the severity glyph in a 40 dp leading box,
the subject as the label and the sentence as a caption of at most
`ReportMetrics.insightCaptionMaxLines` (4). A due row is the routine-row
shape with a one-line phrase ("Overdue 32 days", "1 Nov · not marked"), "n
more ▾" expanding in place (so the model keeps every due row and the page
caps). Touches: a profiled category's header reads "31 h · 12 · 1 missed";
the Totals caption appends "22 working days · 1 public holiday" (only for a
calendar month or year whose categories include a Work, Meeting or Leave
kind, or a plan — unconditional would change every month report) and
"Hours incl. 6 h counted as" (the tile's half width holds 131.5 dp, the
footnote needs 161); the band reads "31 events · 2 of 3 goals on pace" in
place of the missed count only when the template fits without shrinking
("31 events · 2 goals on pace · 1 behind" squeezed to 0.35 at ro 2.0); after
a refold the page keeps the Totals label in place when the reader is past
the new cards.

**Its defaults, accepted by the lead:** A extend `FormMeterRow` · B the
streak in words · C the glyph on the name line, no red (K) · D template
line counts · E "this week" only when the shown period differs from the
goal's · F a past span of several periods reads "3 of 4 weeks met" · G a
goal tap scrolls to and opens its group (the More sheet past the cap) ·
**H the page drops G1–G3 and D1–D4 when the Goals or Due soon card already
shows that subject** (decision L's "never a sentence a tile already says";
it amends walkthrough 2 — Insights shows neither G1 nor G3 beside the Goals
card; the builder still ranks every insight, the readers filter) · I–K as
specified · L "n more" in place, the model uncapped · M a gap row opens the
sheet on its last kept day · N only a profiled category leads with its
primary (`ReportMeasures.profiled`) · O the footnote in the Totals caption
and the tile's spoken label · P the working-days gate · Q the band's
no-shrink rule · R the refold anchor on the Totals label (new code on the
scroll path — the design review and the device pass watch it) · S the ids
`report-goal-<categoryId>`, `report-insight-<n>`,
`report-due-<eventId>-<yyyy-MM-dd>`, `report-due-more` · T–W as specified ·
X moot: S2b lands first, so S4 builds Insights too. Model asks for S4's
build: `ReportMeasures.profiled`, `dueSoon` uncapped, `ReportInsight(id,
severity, subject, detail, target)`.

- **Built (2026-11-04, the second session)** in five implementer runs —
  S4a (words) and S4b-i / S4b-ii (the row primitive and the three cards) in
  a worktree (`C:\Temp\anta-wt-s4`, branch `analytics-s4`, squash-merged;
  the generated plugin registrants left out), S4c-i / S4c-ii (the page) in
  the main tree after S2b-ii — then three fix passes from two code reviews
  and one design review. `ReportLabels` gained every word (`goalCaption` /
  `goalStateWord` / `goalSpoken` / `goalTemplates`, the static `goalPeriod`
  and `closedPeriods`, `insightSubject` / `insightDetail` / `insightSpoken`
  / `insightSeverityWord`, `dueCaption` / `dueSpoken`, `money`, `subtitle(…,
  goals:)`, `subtitleTemplate`, the profiled `groupFacts` / `groupSpoken`,
  the caption and tile appendices) and ~90 ARB keys × 3; `FormMeterRow`
  gained `captionLines`, `labelTrailing`, `compactLeading` and a static
  `isCompact(scaler)` (`FormDividedRow.dividerIndentIn(context)` lets the
  indent follow the scale); `lib/widgets/report_analytics_cards.dart` holds
  `ReportGoalsCard`, `ReportInsightsCard`, `ReportDueSoonCard` (each with
  `canTap`); `lib/utils/report_insight_filter.dart` is H;
  `ReportGroupFolds.isDueSoonExpanded`; `ReportGroupStackState.reveal` and
  the shared `foldBackInPlace` / `revealAtTop`; the body's `_analyticsCards`,
  `_toGroup` / `_toInsight`, `onDueTap` / `onReveal` and the keyed
  `_AnchoredLabel` sliver (R); `AgendaPeriodNav.compactSubtitle` /
  `subtitleTemplate` (Q); `ReportMoreCategoriesSheet.measures`; the
  currency through `getCalendarReportSettings` → `ReportShown` →
  `ReportLabels`; ids `report-goal-<categoryId>`, `report-insight-<n>`,
  `report-due-<eventId>-<yyyy-MM-dd>`, `report-due-more`;
  `ReportMetrics.insightCaptionMaxLines` (4), `goalTemplateDigit`,
  `goalTemplateStreak`.
- **Decisions (S4, the lead's, beyond the designer's A–X):** **BA** money in
  the words reads whole units with the locale's grouping and the settings'
  symbol (attached as a prefix, after a no-break space as a suffix); the
  "of {target}" and over / left figures are bare; the ledger's own sheets
  keep the cents. **BB** a goal's closed shapes (Met / Missed / Within /
  Over) follow the period's own state — `end` before today — never the
  tense: a past week with a monthly goal reads its open period as pace; F
  counts closed periods only ("3 of 4 weeks met" = of the closed ones); on
  a span of several periods the glyph is met when every closed period was
  met, `timelapse` when some were (a partial result is not a failure, C)
  and the alarm when none; the spoken label omits a state word the caption
  already says; the band's past "n of m goals met" counts a goal met only
  when every period was. **BC** the templates (D) are narrowed by the
  reading — the closed words for one closed period, "8 of 8 weeks met" for
  several, "8 of 8 planned" for a plan, the pace / `=1` "one more" / done /
  left / over sentences for an open one — and a day-period goal's figures
  take three digits from the span's day count. **BD** H also drops D1 / D2
  beside a max-gap goal row and a milestone G4 beside a periodic goal row
  (the row ends "· 8 in a row"); D3 / D4 take the event's title as the
  subject. **BE** the band's goals form is "2/3 Ziele im Plan" / "2/3
  obiective în ritm" (the editor's "obiectiv", not "ținte"); it fits in de
  at 360 and still falls back in ro at 360 (the nav's rule, Q). **BF** the
  refold anchor is a `scrollOffsetCorrection` returned by the Totals label's
  own sliver (one frame, never a post-frame jump), keyed
  (`ValueKey(#totalsLabel)`) so a refold that changes the slivers above and
  below keeps its memory, and armed only under the same look (a step, a
  pick or a category change keep the raw offset); the end slack arms when
  the goals, insights or due rows change, not on every refold (D40 / D42
  of the report record hold). **BG** `revealAtTop` jumps after the next
  frame and checks once more (estimated extents above); the Due soon
  fold-back goes through the stack's `foldBackInPlace`; `onReveal` gates
  the in-body jumps and carries the haptic click (null in the guide's
  stage, whose rows stay read rows). **BH** a row `canTap` refuses is a read
  row; on `FormPickerRow` it still carries a disabled-button flag (the
  primitive's rule, left for S8); the picker rows keep text at x 70 at 2.0
  while goal rows go compact (the designer's §2.3 — a `compactLeading` on
  `FormPickerRow` is a question for the design record). **BI** a gap row
  past the lookback opens the event on its start day (the last kept day is
  unknown). **BJ** `ReportMetrics.goalTemplateStreak` is the two-digit
  floor; a day goal's streak can reach three digits from the lookback in
  any span (the template reserves them only in a long span — accepted).
- **Reviews (S4).** Two `reviewer`s (the words, filter, row and cards; the
  wiring) and one `design-reviewer` (18 real-font renders across the
  matrix, geometry on the spec's table at every cell, contrast from
  tokens, the three guideline matchers; no severity 3–4). Taken in the
  three passes: the anchor's lost memory (CONFIRMED: an unkeyed sliver),
  the spring-back near the end, a step anchoring, the past-span open
  period reading "Missed" (CONFIRMED), the missing `=1` template
  (CONFIRMED), the over-reserved lines on closed and planned rows, the
  doubled spoken state, the several-periods glyph, money's ".00", the de
  band and due phrases ("32 Tage abgelaufen", "offen"), `=0` due phrases
  ("Due today"), D1 / D2 beside a gap goal, G4 beside a goal row, D3 / D4's
  subject, the line cache keyed on the currency and today, one compact
  rule, the profiled-header pin at de / ro 2.0, the reviewers' test gaps.
  Accepted as built: faint meter tints (the groups' existing behaviour),
  the 20 dp glyph at 2.0 (the spec's own risk), the meter's reversed sense
  on a gap goal (the glyph resolves it), two identical captions with
  different glyphs (behind vs not started — the glyph and the word
  differ), a missing event titled by its id (unreachable), ro due phrases
  of 21 characters where no shorter natural form exists, the picker rows'
  x 70, a goal past the cap opening the More sheet without scrolling to
  its group inside it. Device-only, for S9's pass: TalkBack on the goal
  rows (one node, no doubled state), the Due soon fold announcement, the
  anchor's and the reveal's frames, ink states, the AOSP 200 % curve in
  de / ro, the gesture-bar clearance with Due soon expanded.
- **Measured (the design review, ±1 dp, 360 and 412, light and dark, en /
  de / ro):** goal rows 66 / 84 at 1.0, 77.4 / 100.8 at 1.3, 104 / 140 /
  176 at 2.0 plus a four-line 212 (a ro weekly hours limit in a month
  view); insight rows 62 / 74, 67 / 90, 130 / 166; due rows 62 / 67 / 94;
  the disclosure 48 / 48 / 52; the header 66 / 77.4 / 104; the unprofiled
  October page pinned (14 slivers, the Totals label at 82, the card at 102,
  the extent 574) and the guide's stage green.
- **Gate (S4).** `dart analyze lib test` clean; `dart format` clean;
  `flutter gen-l10n`, `untranslated.txt` empty; the whole suite `+13064 ~12
  -1` (the known Windows-only case). 33 files; the commit hash is in the
  hand-off at the head of §12.2.
- **Noted for S5 / S8:** `_againstName` in the body always steps the period
  back, so under Compare: last year the caption would say "against
  September 2026" — S5 wires the compare choice and fixes it; the two
  other hand copies of the compact rule (`category_delete_sheet.dart`,
  `calendar_guide_try_categories.dart`) can call `FormMeterRow.isCompact`;
  `FormPickerRow`'s button flag on a refused row and its leading box at
  2.0 are S8 / design-record questions; `_periodsMetReading` in the card
  mirrors the labels' private predicate — make it public when touched.

#### S5 — report cards II (designed 2026-11-04, built after S4)

**The designer's spec** (Opus 5.5, real-font renders from a HEAD snapshot
with the cards composed from the page's own primitives; the ramp checked
with the dataviz skill's validator; the spec and renders in the
scratchpad): the order Categories · By tag · Over time · When · Balance ·
Missed · Ahead · Compare row + footer, each card absent without content.
**By tag** on the Categories-group shape (`FormMeterRow` inside
`ReportGroupStack` under a new `ReportCard.tags`), closed by default with
the first four tags and "n more ▾" in place (open by default was 617 dp at
1.0 and 905 at 2.0), the first category's `EventAvatar` leading, the meter
count over the largest tag in that category's colour, two facts per tag
with the kind's noun ("6 evenings · last Fri 24", "2 trips · 5 days", "3
services · 1,240", else "times" / "once" — three facts shrank to 0.53 at
de 2.0), lines from templates; an open tag shows the dated rows. **When**
(`report_when_chart.dart` on the trend's card): the weekday label column
measured as drawn plus 8 dp, column pitch (width − labels) / 24 with 2 dp
gaps, row pitch the caption line clamped between one and two column
pitches (square cells lost five weekday labels at 2.0), weekday labels
every ⌈line / rowPitch⌉-th row, hour labels stepping by the smallest of 3
/ 6 / 12 that fits, the ramp `Color.lerp(rowGroup, primary, [0.5, 0.67,
0.84, 1.0])` with empty cells in `rowDivider` (light 2.18 · 3.03 · 4.29 ·
6.12:1, dark 3.46 · 5.05 · 7.15 · 9.56:1 — a 25 / 50 / 75 / 100 % ramp's
lightest step was 1.44:1 in light), linear steps to the busiest cell, no
legend, the caption "Busiest: Tuesday · 18:00–19:00", one semantics node;
202 / 234 / 285–294 dp. **Balance**: one `FormMeterRow` per area, largest
first, the area's glyph in `onSurfaceVariant`, "38 h · 67 %", the meter in
`primary`, read-only. **Compare with**: a `FormMenuRow` as the footer's
first row (the period menu with a compare section grew to 620 dp, flipped
above the title and scrolled its section out of sight at de 2.0) — Previous
period · Same period last year (dimmed before the calendar's first year) ·
each saved view by name or a dimmed "No saved views"; the choice lasts for
the visit; last year: the tiles' deltas read it, the caption "against
October 2025", the trend draws last year as a column-wide tick on top with
a 1 dp `rowGroup` ring (an outline behind hid last year wherever this year
was higher; in dark the tick and the column are 1.00:1 without the ring)
and a "Last year" legend item; a saved view stacks a second Totals card
under the view's name at 360 and sits beside at ≥ 600 dp, both with the
page's tile set and no deltas, the caption "beside Work / Life".

**Its defaults, accepted by the lead:** A the footer row (§6.11's "period
menu" amended) · B the nouns and two facts · C–D the ramp and linear steps
· E Balance by hours · F `CalendarIcons.areaIcon` · G saved views listed in
the menu · H the choice per visit, not a setting · I no deltas against a
view · J the view's card uses the page's tiles · K the tick, not the
outline · L rows up to twice as tall · M no legend · N the caption names
the day and the hour · O tags closed, four shown · P tag headers carry a
meter. Model asks for S2b-ii / S5: Sleep out of When (the counts-hours
rule), `ReportTag.kind`, `ReportTrend.lastYear`, the compared view folded
with the page's tile set.

**Built 2026-11-04 by layer**, each layer committed after the whole suite:
S5a words, constants and ids `0abb2f69` (17 ARB keys × 3;
`ReportLabels.tagWords` / `whenWords` / `balanceWords` / `compareName` /
`caption(beside:)`, the trend's spoken last-year tail;
`ReportMetrics.when*` and `trendLastYear*`; the §2.9 ids;
`CalendarIcons.areaIcon`); S5b widgets `67858816` — S5b-i in the main tree
(`report_when_chart.dart`, the trend's tick, ring and "Last year" legend
bar, `ReportTotalsCard.tileIdentifier`) beside S5b-ii in a worktree
(`ReportCard.tags`, the tags inside `ReportGroupStack` through `tagGroups`
/ `tags` / `preview` with the card-level "n more" `report-tags-more`,
folds closed by default for tags only, `ReportBalanceCard`, the shared
`reportCaptionLines` helper); S5c-i body and S5c-bloc `bfa59f0f`
(`ReportBody(compare:, compareView:, views:, onCompare:)`, the three cards
in §2.1's order, the Compare row, `_totalsCards` stacked or side by side
from 600 dp of the body's width, `ReportComparePicked(compare, {view})`,
`ReportShown.compare` / `compareView`, the bloc's `views:
OverviewViewService.getInstance()`); S5c-page `55207ac6` (the page glue,
six end-to-end page cases, the fixture's `qa-cal-coffee` "Coffee with
#ana" and the saved view `qa-view-strength`, flow `32_report_cards.txt`,
flow 24's `--nth 1`); the fix passes B1 `0588f418` and A1 / A2 / B2 (the
hash in the hand-off).

**The reviews** (two code reviewers and the design-reviewer, from a
`bfa59f0f` snapshot; no finding at severity 3–4) and their fate:
- CONFIRMED, fixed: Share under a saved view wrote the previous period's
  bare deltas — `onShare` and `ReportMarkdown.render` take `beside`, the
  deltas are omitted as on the page, the view's own column in the Markdown
  is S7's; a view pick from the footer pushed the footer off screen (the
  second Totals card grew below the anchor) — S6's decision H brought
  forward, the refold anchor is the nearest section label above the
  viewport's top; bold text was not measured for tag and goal captions —
  the shared helper merges `FontWeight.bold` under `boldText`; the "last
  …" template took the longest name by characters ("So." over "Mo.",
  "Sun" over "Wed") — `tagTemplates(widest:)` takes the widget's measuring
  callback; a net of 1–49 cents read "€0" — tested on the rounded units;
  a month so far under last year names the counted days (D28, "Oct 1 –
  Oct 30, 2025") and the body test had pinned a state the fold never
  produces — the test and §2.5's example corrected (a whole month names
  the month); ro headers reserved blank caption lines — the templates
  follow the row's own fact kind and digit counts in 8s (as S4's money
  templates), so a refold that changes a digit count or the fact kind may
  change a row's height, accepted; disclosures spoke "#" — `reportTagName`
  "tag ana", `reportTagsMoreSpoken` / `LessSpoken`; the avatar could name
  another category than the noun — `ReportTag.kindCategoryId`; Balance
  shares summed to 101 % — `ReportLabels.shares` (largest remainder); the
  When caption broke at the en dash and used hour-only times — bound with
  word joiners, `EventTimeFormatter`; a tick at the peak sat on the top
  hairline and the When label boxes overhung the grid — clamped.
- Bloc: the saved views ride in `ReportShown.views` (fresh at every emit,
  so the page reads no service); `ReportFolding.previousCompare` /
  `previousCompareView` name the view of the report drawn (D36.9); a
  non-view pick never waits on the views service; last year falls back to
  Previous before `years.first` (the row's dimmed rule) and a deleted view
  falls back on its next fold; the fold key compares the view's id, name
  and categories (a reorder refolds nothing); a database switch is read
  from `DatabaseLifecycle.generation`.
- Accepted, noted: per-tag cards with the group gap (the Categories shape;
  the closed card 384, not 316) and the card-level "n more" as its own
  card (the "n more categories" precedent — the design review calls it
  the weakest element; judge on a device); tag header heights beside the
  chevron (66 / 77.4 / 140 after the templates fix); the trend with ticks
  at de 2.0 is 342 (the suite's German month height); the de / ro Compare
  row stacks at 1.0 (54 dp; the footer 201 / 213 / 333, pinned); the en
  percent "67 %" through `reportPercent`, the Attended tile's grammar (the
  design review finds it unidiomatic — the owner's call for both); the
  ramp's step 1 against an empty cell 1.78:1 (texture; the facts are
  words); a money fact is bare without a ledger currency; a Trip counts
  `tag.events`; `whenWords` takes the week start because
  `ReportWhen.busiestWeekday` is a row from it; `ReportTotalsCard` takes
  a `tileIdentifier` callback rather than the spec's `idPrefix`, so
  `SemanticsIds` keeps every id string.
- **Open edges, for S6's review** (noted by the fix passes, not fixed):
  the page's slack-arming rule (`_sameCardsAboveTotals`) still reads only
  the cards above Totals, so with the wider anchor a refold that also
  shrinks content below the anchor could correct past the new end and
  spring back; an anchor label that itself leaves in the refold (reading
  under Insights when every insight vanishes) corrects nothing; a failed
  fold re-emits the last Ready, whose `views` are that fold's; the row's
  dimmed last-year rule reads the service's clamped span while the bloc
  reads the unclamped one (they differ only at `CalendarBounds`).
- **For S9's device pass** (the design review's bucket): TalkBack on a tag
  header ("tag ana", one button node, expanded) and its disclosure; the
  When and Balance nodes read once; the compare menu near the bottom
  inset under gesture and 3-button navigation; a 600 dp device and
  landscape; real de / ro copy and ro diacritics; ink on the new rows;
  the Android non-linear 200 % scale on When's label column and the
  legend wrap. Flow 32 lists Same period last year but cannot pick it:
  the seed has no event a year back (a `{{today-365}}` one-off would add a
  2025 section to the overview's Year scroll that flows 05 and 23 walk).

**Decisions (continuing S4's lettering):** BK per-tag cards with the gap ·
BL templates by the row's shape and digit counts, bold-aware, the widest
name measured · BM a Trip counts `tag.events` · BN `whenWords(weekStart:)`
· BO the en percent through `reportPercent` · BP the compare choice per
visit in the bloc, `views` and the folded view in the state, the two
fall-backs, the key by id / name / categories · BQ the body draws from
`report.compare` / `compared` and shows the asked choice as the row's
value · BR a view compare strips the deltas on both cards and Share
writes "beside" with no deltas · BS the refold anchor is the nearest
section label above the viewport (S6 H, brought forward) · BT spoken tag
names say "tag", the avatar from `kindCategoryId` · BU
`ReportTotalsCard.tileIdentifier` · BV flow 32 and the two fixture
entries.

**Gate (S5).** `dart analyze lib test` clean; `dart format` clean on the
slice's 18 files (25 older files elsewhere would reformat — not touched);
`flutter gen-l10n` reproduces the committed generated files,
`untranslated.txt` empty; the whole suite `+13215 ~12 -4` on 2026-11-05:
the known Windows-only host-devices case and **three guide try-cards
cases that are red at the pre-S5 commit too** ("a stage never changes
height at text scale 2.0 — screen: every panel mode", where the day
timeline overflows twice on 2026-11-05's sandbox data, and the two
"tap-target and text-contrast guidelines — screen 360 / 412 light" cases,
whose contrast sampler reads the report stage's "2 events" caption off its
rect) — the stage runs on the real clock (the 2026-11-01 trap), so these
are date drift, not the slice; §14 carries the clock pin. S5 is on `main`
as `0abb2f69` (S5a), `67858816` (S5b), `bfa59f0f` (S5c-i, S5c-bloc),
`55207ac6` (S5c-page), `0588f418` (B1), `830e7645` (B2), **`8855bf29`**
(A1–A2, the last); the docs commit follows it.

#### S6 — year in review (designed 2026-11-04, built after S5)

**The designer's spec** (Opus 5.5, real-font renders of a 2025 fixture
seen from 2026 — six categories, two weekly goals, a gap goal, two trips,
car services — across the matrix; the spec and renders in the scratchpad):
§6.12's five cards become **two new cards and two year readings**, since
the others would duplicate what S4 and S5 already show. The year cards
draw when `report.year != null` — the span is exactly 1 Jan – 31 Dec
however it was picked (This year, Last year, a paged year, an equal Custom
range) and not a plan — after the Totals caption, before Categories:
**Records** (`ReportRecordsCard` in `lib/widgets/report_year_cards.dart`):
read-only `FormMeterRow`s with no meter (a `FormPickerRow` cut "Most
social month…" and thirteen de / ro strings at 2.0), the glyph in
`onSurfaceVariant`, the record's name as the label (two lines), "{subject}
· {value}" as the caption (one line, two reserved from 1.6), the kinds in
order busiest month · busiest week · most social month · biggest spend ·
longest trip · longest streak per tracked event (from
`AnalyticsMetrics.recordStreakMin` 3) · longest gap per gap-target
category, the first `ReportMetrics.yearRecordRows` (6) then "n more ▾" in
place; 62 / 67.4 / 130 dp rows. **Months** (`ReportMonthsCard`): an axis
row of month initials (the trend's `MMM` / `MMMMM` rule, every step-th
month from [1, 2, 3]) over one strip per category in the Categories order
(7 then "n more ▾"): `FormMeterRow(EventAvatar, name, caption "Jan 2 – Dec
30" — the firsts and lasts as a range, since the worded form made 152 dp
rows and a 966 dp card at 2.0 —, chart: twelve tiles of pitch (W + 2) / 12
by `yearTileHeight` 16, radius 2, S5's `primary` ramp stepped to the
strip's own peak, an empty month in `rowDivider`, a month still ahead a 1
dp `outlineVariant` outline, onTap its group)`, one spoken node per strip;
78 / 89.4 / 116 dp rows, a six-strip card 504 / 577.8 / 750. **Goals on a
year**: a periodic goal shorter than a year reads "41 of 52 weeks met ·
longest streak 11" (closed periods only, the meter met / closed). **Balance
with Compare: last year**: the union of both years' areas, the meter scaled
to the max of both, last year as a 2 × 10 dp `onSurfaceVariant` tick with
a 1 dp `rowGroup` ring (`FormMeterRow.marker`), the caption "1,720 h · last
year 1,650 h". **Last year** joins the period menu after This year with
This year's glyph (the eleven-row menu stays at 496 dp and never scrolls
or flips at 360 × 780), id `report-period-last-year`, reopening as This
year. Ids `report-year-record-<kind>`, `report-year-records-more`,
`report-year-months-<categoryId>`, `report-year-months-more`; the
constants `ReportMetrics.yearRecordRows` / `yearRecordCaptionLinesCompact`
/ `yearTileHeight` / `yearAxisPadding` / `yearAxisSteps`,
`FormMetrics.meterMarkerWidth` / `meterMarkerRing` / `meterMarkerOverhang`,
`AnalyticsMetrics.recordStreakMin`; `FormMeterRow` gains `chart` and
`marker`.

**Its defaults, accepted by the lead:** A the past and the current year,
never a plan · B no Goals met card — the Goals card reads the year's tally
· C seven strips then "n more" · D firsts and lasts as the strip's caption
range · E `chart` and `marker` on `FormMeterRow` · F the `primary` ramp,
empty months in `rowDivider`, months ahead hollow · G By area is Balance
with the upright last-year tick · H S4's refold anchor becomes the nearest
section label above the viewport · I record rows read-only · J six records,
streaks from three · K the name as the label, the subject leading the
caption · L the glyphs as specified, no fire icon · M Last year after This
year, no Next year · N the axis at the top of the Months card. **A year
page gains the two cards on any calendar, profiled or not** (decision N:
a year is a span like any other; month and week pages stay pixel-identical
and the October golden and the guide's stage stay pinned). Model asks for
S2b-ii: `CalendarReport.year` (`records`, `months` — twelve values per
category in the primary's unit —, `spans` — first and last kept day per
category to today —, `goalTallies` — met, closed, longest streak per
periodic goal), `ReportRecord(kind, categoryId?, eventId?, value, start,
end?)` with ties to the earliest, `CalendarReport.balanceLastYear` under
Compare: last year.

**Built 2026-11-05 by layer**, each layer committed after the whole suite
(green apart from the Windows host case and the three date-bound guide
cases of the S5 note): S6a words, constants and ids `46680e15` (21 ARB
keys × 3 — the record names in de "Stärkster Monat … Längste Lücke", in
ro "Luna de vârf … Pauză maximă" with "Socializare maximă" for the social
month, since the spec's ro draft ran 20 characters against its own
18-character rule; `ReportLabels.recordName` / `recordWords` / `yearSpan`
/ `yearSpanTemplates(widest:)` / `yearSpanSpoken` / `yearMonthsSpoken` /
`goalYearWords` / `balanceLastYearWords`; `ReportMetrics.year*`,
`FormMetrics.meterMarker*`; the §2.7 ids); S6b-i `ec8642d4` in the
worktree (`FormMeterRow.chart` and `marker` with their asserts — a chart
and a fraction never together, a marker only on a meter —, the marker a 2
× 10 dp `onSurfaceVariant` bar with its 1 dp `rowGroup` ring painted
outside the 4 dp track so the row's height never changes, the chart row
78 / 89.4 / 116; the three constants added on both sides and deduped at
the merge); S6b-ii `a4231338` (`lib/widgets/report_year_cards.dart`:
`ReportRecordsCard`, `ReportMonthsCard`, the axis row and
`ReportYearStripPainter`, which reuses the When chart's `fillFor` /
`stepFor`; `ReportGroupFolds.isRecordsExpanded` / `isMonthsExpanded`; the
Goals card's year reading with the meter met / closed; Balance's
last-year path — the union of both spans' areas, the scale over both, the
marker, `balanceLastYearWords`); S6c-i `6269288e` in the worktree
(`ReportPeriodChoice.lastYear` after This year, `choiceLabel`, the page's
`today_rounded` glyph and `report-period-last-year`, the bloc's `_keptOf`
`lastYear → thisYear`; the eleven-row menu 496 ±1 dp at en 1.0, never
scrolling at 360 × 780); S6c-ii (the body's year block after the Totals
caption, the strip tap to its group, flow `33_report_year.txt`) and the
week-name words fix — the hashes in the hand-off.

**Measured against the spec:** Records row 62 / 67.4 / 130, disclosure
48 / 48 / 52, card 426 / 458.4 / 838 (ro 2.0 842, not 1,038: a wrapped
name adds 4 dp under the reserved caption lines, not 40); Months axis 30
/ 35.4 / 48 in the **narrow** month names at every scale on a 360 or 412
pitch (the trend's own rule: "Jan" is wider than pitch − 4), step 1 / 1 /
2, strip row 78 / 89.4 / 116, a six-strip card 504 / 577.8 / 750, tiles
18.67 / 20.17 / 23 × 16, the ramp's step 1 ≥ 2:1 against `rowGroup`
(1.77 / 2.61 against the empty tile); Goals year rows 66 / 84 at 1.0,
100.8 at 1.3, 140 / 176 at 2.0 (ro 176 / 140, card 422, not 530);
Balance with last year 267 at 1.0 and 563 at de 2.0. **One defect found
by the build itself:** the busiest-week caption carried the year ("Jun 16
– Jun 22, 2025 · 11 events") and was cut in the one line reserved below
1.6 at 1.3 on 360 — the week is now named without the year (the band
shows it).

**Decisions (continuing S5's lettering):** BW the busiest week reads
"Jun 16 – Jun 22", no year · BX Today returns to the picked year — the
home rule D36.7 that Last week and Last month already follow; the spec's
"Today returns to This year" amended; the report still reopens on This
year · BY the Months axis in narrow names wherever the short ones do not
fit the pitch (the trend's rule, not a scale threshold) · BZ the Months
cap is `AnalyticsMetrics.yearMonthsStripCategories` (7; the spec's
`maxCategoryRows` is the same number) · CA under a chart with
`captionLines` the words keep their reserved box and the chart sits
below, so a strip row never changes height with its caption · CB a strip
needs both a `months` and a `spans` entry; Balance with last year draws
from two areas across both years · CC `onCategoryTap` is optional, so the
guide's stage draws read strips.

**The reviews** (two code reviewers and the design-reviewer, from a
`59bad68c` snapshot; no finding at severity 3–4) and their fate:
- CONFIRMED, fixed: a refold at the scroll's end that grows Records or
  Months while content below leaves corrected 163 dp past the new end and
  kept sliding — the page's slack-arming rule compared only the cards above
  Totals; it now also compares the record count and the strip set (rows
  never change height, so count and set suffice); a busiest week across a
  month was still cut below 1.6 (ro 1.3 "29 sept. – 5 oct. · 12
  evenimente") — the Records rows take `captionLines` from measured
  `recordTemplates(widest:)` like Months and Goals, no longer from the
  scale alone; a year goal with no closed period read "0 of 0 weeks met"
  with an empty meter — with `closed == 0` the card keeps S4's reading;
  `_weekSpan` recomputed the week from a `weekStart` and ignored
  `record.end` (a year-end week counted to 31 Dec read "Dec 28 – Jan 3")
  — the record's own days are named and `weekStart` left `recordWords`;
  the busiest week was spoken as drawn ("Dez. – Jan.") — spoken through
  `yearSpanSpoken`; a money-month record under half a unit read "June · 0"
  — skipped by the builder; `yearSpan` compared days with `==` across UTC
  and local — by y/m/d; the strip's spoken list said "November 0, December
  0" for months still ahead and eleven zeros for one kept day —
  `yearMonthsSpoken(aheadFrom:)` stops at today's month and skips zero
  months; "Weniger anzeigen" wrapped at de 2.0 / 360 and grew the expanded
  disclosure from 52 to 92 dp — de `reportGroupLess` is "Weniger"; count
  phrases split ("9 in / Folge") — bound whole; hours group their
  thousands ("1,720 h", the spec's copy; nothing under 1,000 changes);
  Balance's last-year marker sat at the track's start for an area with no
  time last year — no marker at 0; the marker's ring reached 1 dp outside
  the track at 0 and 1 — clamped; the axis row laid out up to 24
  `TextPainter`s per layout and a `RegExp` per record row per build —
  memoised / static; a strip could be a button that does nothing on a
  surface wiring only one of `onReveal` / `onMoreCategories` —
  `ReportMonthsCard.canTap` per strip, as the Goals card guards; a leaving
  anchor label corrected nothing — the anchor is picked among the labels
  the new build keeps; flow 33's comment overclaimed (Last year folds the
  previous year until about 9 February because `qa-cal-checkup` starts at
  `{{today-40}}`) and its shots waited on a tile drawn before the pick —
  corrected; stale docs on `checkedFor`, `_AnchoredLabel` and the slack
  rule.
- Accepted, noted: steady routines saturate the strip (linear steps to the
  strip's own peak, S5 D / S6 F; a quartile ramp was the rejected
  alternative — judge on a device); the axis at 2.0 reads "J M M J S N" —
  the short names are now tried at each thinning step before the narrow
  ones, so 412 at 2.0 gains them where they fit; "Biggest spend" is bare
  without a ledger currency (the ledger's display config, as S5's money
  fact); the 22 dp compact glyph beside 26 px text at 2.0 (S4's rule);
  Balance's templates follow each figure's digit count (S5's rule, a
  refold past 999 h may add a line); no pixel golden exists for the report
  (the October page is pinned by geometry); a Custom range equal to a year
  draws the cards and steps by 365 days (the existing custom-step rule).
- **For S9's device pass**: ink on a strip row with the tiles; TalkBack on
  a strip (the months list's length, no "0" for November and December);
  the menu's deepest row near the 3-button bar at de 2.0; the refold
  anchor's timing when a strip appears under the finger; real de / ro copy
  and ro diacritics ("Săptămâna de vârf", "16.–22. Juni", "16–22 iun.");
  "Weniger ▴" under the finger at de 2.0; Android's 200 % font curve on the
  Records and Months cards.

**The fix passes amended the build**: Records rows reserve the lines
their measured template takes (62 / 67.4 / 94 for one caption line at
1.0 / 1.3 / 2.0, a further line 18 / 23.4 / 36), so the 2.0 card is 730
in en / de (734 ro), not the spec's 838 / 1,038 — the two reserved lines
from 1.6 were the blank band the design review called out on S5's tags;
the axis tries the short names at each step, which 412 at 2.0 gains in de
only ("May" misses the pitch by 0.7 px in en, "sept." in ro); the leaving
anchor hands over to the first label *after* it that the new build draws
(holding the nearest surviving label *above* would have moved everything
below the leaving card), with the correction clamped at the scroll's
start; the slack arms when the goals, insights, due rows, the records
drawn (by kind and subject, not value) or the strip set change.

**Gate (S6).** `dart analyze lib test` clean; `dart format` clean on the
slice's files; `flutter gen-l10n` reproduces the generated files,
`untranslated.txt` empty; the whole suite `+13333 ~12 -4` on 2026-11-05
(the Windows host case and the three real-clock guide cases of the S5
note). S6 is on `main` as `46680e15` (S6a), `ec8642d4` (S6b-i),
`a4231338` (S6b-ii), `6269288e` (S6c-i), `616101c1` (S6c-ii), `59bad68c`
(the week name), `2c7606b1` (fix pass B) and the fix passes A with the
glue (the hash in the hand-off); the docs commit follows.

#### S7 — digests and share (built 2026-11-05)

**Built as two halves on disjoint files** — S7-i the report digest in a
worktree, S7-ii the shared Markdown in the main tree — each gated by the
whole suite and committed: **S7-ii `8202b736`** — `ReportMarkdown.render`
writes, in the page's order and each only with content, `## Goals` ("-
Gym: 14 of 12 · Met" through the new `ReportLabels.goalSharedCaption`:
the card's caption then the state word where the caption does not say
it, the spoken forms' rule), `## Insights` (the page's filter and cap,
never in a plan), `## Due soon` (every row, "- Gym: Due in 3 days"),
Totals as before with, under `beside`, a `### {view}` sub-list of the
compared tiles without deltas (the column S5 deferred), on a whole year
`## Records` ("- Longest trip: \*Sibiu\* · 6 days") and `## Months` ("-
Gym: Jan 2 – Oct 29 · Jan 9 · Feb 8 · Mar — · …" through the new
`yearMonthsLine`, months still ahead left out, a zero month the dash),
Categories as before, `## By tag` ("### #leg\_day · 6 evenings · last Fri
24" then the dated rows as a group's), Over time as before, `## When`
(the caption), `## Balance` ("- Work: 38 h · 67 %", the last-year form
under Compare), Missed and Ahead as before; `render(weekStart:)` so the
shared weekday names follow the app's week start (the page passes the
shown state's); a new `_escapeInline` escapes Markdown's syntax mid-line
without the list-marker rule, so a user title inside a caption never
shows a stray backslash and a "# Plan" title never becomes a heading; the
unprofiled golden byte-identical. **S7-i `e19abc3a`** — the weekly /
monthly report digest's body gains, after its unchanged summary line and
before the category lines, within `kDigestMaxLines`: "Goals · Gym 2 of 3
· Work 42 h (over 40) · Dentist 162 days (limit 180)" (≤
`digestGoalLines` 3, ranked by the state word — past the limit / over /
behind / missed first, then due soon, on pace, met, planned, not started
—, the items through the new `goalRank` / `goalDigest`: met "✓", over in
brackets, a gap's figures in brackets because the line's own dot parts
its items, a past span of several periods "Gym 3 of 4 weeks met"), "Due ·
Car service overdue 32 days · Dentist in 18 days" (≤ `digestDueLines` 2,
the card's phrases lowered and without their date through `dueDigest`),
then the top insight ("Trips · 212 days since the last, the limit is
180", the page's filter taken to `insightsInDigest` 1); eight
`reportDigest*` keys × 3 (de "Ziele" / "Fällig", ro "Obiective" /
"Scadente"); a digest with none of them byte-identical to before; the
words live in `ReportLabels` so the page and the digest never judge a
goal two ways. The two halves met in `report_labels.dart` (both appended
methods after `goalSpoken`); the merge kept both.

**The review** (one reviewer, from an `e19abc3a` snapshot; nothing
severe) and its fate:
- **A decision, not a defect:** a calendar with no profile but a `#` word
  in a title now shares a `## By tag` section, so §1's "`ReportMarkdown`
  for an unprofiled report" is amended — the unprofiled share changes only
  by By tag, the exception the page has made since S5 (a tag is untyped
  and needs no profile; §7 asks for the section). The golden's fixture has
  no tag, so the fix pass adds a builder-folded unprofiled report with and
  without a tag.
- CONFIRMED, fixed: an empty goal caption left " · not started" in the
  share while the digest said "0 of 3" — empty parts dropped, the digest
  item becomes the state word; `insightsInDigest` was honoured only to one
  line (`.take(n).firstOrNull`); the tag, view and group headings escaped
  with the list-marker rule ("### #\-x", "### 1\. Morning") — headings take
  `_escapeInline`; the view's column was lost when the own tiles were
  empty; the shared goal line put the state word after the streak while
  the spoken form says it before; `reportDigestGoalGap` repeated
  `reportGoalLimit`'s words — composed from the card's phrase; stale docs
  (`ReportInsightFilter` "the digest reads insights whole", the digest's
  "never repeats what the lines above say" — it drops insights about every
  goal and due row, shown or not, which stays).
- Deduplicated: `aheadFromMonth` on the model (the Months card, its spoken
  label and the Markdown computed it apart), the Balance order in one place
  for the card and the share, the category-name fall-back, `dueDigest` on
  `dueCaption`'s own parts.
- Noted, not changed: the digest's `ReportLabels(strings)` has no currency,
  so a money goal reads "1,340" where the page may read "€1,340" — pre-
  dates S7, §14; the digest's insight filter drops more than the three
  goals and two due rows it shows (an insight about a fourth goal is never
  said) — the brief's rule, kept.

**Gate (S7).** `dart analyze lib test` clean; `dart format` clean on the
slice's files; `flutter gen-l10n` reproduces the generated files,
`untranslated.txt` empty; the whole suite `+13414 ~12 -4` on 2026-11-05
(the Windows host case and the three real-clock guide cases). S7 is on
`main` as `8202b736` (S7-ii), `e19abc3a` (S7-i) and `3885ef3d` (the fix
pass: headings through `_escapeInline`, the view column outside the
tiles guard, one digest line per insight up to `insightsInDigest`, the
state word before the streak, the gap phrase from `reportGoalLimit`, the
Balance section gated on `balanceRows()` as the card is, the shared
`CalendarReport.aheadFromMonth` / `balanceRows()` and
`ReportLabels.insightCategory` / `_duePhrases`, the ten new cases); the
docs commit follows S8's.

#### S8 — the report cards setting, the settings page, the docs (built 2026-11-05)

**Built in three layers**: **S8a `c09ef7a7`** — `lib/models/report_cards.dart`:
`ReportCardKind` in the page's default order (goals, insights, dueSoon,
totals, records, months, categories, tags, overTime, when, balance,
missed, ahead; the footer is no card) and `ReportCards` (`order` + `off`,
`shown`, `defaults`, `encode` / `decode` in the grammar
"goals,insights,-dueSoon,…" — unknown names skipped, missing names
appended in the default order, a repeated name keeps its first place;
`moved(oldIndex, newIndex)` with `onReorderItem`'s indices, `toggled`),
`SettingsKeys.reportCards` ("calendar_report_cards";
`setReportCards(defaults)` deletes the key, so a card a later version adds
lands in its own place), `getCalendarReportSettings` → `cards`,
`ReportShown.cards` refreshed on every re-read (a resume re-emits Ready
with the new list and no `ReportFolding`), the ids
`calendar-settings-report-open`, `report-card-switch-<kind>` /
`-handle-<kind>` (the enum's camelCase name), `report-cards-reset`, four
strings (Totals reuses `reportSectionTotals`). **S8b-i `9cfd9b99`** — the
body walks `cards.shown` through one `switch` per card, each card keeping
its own gate and slivers, a single gap rule (`_spaced`: a gap before every
drawn block but the first — no leading, double or orphan gap), the Totals
block one card (its caption leaves with it), `_labelIds` on the same walk
so the anchors follow the order; a tap that would land in an off card has
no tap (goals, category insights and strips with Categories off; a tag
insight with By tag off falls back to the category's group); the page's
slack rule reads the cards and skips the off ones; with every card off the
footer alone remains; under `defaults` every pre-S8 sliver pin holds
unchanged. **S8b-ii** (merged with the gate below) —
`CalendarReportSettingsPage` under Settings → Calendar → **Report cards**
(the row after Alerts: `bar_chart_rounded`, the title, the description,
the thirteen names as search keywords, `calendar-settings-report-open`;
`AppNavigator.toCalendarReportSettings`, `NavDestinationKind.reportSettings`
appended and restored): `SettingsAppBar`, the kit's group drawn by hand
because its `ListView` holds no reorderable sliver — the description as
the group's intro, a `SliverReorderableList` of thirteen rows (the shared
`FormDragHandle` 48 × 48, the name wrapping at 2.0, a `Switch` the single
spoken control; an off row dims to `switchedOffOpacity`), then a Reset to
default row disabled on the defaults, writing them with the snackbar;
every move and toggle writes at once; the fasting page's shape; flow
`34_report_cards` (Settings from the calendar's ⋮, the row, a card off and
on). **S8c** — the docs: `calendar-events` SKILL.md (an Analytics rules
block and a reading-map row), its `references/subsystems.md` ("The
analytics layer"), `calendar-ui` SKILL.md (the id families and flows
30–34), `docs/calendar-events-feature.md` (the 2026-11-05 addendum),
`docs/calendar-report-roadmap.md` (§4.1 and D31 addenda); the guide is
untouched (V).

**Decisions (continuing S7's lettering):** CD the cards setting's grammar
and the defaults-deletes-the-key rule · CE the page's camelCase id suffix
· CF the settings page draws the kit's group by hand around a
`SliverReorderableList` · CG the `FormDragHandle` and the reused "Reorder
{name}" spoken label · CH a tap on the name toggles; the switch is the one
spoken control · CI no confirmation on Reset · CJ a tap into an off card
has no tap · CK the slack rule skips off cards.

**The reviews** (one code reviewer and the design-reviewer, from a
`c83061de` snapshot; nothing severe) and their fate, through three fix
passes (I `35ded696`; II-A the page and II-B the data side, merged with
the gate below):
- CONFIRMED, fixed: `SettingsKeys.reportCards` was missing from the
  backup's settings allowlist, so a reordered or hidden list did not
  survive a round-trip — exported as the other display preferences are;
  an off card's dimmed name fell to 3.26:1 in light (`switchedOffOpacity`
  on a live control, the Alerts hub's token) — the off name is
  `onSurfaceVariant` at full strength, the switch says off; the group came
  apart while a row was dragged (each row painted its own ground, the
  drag gap showed `pageGround`, the foot un-rounded when the last row
  lifted) — the group's `rowGroup` is painted behind the whole list and
  the gap sits after it, so the last row's drag threshold is every row's;
  the dividers sat at the glyph indent 52 where the kit draws 16; no
  level-2 header over the group and the Reset row's group unlabelled —
  one group under "Cards" with Reset as its last row; the intro's column
  did not meet the names'; fix pass I's Move up / Move down wrapper gave
  the handle a merged child node repeating its id — one node per handle;
  flow 34 never checked the off state nor the card gone from the report —
  it toggles Totals off, returns to the report and expects the tile ids
  absent; `decode` read "- goals" as unknown — trimmed after the dash;
  the stale docs on the slack rule and `_heard`; the card-name mapping
  written twice; `ReportShown.cards` optional while every sibling is
  required.
- PLAUSIBLE, fixed: the slack rule still compared the default positions
  — it now compares every shown card's shape in the owner's order (an off
  card never arms; By tag first and its tags changing arms); the Totals
  placeholder frame drew, vanished and returned on open with Totals off —
  the loading frame is not a card the owner can turn off; a failed fold
  re-emitted the last Ready with its old cards — re-carded; the settings
  page's load or write could fail silently on the spinner — caught and
  logged with the defaults as the fall-back; Insights still hid what an
  off Goals or Due soon card "already said" — `ReportInsightFilter.forPage`
  takes the shown cards (the Markdown and the digest keep the defaults:
  they write their own Goals and Due lines).
- Accepted, noted: with Categories off a goal or insight on a category
  past the cap loses the "n more categories" sheet too (CJ: a tap into an
  off card has no tap); a future card lands at the end of a list the
  owner reordered or toggled (CD), and a downgrade drops a future card's
  name on its next write; the handle's spoken label reuses "Reorder
  {name}" with a widened ARB description; "Nach Schlagwort" wraps to two
  lines at de 2.0 on 360 (the row grows with its text, never at runtime);
  the disabled Reset row's 38 % is WCAG's inactive-control exemption.
- **For S9's device pass**: a drag on `emulator-5556` (the seam during the
  drag, the last row's travel, auto-scroll at 2.0, a quick tap on the
  name toggling without a drag), the lifted row's shadow and corners in
  both themes, the ripple on the name and the switch in dark, TalkBack on
  the switch ("<card>, switch, on / off" once), on the handle ("Reorder
  <card>" with Move up / Move down), on the disabled Reset row and its
  snackbar, the off names in sunlight at the system font, de / ro at 200 %
  with Android's non-linear scale.

**Gate (S8).** `dart analyze lib test` clean; `dart format` clean on the
slice's files (the backup round-trip suite carries three pre-existing
unformatted hunks, left as found); `flutter gen-l10n` reproduces the
generated files, `untranslated.txt` empty; the whole suite `+13457 ~12
-4` on 2026-11-05 (the Windows host case and the three real-clock guide
cases); the two Calendar settings goldens where the new row is in view
regenerated. S8 is on `main` as `c09ef7a7` (S8a), `9cfd9b99` (S8b-i),
`c83061de` (S8b-ii with the goldens), `35ded696` (fix pass I) and the fix
passes II (the hash in the hand-off); the docs commit follows with S8c's
six documents.

#### S9 — the device pass (2026-11-05)

**Run by `qa-runner`** on the fleet: `anta_qa_1` (`emulator-5556`) refused
the install — `Requested internal only, but not enough space` with 539 MB
free against a 259 MB debug APK — so the pass ran on `anta_qa_2`
(`emulator-5558`, 3.2 GB free) with the `ed010ff5` build; `anta_qa_1` was
stopped, nothing the owner booted was touched (the guest's storage is the
owner's fleet chore — the 2026-10-31 health-check memory scripts the wipe).
**`qa pass calendar`: 34 of 35 green in 629 s**, the new
`30_category_kind`, `31_category_goal`, `32_report_cards` and
`33_report_year` among them; **`34_report_cards` red twice** at its last
step, `scroll-to id:report-group-categories-qa-cal-strength`: the run
fell before the day's 6 PM Lifting session, so today's occurrence was
pending and Strength sat under Ahead, not Categories (D31) — a flow
assumption bound to the time of day, not an app defect; the step now
scrolls to the footer's Show as list, which is always drawn, and the
comment says why (the re-run's verdict below). **`qa pass alerts`: 5 of 5
green** in 284 s. `qa errors` clean on both. The reports:
`build/qa/pass/calendar_20261105_035327_889_emulator-5558/report.json`
and `alerts_20261105_040533_124_emulator-5558/report.json`; the shots in
`build/qa/shots/`.

**The device buckets** (the three design reviews'): a tag header is one
button node, "tag ana, once, last Monday 2 November", and its tap lists
`report-tag-row-ana-qa-cal-coffee-2026-11-02` ("Coffee with #ana / Mon 2
Nov · 10:30 AM · 45 min") — the dump exposes no expanded flag (the widget
suite asserts it); the When card is one node, "When. Busiest day
Saturday, busiest hour 6:00 PM to 7:00 PM, over 12 timed days.", with no
cell nodes; the Compare with menu at the scroll's end opens with Previous
period checked, Same period last year disabled and "Strength only", ends
at y ≈ 2685 of 2856 and neither scrolls nor flips; on This year the
Strength strip reads "Strength, from October 8 to October 31. By month:
October 7." and the Records rows read "Busiest month: October, 7
events", "Busiest week: from November 2 to November 8, 5 events",
"Longest streak: Lifting session, 6 in a row"; on the Report cards page
the handle is one node "Reorder Goals" and the switch a Switch node
"Goals" (`click, checked`), a 700 ms hold-drag of the Goals handle down
two rows landed it third and a quick tap on a name toggled without a
drag; in de, dark, 2.0 the period menu's eleventh row ends at y = 2244 of
2856, clearing the 3-button bar, and the cards page's rows reflow to a
195 px pitch. **Not reached by the dump or the turn budget**: a Balance
row's node, the handle's Move up / Move down actions (the dump carries no
actions field), mid-drag frames of the group, a visual read of the three
de / dark shots, the When card fully on screen (it sits at the scroll's
end). The tag header's expanded state and the custom actions are pinned
by the widget suites; the rest is for the owner's eye on a device.

**The re-run**: `qa pass calendar --only 34_report_cards -d
emulator-5558` on the repointed flow — 1 of 1 green in 29 s, `qa errors`
clean (`build/qa/pass/calendar_20261105_041506_137_emulator-5558/report.json`);
with the earlier full pass the calendar suite is **35 of 35** and alerts
**5 of 5**. The flow's repoint and this note are the roadmap's last
commit; the status line at the head of this record reads COMMITTED from
it. What stays with the owner: the Firestore rules deploy before a v44+
build syncs from a phone (the S0 note), the guide try-cards suite's clock
pin (§14), `anta_qa_1`'s storage, and the device-only looks the three
design reviews listed (ink, TalkBack phrasing, the drag's seam, the AOSP
200 % curve) — the S5, S6 and S8 notes carry them. *Later on 2026-11-05:*
`anta_qa_1`'s storage is resolved — the fleet spec's
`disk.dataPartition.size` is 16G (`496bf931`; Google's self-updates had
filled the 6 GB) and the guest boots on `emulator-5556` with a 16 GB data
partition, 13 GB free, the app installed; it is the pass device again. The
clock pin and the deploy moved to §13.1 and §14.

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

### 13.1 The closing check (2026-11-05)

Run from the Fable lead session at `94a55179` with the suite alone, the
second line's audit by one read-only Opus 5.5 reviewer, the fixes by one
implementer; one entry per line of §13, in order.

1. **Unprofiled, byte-for-byte** — holds, with the two by-design exceptions
   §1 now names (By tag for a `#` word, When at ten timed samples). The
   goldens, all in the default run: `calendar_report_builder_test.dart`
   "the unprofiled golden (§13)" (no goal, no Due soon row, no insight;
   Balance all `other`), `digest_notification_content_test.dart` "no goal,
   due row or insight: the lines are byte-identical",
   `report_markdown_test.dart` "an unprofiled fold with a #tag adds By tag
   and nothing else", `calendar_report_service_test.dart` "every scoped
   category resolves its profile, unprofiled too" with its month report
   that reads as before S4, and the page suite's real-font pins.
2. **Fixture pairs** — holds at the item level: the 11 measures, the 7 goal
   states and 3 gap states, the 4 due states and the 27 insight rules (ids
   one for one with §6.7) each fire and stay silent in a named case of the
   builder suite; `effective()` is checked for all 21 kinds
   (`category_profile_test.dart` loops `CategoryKinds.all`,
   `category_kinds_test.dart` pins each row to §6.2). Four arms inside
   rules had no firing case — G2's budget arm, D4's Deadline arm, L1's
   Social arm, the Sleep counts-as guard of §6.3 — and T2 had no
   below-threshold negative; the closing commit adds the five ("a counts-as
   never fills a Sleep day", "G2: a budget over in its current month", "D4:
   a Deadline day passed unmarked", "L1: Social events booked a day ahead",
   "T2: a move under 30 % against last year is silent"; the file 216
   cases). The audit also found §6's text behind the code in four places —
   the goal states' `missed` and the at-most / budget arms (§6.6), the
   four due states and the Expiry rule (§6.8), T3 as decision AT (§6.7),
   Timing's one late line (§6.3) — amended in place as *as built* notes.
3. **One-off** — holds: `event_skip_service_test.dart` "cancelling a
   one-off clears its mark", `calendar_bloc_skip_test.dart` "a one-off is
   cancelled and restored through the bloc", the detail sheet's cancel,
   Undo and Done-again cases, `event_presence_service_test.dart` "an
   explicit missed mark on a one-off reads missed", the editor's "a tracked
   one-time event is offered it too" (assume absent),
   `mark_verb_labels_test.dart` for the verb; `shapeOf` pinned in the
   builder and service suites; the presence and skip suites green in the
   gate below.
4. **Cost** — holds on both halves. The pin as built is the timed ratio
   profiled / unprofiled ≤ 1.75 (1.5 → 1.75 in S2b-ii, the compared fold
   being a second fold by design), `benchmark`-tagged, run today: 1.45
   (6.7 ms against 4.6 ms, fastest of 20, this host); the year fixture with
   the previous year folded: 114.6 ms on its first run (the test VM's
   warm-up included), 0.4 ms from the memo. The device half, measured later
   the same day on `anta_qa_1` / `emulator-5556` with a profile build
   (`flutter build apk --profile` with the QA defines and the driver entry
   point, a temporary stopwatch around `_service.report` in the bloc, never
   committed) seeded with the benchmark fixture's twin
   (`tool/qa/perf/gen_perf_calendar.dart` — 50 events over five profiled,
   tagged categories, the dailies' marks, the repeats' skips, the weeklies'
   task lists): the Report's first fold (This month) **2.5 ms**, This year
   with the previous year folded **12.1 ms** — inside one 16.7 ms frame.
5. **Backup and sync** — holds: `backup_service_calendar_round_trip_test.dart`
   "a v7 archive without the key imports with no profiles", "profiles
   round-trip under their own key" (v8), "an archive without categories
   keeps the profiles"; `calendar_category_profiles_merge_test.dart` "a
   newer profile lands every payload column as received", "a newer row
   moves the profile to another category", "another device's profile for
   the same category is kept".
6. **Device pass** — holds: 35 of 35 calendar flows (34 in the full pass,
   flow 34 green on its repointed re-run) and 5 of 5 alerts flows on
   `emulator-5558`, `qa errors` clean — the S9 note; `anta_qa_1` refused
   the install for storage, so `emulator-5556` was not the device.
7. **Rendered and reviewed** — holds as the notes record it: one
   `design-reviewer` pass per visual slice — S3 (the kind picker and the
   goal sheet: the pins hold, four severity-2 findings taken), S4 (18
   real-font renders across the matrix, contrast from tokens, the three
   guideline matchers; measured at 360 / 412, light / dark, en / de / ro;
   no 3–4), S5 (the tags, When, Balance, Compare; no 3–4), S6 (the year
   cards; no 3–4), S8 (the cards page; the off name's 3.26:1 fixed to full
   strength). No colour alone: Due soon's leading glyph (§6.8), the goal
   rows' state glyph beside words, the When card's caption as its one
   semantics node — the heatmap's ramp carries a quantity, not a state, and
   the designer's M gives it no legend. The device-only looks the three
   reviews listed stay with the owner (the S9 note).
8. **Docs** — the report record carried two addenda (S1 / S2a at its
   pending rule; S1 at §4.1 / D31); the categories and settings records
   carried none — the closing commit adds one each (§4.4 the editor sheet;
   §4.7 Calendar settings); `calendar-events` (SKILL "Analytics",
   `references/subsystems.md` "The analytics layer") describes kinds, marks
   on one-offs and the cards; `calendar-ui` has no `references/` directory
   — its SKILL.md file table now lists the analytics widgets;
   `ui-language/references/row-primitives.md` now names `FormMeterRow`'s
   five new members.

**The closing gate** — `dart analyze lib` clean; `dart format` clean on
every analytics file (the repo-wide drift is §14's); the whole suite twice,
alone: `+13461 ~12 -5` both times — the four known red cases (the
Windows-only `host_devices_test` case and §14's three guide clock cases)
and one more, new since S8's gate (`+13457 ~12 -4`):
`backup_service_calendar_round_trip_test.dart` "category alerts import
right after the categories" times out at 30 s under the suite's load with a
Drift isolate channel closed mid-transaction, and is green alone (24 of 24)
and in this session's first full run — §14 carries it. The must-not-change
list re-read against `d8836132..HEAD`: the 30 original flows green in S9,
the presence, skip and `noteId == ''` semantics untouched (the S0 and S1
notes), `gym_notes` unchanged, the v1 and v7 archive cases of the backup
suites green.

**The closing fixes (later on 2026-11-05).** The owner's word was "finish
what is left; make the decisions", so the review's leftovers were taken,
each with one implementer, one code reviewer and — for the one visual
change — the design-reviewer: the repo-wide format (`985b7055` lib and
test, `e4ed8517` tool and test_driver, `95f46b11` the five test if-bodies
the new wrapping exposed), the fleet's 16 GB data partition (`496bf931`;
`anta_qa_1` is the pass device again), the guide suite's clock with the
timeline's own overflow at 2.0 and the contrast sampler behind it
(`1bea5b47`), the backup import's folder batch and the suites' timeouts
(`325a9ae0`), the digest's currency (`e8563019`), the fold measured on the
device (line 4 above; the seed generator `tool/qa/perf/
gen_perf_calendar.dart`). Not taken, by the session's permission layer:
the Firestore deploy and the AVD delete — §14 names the first with its
tested command; the second became moot when the guest booted with the 16 GB
partition. **The second gate**, at `95f46b11`: `dart analyze lib test`
clean, `dart format` clean over lib, test, tool and test_driver, the whole
suite alone `+13476 ~12 -1` in 3:50 — the one red the Windows-only
`host_devices_test` case; the three guide cases and the backup case are
green. **The device pass after it** (`qa-runner`, `anta_qa_1` on
`emulator-5556`, the debug QA build of `95f46b11`): calendar 35 of 35
green in 613 s, alerts 5 of 5 in 298 s, `qa errors` clean after each
(`build/qa/pass/calendar_20261105_121402_969_emulator-5556/report.json`,
`alerts_20261105_122420_553_emulator-5556/report.json`); the day timeline
at text scale 2.0 in en and de
(`build/qa/shots/20261105_122943_506_timeline_2x_en.png`,
`20261105_122946_465_timeline_2x_de.png`): the blocks' titles whole at the
clamped scale, nothing cut or overflowing, and the hour rail's stubs
("7:0", "10:" / "07:", "10:") exactly as §14's bucket describes.

## 14. Deferred

- **The day timeline at large text — the closing design review's
  pre-existing bucket (2026-11-05), for a designer-led slice.** Measured
  with real fonts on `DayTimelineView` while reviewing the block fix: (1)
  the hour rail's labels — a 16 dp row in a 52 dp gutter — are cut: en
  "9:00 AM" wraps to two lines at 1.0 and loses its AM / PM entirely (the
  rail reads 9:00 … 12:00, 1:00 with nothing to tell morning from
  afternoon), de / ro at 1.3 lose the line's descent, and at 2.0 every
  locale shows "09:", "10:" stubs (about 60 % of each digit cut) —
  severity 3 at 2.0, 2 for en at 1.0; (2) a block's tap target is fixed by
  its duration — 69 × 28 for a 30-minute block, neighbours edge to edge —
  below Android's 48 dp (WCAG 2.5.8's 24 passes), the design-practices §2
  conflict that is the owner's call; (3) a missed block's whole-tile
  `Opacity(0.35)` puts its title at 2.1:1 light / 2.8:1 dark
  (`CalendarColors.missedEventAlpha`, an owner token); (4) the stripe
  against its 16 % tint is 1.6:1 light for the holiday colour, and the
  hour gridlines show through the translucent tint; (5) at 1.3 a 43–51
  minute block holds one 21 dp title line over 13–20 dp of blank tint (the
  time row rightly dropped; trimming the line box with a
  `TextHeightBehavior` in both the measure and the drawn text would let it
  back on). Device-only for a `qa-runner`: Android 14+'s non-linear 200 %
  scale on the 30 / 45 / 60 / 120-minute blocks and the rail in en and de;
  TalkBack's phrasing through the blocks at 100 % and 200 %; "Întâlnire"'s
  circumflex at the top of a 28 dp block; the stripes on an OLED panel.
- **The Firestore rules and index deploy — the owner's hands.** S0's
  `firestore.rules` gained the `calendar_category_profiles` collection and
  `firestore.indexes.json` its `data` field override; a v44+ build syncing
  from a phone needs both. **Both were verified LIVE on 2026-11-07** (the
  `cloud.firestore` release of 2026-11-05 carries the collection;
  `firebase firestore:indexes` lists the override), so the step is done —
  the paragraph below records how it got there. On 2026-11-05 the rules suite ran green against the local emulator
  (`test/firestore/rules_test.dart`, 55 cases, `flutter test
  test/firestore/rules_test.dart --tags firestore-rules --run-skipped` with
  `firebase emulators:start --only firestore --project
  alexs-note-tracking-app --config firebase.emulators.json` up), so the
  files are ready; the lead's deploy was refused by the session's
  permission layer as a production deploy. The command, from
  `frontend/anta`, needs no `firebase.json` edit: `firebase deploy --only
  firestore:rules,firestore:indexes --project alexs-note-tracking-app
  --config firebase.emulators.json`.
- **The backup round-trip suite's isolate flake (2026-11-05) — RESOLVED
  the same day (the closing fixes, `325a9ae0`).** The red was a 30 s timeout, not a
  race: the "connection was closed" error came after it, when the teardown
  closed the database under a still-running import. The time went to the
  FOLDER import — the file's groups exported with `folders` / `notes` left
  in, every import appended copies, so the count doubled per case (16,384
  folders by the red case, 12.9 s through `FolderDao.importFolder`, one
  transaction per row on the isolate-backed file database). Fixed three
  ways: `FolderDao.importFolders` batches an archive's folders in one
  transaction (parents resolved through the copies made earlier in the
  list, positions counted per parent from one live-max read, a stamp and
  an outbox entry per row — parity pinned in `sync_outbox_test.dart`,
  including a mutation probe that re-read the max per row and went red);
  the v40, v41, report-cards and v42 groups strip `folders` / `notes` from
  their exports as the profiles group already did (no assertion in them
  reads either); `@Timeout(Duration(minutes: 2))` on the eight suites that
  open the real `AppDatabase.getInstance()`, with the measured reason. The
  file runs in 5 s (37 s before). One behaviour change, accepted: a
  restore that throws partway through the folders now rolls back every
  folder — the import reported failure either way. Left: `createFolder`
  keeps its own copy of the max-position query (`_maxLivePosition` could
  serve it).
- **The fold's frame on a device — RESOLVED 2026-11-05 (§13.1, line 4).**
  Measured on `emulator-5556` in a profile build seeded by
  `tool/qa/perf/gen_perf_calendar.dart` (the benchmark fixture's twin):
  This month 2.5 ms, This year with the previous year folded 12.1 ms, inside
  one frame; R (an isolate fold) stays deferred with no measurement asking
  for it. The recipe, should the fold grow: build the profile APK from a
  worktree with a temporary `Stopwatch` + `debugPrint` around
  `_service.report` in `calendar_report_bloc.dart` (`kotlin.incremental=
  false` in that worktree's `android/gradle.properties` — the Kotlin
  incremental caches would not close under `C:\Temp`), `qa -d <serial>
  install --apk <path>`, `qa relaunch --fresh --seed <the generated json>`,
  the flow 33 steps to This year, `qa log | grep perf`; then `qa fleet
  install --build` puts the debug QA build back.
- **Formatter drift (2026-11-05) — RESOLVED the same day, `985b7055`.**
  `dart format --set-exit-if-changed lib test` on this machine's Flutter
  3.44.2 / Dart 3.12.2 changed 166 files, almost all untouched since
  October (`alert_skip_action.dart`, `sync_bloc.dart`, the DAOs): the tree
  had been formatted by an earlier formatter and the newer one splits
  method chains differently. Formatted in one whitespace-only commit of its
  own, generated files untouched, after the closing commit so no slice's
  diff carries it. Both machines must run the same SDK for the gate's
  `dart format` to hold on the other one.
- **The guide try-cards suite's clock — RESOLVED 2026-11-05 (the closing fixes, `1bea5b47`), and two real defects behind it.** The suite opened every stage but fasting and finding on `DateTime.now`, so three cases drifted with the date. Now one suite clock, `DateTime(2026, 10, 14, 10)` (the finding pin's Wednesday mid-month), `fixedNowFor` sends every topic but fasting to it, `open` defaults to it, and the five cases that read today were fixed under the pins (the kinds demo takes `now`; the fasting skip / force case pages the Dates sheet to each day's month through `FastingScheduleRobot.pickDates`; the setup first-day case reads the strip's own cells). What the drift had hidden: (1) **the calendar's own day timeline overflowed at text scale 2.0** — `_TimelineBlockCard` dropped its time row on a fixed 40 px threshold that ignored the scale, so short blocks overflowed; the block now shows the time row only where both lines fit at the ambient scale and clips a title taller than itself, geometry unchanged, pinned by the new `day_timeline_view_test.dart` (a crowded day at 360 and 412, 2.0: no exception, every block's rect equal to its 1.0 rect); the guide case expects zero exceptions, the tolerated one is gone. (2) **The contrast red was the sampler**, the 2026-11-01 trap proper: "2 events" draws at about 8.6:1, but the stock guideline's most-frequent-colour rule took the anti-aliasing step (the text starts at x = 130.7) for the ink; `GuideTextContrastGuideline` now takes the ground as the most frequent colour of the inflated box and the ink as the most contrasting colour inside the text's own box, inline `WidgetSpan`s excluded — dim text still fails (probed at 1.92:1, beside a black icon too). Accepted: the ro 2.0 360 Overview rows ellipsised at `FormPickerRow`'s two-line clamp, the acceptance the suite already had for the Upcoming body, widened to the Overview view's rows only. Still reading the wall clock without a seam, harmless in the app and the reason a pinned stage cannot pin everything: `CalendarDatePickerSheet`, `CalendarAppearancePreview`, `DayTimelineView._nowMinute`.
- **The digest's currency — RESOLVED 2026-11-05 (the closing fixes, `e8563019`).** `digestNotificationContent` built `ReportLabels(strings)` with no currency, so a money goal in the digest read "1,340" where the page reads "€1,340". Now it takes `currencySymbol` / `currencySuffix` (defaults `''` / `false`, so every other caller and the generic line are byte-identical — pinned); the scheduler reads them once per reconcile through `SettingsService.getMoneyConfig()` beside its week-start read, the same keys and defaults `getCalendarReportSettings` resolves for the page, in its own try that falls back to the defaults (an amount's symbol is no reason to leave the pass unarmed); the content suite pins a prefix goal line ("To do €1,340 (over 1,200)"), a suffix one ("1,340 lei"), a money insight line (M1 "Bills €1,340 due in the next 30 days") and the generic lines unchanged; the scheduler suite pins the pass-through and a re-arm on a currency change. Left, the page's own rule: `ReportLabels` binds a no-break space only next to a digit, so a narrow notification could wrap between "To do" and "€1,340"; and `calendar_guide_try_report.dart` still builds `ReportLabels(l10n)` without a currency (the guide's stage, no money).
- **The slack rule and a saved-view compare** — picking a view adds the view's Totals card within the same look, a shape change `_sameShapes` does not count (Totals is treated as fixed); a reader at the scroll's end who picks a view could see the end spring back (S8 II-B's note).
- **Small leftovers noted by the S7 / S8 reviews** — `_GoalShape.planned => ''` in `_periodFacts` is unreachable (the planned shape returns earlier); the Insights label's presence in `_labelIds` reads the unfiltered page list while the card draws the first `insightsOnPage` (consistent today); with Categories off a goal or insight on a category past the cap loses the "n more categories" sheet too (CJ); a card a later version adds lands at the end of a list the owner reordered or toggled (CD), and a downgrade drops a future card's name on its next write; `_resume`'s null-`_request()` branch has no test (no way found to make the request null after a Ready).
- **The saved view's own column in the shared Markdown** — done in S7 (`### {view}` under Totals); kept here only as the pointer the S5 note gives.
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
- **A Cancelled listing** (AJ, S1) — a cancelled one-off is reachable only
  from its open sheet, the snackbar's Undo and, from S4, the Report's rows;
  an overview filter or a "Cancelled" section would make it findable on
  any day. After the owner has cancelled a few.
- **The v45 sweep's tombstones are not queued for sync** (S1) — v43's
  backfill rule; every device sweeps its own copy on upgrade. If a device
  that never upgraded keeps pushing a stale row, decide then whether the
  sweep should enqueue.
- **Targets on a secondary measure** (AD, S0) — Work's "at least days /
  month" and Trip's "at least trips / year" need a target that names its
  measure; the profile row has no `targetMeasure` column yet.
- **A past span's trailing goal period** (S2a-ii) — a Last-month report's
  last week runs past the month's end and is valued to the end, out of the
  streak; a second scan per target category (the days after the span, to
  the period's end) would make it exact. After the Goals card has been
  looked at.
- **A recurring Expiry beyond the span** (S2a-ii) — the builder never
  scans, so Due soon lists an Expiry only from the span's samples or a
  one-off's start day; a yearly Expiry whose next day lies past a month
  span needs the next-occurrence probe the sampler does not do yet.
- **Money per occurrence** (P, found by the S2a review) — money is read
  once per event at its start day (the ledger's rule: one net per linked
  note), so a monthly-repeat Bill feeds a `budget / month` goal only in its
  first month; a Bill paid monthly is one one-off per payment, each with
  its note, until the ledger can attribute a note's lines to occurrence
  days. The Bill kind's preset stands for that shape.
- **Money after today in a current span** (S2b-ii review) — the measures'
  `spentCents` and a budget goal count a current span's later bills (money
  is read at the event's start day, uncut), while the year's months and
  its Biggest spend record cut at today like every kept-day measure; a
  Categories row can say 510 where October's tile says 10. Align both when
  the money-per-occurrence item above is taken.
- **The view-without-a-view release guard** (S2b-ii) — `compare == view`
  with no `compareView` folds as `previous` in release, behind an assert
  that fires in the request's initializer, so no test can build the case;
  if the request ever grows a non-asserting path, pin it then.
- **Same period last year for a quarter** (AR) — a 91-day leap-year quarter
  shifts 364 days, a 90-day one month to month; AR names only months and
  years. Decide when a quarter preset exists.
- **The year's first partial week** (AX) — belongs to no busiest week while
  the last week counts its December days; symmetric clipping would need the
  previous year's samples. After the Records card has been looked at.
