# Calendar & Events — Feature Reference

A deep, implementation-aware description of the calendar/events subsystem in
`anta`, written as of schema **v14**; the **Addendum (schema
v15–v18)** at the end of this document covers everything added since —
panel modes, the upcoming agenda, the day timeline, `.ics` export, and the
priority-scale inversion. This document focuses on the **events** feature
plus the **public-holiday** subsystem it depends on. Everything below is
grounded in the actual code paths in [lib/](../lib/) — file references are
linked.

> Schema lineage relevant to this subsystem: **v10** created the calendar
> tables; **v11** added the Until bound + time-of-day columns; **v12** added
> `description`; **v13** added holiday profiles; **v14** added the optional
> event ↔ note link (`note_id`); **v15** added the data-driven
> `calendar_categories` table (user-creatable categories); **v16** added
> `color_value` / `tint_icon` / `priority` columns; **v17** added the
> `suppressed` flag on `public_holidays`; **v18** inverted the stored
> priority scale (data-only: `p -> 6 - p`, see the Addendum); **v24** added
> the sparse `calendar_event_occurrences` table (per-occurrence description
> overrides, §6.6). The recurrence **interval** ("every N …") shipped without
> a migration — it rides inside the existing `rule_payload`.

---

## 1. Product purpose

The calendar lives inside an offline-first personal tracker. It is **not** a
general-purpose calendar (no meetings, no invites, no sync). Its purpose is to
let one person:

- **Plan recurring commitments** — schedule repeating sessions (3×/week, every
  workday, weekends only, etc.) so the calendar answers "what should I do
  today?". Training was the original case and is still the densest one.
- **Annotate the year** — mark holidays, fasting periods, birthdays,
  competitions, deload windows, measurements, rest days.
- **Stay context-rich on a single device** — every event is local SQLite,
  with no account, no cloud, and survives device wipe via the JSON backup.

Design principle: the calendar must be useful **the second the user installs
the app**, with zero setup. That is why public holidays are pre-seeded and
why one-time events are the default.

---

## 2. Domain model

### 2.1 [`CalendarEvent`](../lib/models/calendar_event.dart)

The single value object representing an event. It is `Equatable` and
immutable; mutation is done through `copyWith`.

| Field           | Type                       | Notes                                                                                              |
| --------------- | -------------------------- | -------------------------------------------------------------------------------------------------- |
| `id`            | `String`                   | UUID v4, generated client-side. Stable across edits.                                               |
| `title`         | `String`                   | User-entered, ≤ 120 chars (UI-enforced). Trimmed on save.                                          |
| `categoryId`    | `String`                   | Id of a `CalendarCategory` (built-in enum-name like `gym`, or a custom UUID). Resolved to color/icon/label at render time; an unknown id falls back to `other`. |
| `startDate`     | `DateTime` (date-only UTC) | Anchors recurrence math. For one-time events this *is* the event date.                             |
| `rule`          | `RecurrenceRule`           | Sealed hierarchy — see §3.                                                                         |
| `endDate`       | `DateTime?` (date-only UTC) | Optional inclusive upper bound for recurring rules. `null` = "no end".                            |
| `time`          | `EventTime?`               | Optional time-of-day annotation (start minute + optional duration). `null` = all-day.             |
| `description`   | `String?`                  | **v12**. Free-form markdown, length capped by the `eventDescriptionLimit` setting (§6.6). `null`/empty = none. Stored verbatim. |
| `noteId`        | `String?`                  | **v14**. Optional link to a workout note (`notes.id`). Folder resolved at navigation time.        |
| `iconKey`       | `String?`                  | Key into `CalendarIcons.palette`. `null` = use category default.                                  |
| `allDay`        | `bool` (derived)           | Computed as `time == null`. The persisted `all_day` column mirrors this on write only.            |

`CalendarEvent.occursOn(day)` is the central query. It:

1. Normalizes both `startDate` and `day` to date-only UTC.
2. Short-circuits to `false` if `endDate != null && target.isAfter(endDateUtc)`
   (the **Until** bound, applied at the model layer because it is orthogonal to
   the rule shape).
3. Otherwise delegates to `rule.occursOn(target, start)`.

### 2.2 Categories (data-driven since v15)

`CalendarEvent.categoryId` is a `String` referencing a row in the
`calendar_categories` table. Categories are **user-creatable**: built-ins are
seeded with stable ids equal to the historical `CalendarEventCategory` enum
names (`'gym'`, `'cardio'`, …) — which is exactly what `calendar_events.category`
already stored — so the migration needs **no event-data rewrite**. Each
category carries:

- A label — built-ins resolve a localized label by id
  (`CalendarCategories.labelOf` → `l10n.eventCategory*`); custom categories show
  their stored `name` verbatim.
- A color (`color_value`, 32-bit ARGB int) and an icon (`icon_key` into
  `CalendarIcons`).

The `CalendarEventCategory` enum survives only as the **built-in seed catalog**
and the source of localized built-in labels. Runtime lookups go through the
synchronous `CalendarCategories` facade (`byId`/`resolve`/`all`/`labelOf`/
`iconFor`), mirroring the `PublicHolidays` cache so render paths stay O(1) with
no `await`. An unknown id resolves to a fallback (`other`) so deleting a custom
category never corrupts its events; `CategoryService.deleteCategory` also
reassigns those events to `other` in a transaction. Built-ins cannot be
deleted. CRUD lives in `CategoryService`; the UI is `CategoryEditorSheet`
(name + icon + color) and `CalendarCategoriesPage`, plus an inline "Create
category" entry in `CategoryPickerSheet`. The calendar filter is a hidden-id
set (`CalendarPageLoaded.hiddenCategoryIds`), so new categories are visible by
default.

One built-in carries editor behavior: selecting **Birthday**
(`kBirthdayCategoryId`, a cake-iconed yearly category) on a still-one-time
event pre-fills a `YearlyRecurrence` so birthdays repeat every year with no
extra taps. It never overrides a recurrence the user already configured.

---

## 3. Recurrence engine — [`RecurrenceRule`](../lib/models/recurrence_rule.dart)

A sealed-class hierarchy. Each subtype implements a pure
`bool occursOn(DateTime target, DateTime start, {bool retroactive = false})`
where both date arguments are date-only UTC. The table below describes the
default (`retroactive == false`) behaviour; see §3.3 for what the flag lifts.

| Rule                          | Semantics                                                              |
| ----------------------------- | ---------------------------------------------------------------------- |
| `OneTimeRecurrence`           | Occurs iff `target == start`.                                          |
| `DailyRecurrence(interval)`   | Occurs iff `target >= start && (target - start).inDays % interval == 0`. |
| `WeeklyRecurrence(weekdays, interval)` | Occurs iff `target >= start`, `weekdays.contains(target.weekday)`, and `(weekIndex(target) - weekIndex(start)) % interval == 0`. |
| `MonthlyRecurrence(interval)` | Occurs iff `target.day == start.day` and the whole-month delta is a multiple of `interval` (clamped — Feb 30 → no occurrence). |
| `YearlyRecurrence(interval)`  | Occurs iff `target.month == start.month && target.day == start.day` and `(target.year - start.year) % interval == 0` (Feb 29 in non-leap years → skip). |
| `WorkdaysRecurrence`          | Occurs iff `target >= start`, weekday is Mon–Fri, and **not** a public holiday. |
| `WeekendsRecurrence`          | Occurs iff `target >= start` and weekday is Sat/Sun.                    |
| `PublicHolidaysOnlyRecurrence`| Occurs iff `target >= start` and `PublicHolidays.isHoliday(target)`.    |

**Interval ("every N …").** `Daily`, `Weekly`, `Monthly`, and `Yearly` carry
an `interval` field (default `1`, asserted `>= 1`). `interval == 1`
short-circuits to the original behaviour. Weekly interval phase is counted on
a **fixed Monday-aligned grid** (epoch `2000-01-03`, an ISO Monday) rather
than from each event's start, so an A/B "every 2 weeks" split stays
phase-consistent regardless of the anchor's weekday. The fixed cadences
(`Workdays`, `Weekends`, `PublicHolidaysOnly`) have no interval. All math is
O(1) modular arithmetic on date-only UTC values — no DST hazard, no
allocation on the per-day render path.

### 3.1 Persistence shape

Rules serialize as `(ruleKind: String, rulePayload: String?)`. The payload is
a small JSON object that is **only written when it carries something**:

- `weekdays` — populated by `Weekly` (e.g. `{"weekdays":[1,3,5]}`).
- `interval` — written by any periodic rule **only when `> 1`** (e.g.
  `{"interval":2}`, or `{"weekdays":[1,4],"interval":2}` for an A/B split).

Decoding is defensive: a missing/`<1`/malformed `interval` falls back to `1`,
and legacy payloads (which never carried it) decode unchanged. New rule kinds
add a string constant to `CalendarEventService`'s `_kXxx` set and a case to
`_decodeRule` / `_ruleKind`.

The split-column representation (kind + JSON payload) is deliberately more
forgiving than a single JSON blob: corrupt payloads still let the rule kind
through, and adding a new kind — or a new payload field like `interval` — is a
no-migration change.

### 3.2 Until / `endDate` bound

Added in schema v11. Lives **on `CalendarEvent`, not `RecurrenceRule`**, because
it is orthogonal to every rule shape and would otherwise need to be wired into
each subtype's `occursOn`. The wrapper at `CalendarEvent.occursOn` keeps the
rule subclasses pure and easy to test.

UI rules:

- Editor only shows the "Ends on" picker when `_mode == recurring`.
- `firstDate` of the picker is clamped to the event's start date.
- If the user pushes the start past the existing end date, the end date is
  silently dropped (rather than producing an event with zero occurrences).
- `_onSave` writes `effectiveEnd = recurring ? _endDate : null`, so a
  one-time event can never carry a stale end date.

### 3.3 Scope / `retroactive` (schema v19)

By default a rule never fires before its anchor. `CalendarEvent.retroactive`
lifts that guard, so the rule's periodic phase extends backwards through time —
a yearly check-up added today also shows in every previous year. The editor
presents it as two chips under "Occurrences": **From this date on** (default)
vs **Every year** (yearly rules) / **Always** (everything else).

Like `endDate`, the flag lives **on `CalendarEvent`, not the rules** — it is
orthogonal to every rule shape. Unlike `endDate` it cannot be enforced purely
in the wrapper (the guard is inside each rule), so `occursOn` takes it as a
named parameter and each subtype's guard became
`if (!retroactive && day.isBefore(start))` via the shared `_beforeStart`
helper.

**Why the guard and not a back-projected anchor.** The tempting alternative —
leave the rules untouched and hand them a `start` shifted backwards by whole
periods — is wrong. `MonthlyRecurrence` compares `target.day == start.day`, so
reconstructing a day-31 anchor in a 30-day month rolls over into the next month
and corrupts the phase; a Feb-29 anchor rolls to Mar 1 in non-leap years. The
guard has no such failure mode: every phase test is already correct for a
negative delta, because Dart's `%` is Euclidean and `_weekIndex` floors toward
negative infinity by design.

Scope rules and interactions:

- Only rules with `supportsRetroactive == true` are affected. `OneTime` and
  `SpecificDates` have exact membership and return `false` for it, which is
  what makes the editor hide the chips for one-time events.
- `_onSave` writes `recurring && _retroactive`, mirroring the `endDate` guard,
  so a one-time event can never carry a stale `true`.
- `endDate` still clamps the forward side — a retroactive event is unbounded
  only backwards.
- **`.ics` export stays forward-only.** RFC 5545 cannot express occurrences
  before `DTSTART`, so `IcsSerializer._firstOccurrenceOf` deliberately queries
  the rule without the flag rather than emitting something no consumer could
  represent.
- The agenda scans forward from today, so retroactive occurrences never enter
  it; the day cache and `eventLoader` are unaffected (they already call
  `occursOn` per day).
- Backup keeps version 7: the column is additive and older backups import as
  `false`, which is exactly the behaviour those events had.

### 3.4 Occurrence count / `countOccurrences` + `countStyle` (schema v20–v21)

`CalendarEvent.countOccurrences` is a **display-only** flag: each occurrence
of a periodic rule carries a count label derived from the start date, shaped
by `CalendarEvent.countStyle` (`OccurrenceCountStyle`):

The two values differ in **exactly one thing — where counting starts** — and
the UI says so outright ("Count from 1" / "Count from 0"). Everything else
about them follows from that:

- **`numbered`** = count from 1 (default below yearly) — "Day 1" / "Week 3":
  the start day is occurrence one. Numbering is calendar-based, not
  sequence-based: an every-2-days rule reads "Day 1, Day 3, Day 5" and a
  Mon/Wed/Fri weekly rule labels all three sessions of a week "Week N" — the
  training-program reading.
- **`elapsed`** = count from 0 (default for yearly) — "0 years" / "26 years":
  the start day is zero, so a birth-date anchor makes every later occurrence
  the **age**.

Both render on the start day and both suppress only genuinely pre-start
(retroactive) days, so the origin really is the single difference — that
symmetry is what makes the choice explainable in a chip label. The editor's
live example shows the **first three occurrences** under the current
selection ("Day 1 · Day 2 · Day 3" against "0 years · 1 year · 2 years"), so
the origin is visible before saving rather than discovered on the calendar.

The default is **frequency-dependent** (`_defaultCountStyleFor`), and that
matters: a yearly counted event is an anniversary, and counting one from 1 is
off by one against how everyone reads a birthday — someone born in 2000 has
their 27th *occurrence* in 2026 but turns 26, so "Year 27" reads as a bug
even though it counts correctly. The editor tracks whether the user has
actually tapped a chip (`_countStyleTouched`); until they have, the style
re-resolves when the frequency changes — the same "only re-anchor an implicit
default" rule `_pickDate` applies to the weekday set. A saved event that was
already counting is treated as an explicit choice and never rewritten by the
editor; the one-off repair of rows written under the old flat `numbered`
default was done as a **v23 data migration** instead, scoped to yearly rules
(shorter cadences were already correct).

Mechanics:

- The math is `RecurrenceRule.elapsedPeriods(day, start)` — O(1) date
  arithmetic per rule (days diff / Monday-grid week index diff / month diff /
  year diff), `null` for rules without a periodic unit (one-time, specific
  dates, workdays, weekends, holidays-only). It never touches `occursOn`.
- Formatting is `RecurrenceFormatter.countLabel(event, day, l10n)` — the
  single entry point both surfaces use; it owns the flag check, the style
  switch and the ≤ 0 suppression (`eventElapsedDays/Weeks/Months/Years` ICU
  plurals, `eventNumberedDays/Weeks/Months/Years` unit labels).
- Surfaces: the count label **leads** the day-panel/agenda row subtitle
  ("Week 3 · Weekly · All day" — the count is the headline fact and trailing
  segments ellipsize first), and the detail sheet's next-occurrence chips
  append it ("Sat, May 10 · 30 years").
- Editor: a "Count occurrences" switch shown only for the periodic kinds
  (the `_kindSupportsInterval` set); when on, two style chips appear with a
  live three-sample example line ("Day 1 · Day 2 · Day 3") rendered from
  the same l10n keys, so the choice explains itself. `_onSave` writes
  `recurring && _kindSupportsInterval && _countOccurrences`, mirroring the
  `retroactive` guard. Picking the birthday built-in on a still-one-time
  event pre-fills counting **with the elapsed style** together with the
  yearly rule.
- `.ics` export ignores both fields (RFC 5545 has no equivalent) and backup
  keeps version 7 — additive columns; older backups import as off/numbered.
- v21 is a separate migration from v20 only because v20 had already run on
  devices when the style choice was added; **v23** likewise repairs data v21
  had already written (`count_occurrences = 1 AND rule_kind = 'yearly' AND
  count_style = 'numbered'` → `elapsed`). Both are cases of the same rule:
  never edit a migration that has shipped, add the next one.

---

## 4. Public-holiday subsystem

The calendar engine consults
[`PublicHolidays.isHoliday(day)`](../lib/constants/public_holidays.dart) for
two recurrence rules (`WorkdaysRecurrence`, `PublicHolidaysOnlyRecurrence`)
and also for visual rendering on calendar tiles.

### 4.1 Built-ins are computed, not stored (schema v22)

A profile's holidays are a **pure function of (profile, year)** — that is
what [`HolidaySeeds.forYear`](../lib/constants/public_holidays.dart) is, and
it always was; until v22 the app merely *ran* that function ahead of time and
persisted the results as rows for a rolling 6-year window.

Persisting derived data bought nothing and cost correctness: any year outside
the window had no movable feasts at all (Good Friday in 1991 or 2099 simply
did not exist), and a profile switch had to delete and re-seed rows to stay
honest. So v22 deleted the seeding pass. `PublicHolidays` now computes a
year on first touch and **memoizes** it (bounded at 12 years, cleared
wholesale — rebuilding a year costs microseconds, so an LRU would be more
bookkeeping than it saves), exactly the shape `FastingCalendar` already uses.

Every year in [`CalendarBounds`](../lib/constants/calendar_bounds.dart)
(1900–2100) now resolves fully, Easter-derived feasts included, at a cost of
one Easter computus plus ~15 date constructions per year touched — a month
view touches at most two. There is **no window setting to tune and no
performance cliff to warn about**; both would be configuration over a
non-problem.

Resolution order in `PublicHolidays.holidayOn`:

1. **Overrides** — the user's custom holidays (and any legacy stored
   built-in row) win, so a custom entry can sit on a date the profile
   already claims.
2. **Computed** — `HolidaySeeds.forYear(profile, year)`, unless the date +
   holiday name appears in the suppression set.
3. **Fixed-date fallback** — only while the service has not initialized
   (`_profile == null`), so tests and the first frame still render something
   sensible. Movable feasts are unavailable in that state by nature.

### 4.2 Legislative accuracy: validity years and substitute days

Holidays are law, not arithmetic, so a pure generator needs two corrections
that a naive "compute the date every year" pass gets wrong. Both live inside
`HolidaySeeds`; neither needs a schema change, a setting, or a network call.

**Validity years.** Each holiday created or moved by legislation carries an
inline `if (year >= NNNN)` guard, so browsing a past year does not show an
anachronism. Without them, extending the range to 1900 (§6.5) showed
Juneteenth in 1991 and German Unity Day in 1980. Covered: US (MLK 1986,
Uniform Monday Holiday Act 1971 for Presidents'/Memorial/Columbus,
Thanksgiving 1942, Veterans Day 1954, Juneteenth 2021), UK (New Year 1974,
Early May 1978, spring/summer bank holidays 1971), Germany (Unity Day 1990),
Romania (National Day 1990, Pentecost/Assumption 2008, St Andrew 2012,
Unification Day 2016, Children's Day 2017, Good Friday 2018). The guard sits
next to the date it governs so each region's history reads in one place.

This is a **best-effort curated set covering the clear cases**, not an
exhaustive legislative history — the 1971–1977 US move of Veterans Day to
October is knowingly not modelled, for instance. `generic` and `europe` are
deliberately unguarded: they are curated convenience sets rather than
jurisdictions, so dating them by statute would be false precision.

**Substitute days.** A holiday falling on a weekend earns a statutory day off
elsewhere, and the two rules differ by country, so `forYear` dispatches per
profile after building the base set:

- **UK** — moves *forward* to the next weekday that is not already a bank
  holiday. Order matters: Christmas takes the first free weekday and Boxing
  Day the next, which is what produces the Mon/Tue pair when Christmas falls
  on a Saturday (2021 → 27th and 28th) and the single Tuesday when it falls
  on a Sunday (2022 → 27th, because Monday is Boxing Day itself).
- **US** — Saturday shifts *back* to the Friday before, Sunday *forward* to
  the Monday after. A Saturday New Year is observed on 31 December of the
  **previous** year, so that date is emitted into the prior year's map.
- **Germany, Romania, generic, europe** — no statutory substitution; the day
  is simply lost when it lands on a weekend.

Both the real date and the substitute are emitted, because you want to see
Christmas on Christmas *and* see which weekday is actually off. They are
distinguished by `HolidayOccurrence.observed` → `PublicHolidayInfo.observed`,
which `PublicHolidays.labelOf` renders through the `publicHolidayObserved`
ARB key ("Christmas Day (observed)") — otherwise two identical rows in one
week would be unexplainable. Suppression keys on `(date, name_key)`, so a
substitute can be removed independently of the holiday itself.

### 4.3 The table holds only user deltas

`public_holidays` now stores exclusively what **cannot** be recomputed:

- **Custom holidays** — `name_key = 'custom'` (the `kCustomPublicHolidayKey`
  sentinel) with a non-null `custom_label` and `profile = 'custom'`, so they
  survive every profile switch. Indistinguishable from built-ins for
  recurrence and rendering.
- **Suppressions** — `suppressed = 1` rows (v17), the only durable record
  that a built-in was removed from one specific date.

The v22 migration deletes every other row (`suppressed = 0 AND name_key !=
'custom'`), which is lossless because each one is reproducible. `importData`
applies the same filter: plain built-in rows in an older backup are skipped
rather than restored, since importing them would pin a stale copy of some
other profile's holidays over the computed set. Backup stays **version 7** —
the export shape is unchanged, and a new backup restored into an older build
simply gets re-seeded by that build's seeder.

### 4.4 Removing and restoring a built-in

Removing a holiday (day-summary panel delete action →
`PublicHolidayService.removeOn`) hard-deletes custom rows and **writes a
suppression row** for the computed built-in on that date — with built-ins no
longer stored, that row is the only thing that can persist "not on this
date"; without it the next resolve would hand the holiday straight back.

Restoring (`restoreSuppressed`, backing the "Removed holidays" list in
Calendar Settings via `RemovedHolidaysSheet`, plus the day panel's Undo
snackbar) **deletes** the suppression row rather than clearing its flag: the
holiday itself is computed, so dropping the marker is what brings it back,
and clearing the flag would leave a stored duplicate of derived data behind.

Suppressions are keyed per `(date, name_key)`, so restoring one holiday on a
day that carries two does not resurrect the other. A profile switch deletes
the previous profile's rows including its suppressions — a day removed from
the German set says nothing about the Romanian one.

### 4.5 Religious fasting engine

[`FastingCalendar`](../lib/constants/fasting_calendar.dart) computes fasting
days for four traditions — **Orthodox, Catholic, Muslim, Jewish** — enabled
per user via toggles in Calendar Settings (`SettingsService
.getFastingTraditions`, CSV under `calendar_fasting_traditions`, empty = off,
unknown names dropped for forward compat, cleared by reset-to-defaults).

**Nothing is persisted beyond that setting.** Fasts are fully deterministic
from (year, tradition), so the engine mirrors `PublicHolidays`: a static
sync facade, `configure(traditions)` called from the calendar page's
settings load (no-op when unchanged), then `on(day)` / `isFastingDay(day)`
during builds. Years build lazily (O(365) per tradition, bounded cache of
12 year-maps) and every later lookup is an O(1) map hit — nothing heavy
ever runs inside a cell build or the `eventLoader` path.

The raw date math lives in
[`LiturgicalComputus`](../lib/utils/liturgical_computus.dart) — deliberately
**dependency-free** (no Flutter imports) so a plain `dart run` script can
assert it against externally known dates (it was validated against
2000–2038 Easters both computus, Ramadan 1445–1447, and the Hebrew calendar
anchors RH 5761/5784–5786, Yom Kippur, Pesach, the postponed Tzom Gedaliah
5785, 10 Tevet, Ta'anit Esther). It provides: Gregorian Easter
(Meeus/Anonymous), Orthodox Easter (Meeus Julian + century-aware Julian→
Gregorian offset, shared with `PublicHolidayService` which now delegates to
it), Fliegel–Van Flandern JDN↔Gregorian, the tabular ("Kuwaiti") Islamic
calendar (civil epoch JDN 1948440, ±1 day vs moon sighting — the standard
software caveat), and the full arithmetic Hebrew calendar (molad + all
dechiyot; every public fast is a fixed offset from Rosh Hashanah or from
Pesach, which is always RH(next year) − 163 because Nisan–Elul never vary).

Per-day output is a `FastingInfo(tradition, period, regime)`:

- **Periods** name the fast (Great Lent, Nativity Fast, Ramadan, Yom
  Kippur, …) — localized via sealed switch (`periodNameOf`), never `byKey`.
- **Regimes** are the day's rule: `strict` (post aspru), `oil` (dezlegare la
  vin și ulei), `fish`, `dairy` (Cheesefare), `penitential` (Catholic
  Lent/Advent weekdays), `daylight` (dawn-to-sunset: Ramadan, Jewish minor
  fasts), `full` (Yom Kippur, Tisha B'Av).
- Orthodox rules follow the common printed Romanian calendar: the four
  great fasts with their weekday patterns (Mon/Wed/Fri strict, Tue/Thu
  wine & oil, weekend dispensations), fish on Annunciation/Palm Sunday/
  Transfiguration/Entry into the Temple/St John, first week and Holy Week
  strict, the Dec 20–24 tightening, the three strict single days (Jan 5,
  Aug 29, Sep 14), Cheesefare Wed/Fri as dairy, year-round Wed/Fri fast
  suppressed in the harți weeks (Christmastide, Publican & Pharisee week,
  Bright Week, Trinity week). Apostles' Fast starts Pascha+57 and can
  vanish entirely in late-Pascha years.
- Jewish fasts carry their Shabbat deferrals (17 Tammuz / Tisha B'Av /
  Gedaliah → Sunday, Ta'anit Esther → Thursday).

**Display is configured per tradition**, not globally — Orthodox can tint
the cell in violet while Ramadan draws a green bar. The config model is
[`FastingAppearance`](../lib/models/fasting_appearance.dart), which owns
`FastingTradition`, `FastingDisplayStyle`, `FastingRowPlacement` and
`FastingTraditionStyle` (the same shape as `CalendarAppearance`: enums with
forward-compatible `fromName`, `Equatable`, `copyWith` with `clearX` flags
for the nullable overrides). Each tradition carries:

| Field | Meaning |
| --- | --- |
| `style` | `tint` (default) / `bar` / `strong` / `none` |
| `colorValue` | ARGB override, null = the shared `CalendarColors.fasting` violet |
| `iconKey` | `CalendarIcons` key, null = the tradition's built-in icon |
| `placement` | `first` / `beforeHolidays` / `afterHolidays` (default) / `last` |
| `titleOverride` | replaces the computed period name in the row, null = keep it |
| `description` | extra markdown line under the regime, null = none |

`titleOverride` replaces the period name **outright** (someone who types
"Post" wants it on every Orthodox day, not the specific fast's name) and is
also what the day bar's `semanticLabel` announces. `description` is handed to
`DaySummaryEntry.description`, so it renders through the same clamped
`MarkdownInlineText` path event descriptions use and inherits their rules for
free — money disabled, no tap recognizers, two lines with an ellipsis. Both
text fields normalize blank input to null inside `copyWith`, so clearing a
field *is* the reset and no `clearX` flag is needed for them.

`FastingRowPlacement` exists so the UI never exposes a raw priority — the
enum carries the `DaySummaryEntry.priority` / `DayBar.priority` it maps to
(10 / 120 / 160 / 260), keeping the band layout (events 0–99, holiday 150,
weekend 250) an implementation detail.

How each style reaches the screen:

- `tint` / `strong` — resolved by **`FastingCalendar.cellStyleFor(day)`**
  into a `FastingCellStyle(tint, numberColor)` and handed to
  `CalendarDayCell` as two plain nullable `Color`s. The cell knows nothing
  about traditions or styles, and the resolution (highest placement wins per
  slot; both slots can be filled by different traditions) lives in one
  place. Memoized in a bounded 512-entry day map so `defaultBuilder` never
  re-derives colours for ~42 cells a frame.
- `bar` — `FastingDayBarProvider` emits **one bar per tradition** that asked
  for it, in that tradition's colour at its placement. The check is per
  tradition, not a global gate.
- the day panel always gets one `FastingSummaryProvider` row per active
  tradition — configured icon, colour and placement — titled with the period
  and subtitled with the regime ("Postul Crăciunului · Dezlegare la pește").

Appearance is **display-only**: `configure()` drops just the cheap per-day
cell-style memo when it changes and never touches the computed year maps,
which only invalidate when traditions or the Orthodox scope options move.

Persistence is one key, `calendar_fasting_appearance`, holding a **JSON**
object keyed by tradition name. It started as a delimited
`tradition:style|argb|icon|placement;…` record, which was safe only while
every field was an enum name, an integer or an icon key — the moment free
text (title, description) entered, any separator the user typed would have
corrupted the row, and hand-rolled escaping is exactly the thing that
silently eats one person's data. `decode` still reads the delimited form
(detected by the leading `{`) so nothing written before the switch is lost.

Whatever the shape: every field degrades to its default independently,
unknown traditions are dropped, malformed JSON yields defaults instead of
throwing (a corrupt settings row must never keep the calendar from opening),
and when the key is absent the retired global `calendar_fasting_style` seeds
every tradition. Round-trip (including text carrying `;` `:` `|` `"` `\` and
newlines), legacy decoding, migration and junk-degradation were all verified
with a throwaway harness.

**Editing UX**: each enabled tradition gets an indented "Appearance" row
under its switch, summarising `style · placement`, opening
[`FastingStyleSheet`](../lib/widgets/fasting_style_sheet.dart). The sheet
applies **live** via `onChanged` (the settings page persists on every tap)
rather than gating behind Save — it is a settings surface, so dismissing
must never mean "discard". It leads with a preview showing both halves at
once: a sample day cell carrying the grid treatment next to the day-panel
row it produces, title/description included. Colour and icon reuse the app's
existing `ColorWheelDialog` / `IconPickerSheet`; the preview resolves its
icon from the sheet's own draft, because the engine only learns about a
change after the page has persisted and reconfigured it, and it renders the
description as plain text — pulling the markdown builder into a settings
sheet to show two lines is not worth the dependency.

The two text fields debounce their `onChanged` by 400 ms (discrete controls
still write through immediately) so typing a description does not queue one
settings write per keystroke, and the pending write is flushed in `dispose`
— leaving inside the debounce window must not lose the last keystrokes. The
same shape as the agenda search field in `CalendarBottomPanel`.

**Orthodox scope option** (shown only while Orthodox is enabled):

- *Multi-day fasts* (`calendar_fasting_orthodox_great_fasts`, default on) —
  turning it off drops the four great fasts, the strict single days and
  Cheesefare, leaving only the weekly rule, which then applies year-round.

**The personal schedule** ("My practice", `FastingScheduleSheet`, shown while
**any** tradition is enabled) is one `FastingSchedule` persisted as JSON under
`calendar_fasting_schedule`:

- *Weekdays* — default Wednesday+Friday, but any set works (some keep only
  Wednesday, some add Monday) and clearing them all disables the weekly rule.
  The harți (fast-free) weeks still suppress whatever days are chosen.
- *Weekday scope* (2026-08-22) — the exact mirror of the month scope.
  `weeklyOnly` (default, and everything that shipped before it) gates only the
  year-round weekly rule, so Great Lent keeps its Thursdays; `allFasts` gates
  every mark, so a Wed/Fri practice keeps Great Lent on Wednesdays and Fridays
  only. Applied in the same `_buildYear` `merge` closure beside the month
  probe, one set probe per produced entry. Subtract-only like everything else
  here: it removes days, never invents one, and `forceDates` still wins on a
  weekday that is turned off.
- *Months* — which months the practice is kept in, default all twelve.
- *Month scope* — `weeklyOnly` (default) gates only the weekly rule, so a
  great fast still shows in a month the weekly fast is not kept in;
  `allFasts` gates every mark, other traditions included. Applied inside
  `_buildYear`'s `merge` closure, so it costs one set probe per produced
  entry and never a second traversal.
- *Exception dates* — `skipDates` (never marked) and `forceDates` (always
  marked, emitted as `FastingPeriod.personalFast` attributed to the first
  enabled tradition). Applied last, in `_applyExceptions`, by walking the
  date sets rather than the year map; each is capped at 200 and the two are
  kept disjoint, force winning.

The schedule may **subtract** from a tradition's own weekly rule but never
**invent** days it does not have: dropping Friday silences the Catholic
year-round abstinence, while adding Monday must not fabricate a Catholic
Monday abstinence. Lent/Advent Fridays and Good Friday are seasonal, not
weekly, and survive either way.

Migration: an absent `calendar_fasting_schedule` falls back to the retired
`calendar_fasting_weekdays` CSV, which is read but never written again. That
CSV's **absent** (traditional default) vs **empty string** (deliberate "none")
distinction is resolved in `SettingsService.getFastingSchedule`, which passes
the raw value — `''` included — as `legacyWeekdayCsv`; `FastingSchedule.decode`
treats `null` and `''` differently and must keep doing so.

---

## 5. Persistence layer

### 5.1 Schema (v14)

#### [`CalendarEvents`](../lib/database/tables/calendar_events_table.dart)

| Column              | Type     | Null | Notes                                                                |
| ------------------- | -------- | ---- | -------------------------------------------------------------------- |
| `id`                | TEXT     | PK   | UUID v4.                                                             |
| `title`             | TEXT     | NN   | ≤ 120 chars enforced in UI.                                          |
| `category`          | TEXT     | NN   | Stores enum `name`, decoded with fallback to `other`.                |
| `start_date`        | INTEGER  | NN   | Epoch ms. Date-only UTC by convention.                               |
| `all_day`           | INTEGER  | NN   | Boolean. Write-time mirror of `time == null`; ignored on read.       |
| `icon_key`          | TEXT     | YES  | Optional icon override.                                              |
| `rule_kind`         | TEXT     | NN   | `oneTime` / `daily` / `weekly` / `monthly` / `yearly` / `workdays` / `weekends` / `holidaysOnly`. |
| `rule_payload`      | TEXT     | YES  | JSON; carries `weekdays` (weekly) and/or `interval` (when > 1).      |
| `end_date`          | INTEGER  | YES  | **v11**. Inclusive Until bound (epoch ms).                           |
| `start_minute`      | INTEGER  | YES  | **v11**. Time-of-day start (minutes since local midnight).           |
| `duration_minutes`  | INTEGER  | YES  | **v11**. Optional event duration in minutes.                         |
| `description`       | TEXT     | YES  | **v12**. Free-form markdown notes; length is a UI setting, not a schema constraint (§6.6). Acts as the **template** when per-occurrence descriptions are on. |
| `note_id`           | TEXT     | YES  | **v14**. Optional link to a workout note (`notes.id`).               |
| `retroactive`       | INTEGER  | NN   | **v19**. Boolean, default 0. Lifts the rule's pre-start guard (§3.3).|
| `count_occurrences` | INTEGER  | NN   | **v20**. Boolean, default 0. Occurrences carry a count label (§3.4). |
| `count_style`       | TEXT     | NN   | **v21**. `numbered` / `elapsed` — label shape; column default `numbered`, editor default is frequency-dependent (§3.4). |
| `created_at`        | INTEGER  | NN   | Epoch ms (UTC).                                                      |
| `updated_at`        | INTEGER  | NN   | Epoch ms (UTC).                                                      |

#### [`PublicHolidaysTable`](../lib/database/tables/public_holidays_table.dart)

| Column         | Type     | Null | Notes                                                  |
| -------------- | -------- | ---- | ------------------------------------------------------ |
| `date`         | INTEGER  | PK   | Epoch ms at UTC midnight. Composite PK with `name_key`. |
| `name_key`     | TEXT     | PK   | Built-in enum name or `custom`.                        |
| `profile`      | TEXT     | NN   | **v13**. Owning `HolidayProfile.name`, or `custom`.    |
| `custom_label` | TEXT     | YES  | Required iff `name_key == 'custom'`.                   |
| `suppressed`   | INTEGER  | NN   | **v17**. Boolean; marks a built-in removed from a date. |

Since **v22** the table holds only user deltas — custom rows and
suppressions (§4.3). Built-ins are computed, never stored.

### 5.2 Migrations

[`DatabaseMigrations`](../lib/database/migrations/database_migrations.dart)
follows the project rule that migration SQL is **frozen at the migration's
moment in time** — never relies on the live Drift declaration. This avoids
regressions when columns are added later.

Calendar-relevant steps:

- **v9 → v10**: Creates `calendar_events` and `public_holidays` with raw
  `CREATE TABLE` and adds the calendar indexes.
- **v10 → v11**: Adds three nullable columns
  (`end_date`, `start_minute`, `duration_minutes`) via `ALTER TABLE … ADD
  COLUMN`. Idempotent: introspects `PRAGMA table_info(calendar_events)` and
  skips any column already present.
- **v11 → v12**: Adds the nullable `description` column (same idempotent
  `PRAGMA table_info` guard).
- **v12 → v13**: Holiday-profile support (rebuilds `public_holidays`); not a
  `calendar_events` change.
- **v13 → v14**: Adds the nullable `note_id` column (same idempotent guard).
  `NULL` preserves the historical "no linked note" semantics, so existing
  rows are unchanged.

Fresh installs use `m.createAll()` from the live Drift declaration, which
already includes every column above — no migration runs. The recurrence
`interval` needed **no migration**: it is encoded inside the existing
`rule_payload` JSON.

### 5.3 [`CalendarEventDao`](../lib/database/daos/calendar_event_dao.dart)

Thin Drift DAO: `getAll`, `upsert`, `deleteById`, `deleteAll`. No
recurrence-aware queries — recurrence math is always done in Dart against
the in-memory cache.

### 5.4 [`CalendarEventService`](../lib/services/calendar_event_service.dart)

Singleton (registered with `DatabaseLifecycle` so it resets when the user
switches DBs). Responsibilities:

- **Load on init** — pulls all rows once into `List<CalendarEvent> _cache`.
- **Synchronous reads** — `events` getter returns the unmodifiable cache so
  `CalendarBloc.eventsForDay` can expand recurrences with no async hops. The
  bloc additionally **memoizes** the per-day result (see §6.1), so each
  distinct day is scanned at most once per event-set / filter generation.
- **Mutations** — `upsert` and `deleteById` go through the DAO and then
  patch the in-memory cache so the calendar UI sees the change instantly.
- **Date-only normalization** — `startDate` and `endDate` are forced through
  `_dateOnlyUtc` on every write so equality / ordering is timezone-stable.
- **Backup parity** — `exportData()` and `importData()` mirror the row shape
  for inclusion in the app-global backup (see §7).
- **Rule serialization** — kind/payload codec, isolated in this service so
  the rest of the app stays in domain types.

### 5.5 [`PublicHolidayService`](../lib/services/public_holiday_service.dart)

Companion singleton:

- **Seeds** the 6-year window on first launch and on every subsequent launch
  via `insertIfMissing`.
- **Publishes** a `Map<DateTime, PublicHolidayInfo>` to
  `PublicHolidays._cache` plus the inclusive `(minYear, maxYear)` window.
- **Mutates** via `addCustom` (writes `name_key=custom` rows) and
  `removeOn(date)` (suppresses any holiday on that day).
- **Backup parity** — `exportData()` / `importData()` round-trip every row
  shape verbatim (see §7).

---

## 6. UI surfaces

### 6.1 Calendar page

Backed by `table_calendar 3.2.0`. Tile rendering consults
`PublicHolidays.holidayOn` for holiday badges and
`CalendarBloc.eventsForDay(day)` to draw event chips.
`CalendarBloc.eventsForDay` is synchronous and **memoized**: the first call
for a day iterates the cached event list and calls `event.occursOn(day)`,
then stores the result in a bounded per-day map (`_dayCache`, cap 512
entries — cleared wholesale on overflow). The cache is invalidated **only**
by the handlers that change the inputs to the expansion —
`LoadCalendarEvents`, `CreateCalendarEvent`, `UpdateCalendarEvent`,
`DeleteCalendarEvent`, and `ChangeHiddenCategories`. Day-selection, focus,
and format changes deliberately keep the cache warm, so the common case
(tapping around a month, toggling month/2-week/week) is an O(1) map lookup
per cell instead of an O(N) recurrence scan. The same cached path also feeds
the bottom day-summary panel, so there is a single recurrence-expansion code
path (the old uncached `CalendarPageLoaded.selectedEvents` getter was
removed).

**Header** (`headerTitleBuilder`, chevrons still table_calendar's). Three
controls share one row between the chevrons:

- the **month title opens
  [`MonthYearPickerSheet`](../lib/widgets/month_year_picker_sheet.dart)** —
  see below. Its wheels carry a day too, so a pick is a full date: the page
  dispatches `SelectCalendarDay` (focus **and** select), moving the panel
  below with it, and opens the sheet on the current `selectedDay`.
- the **Today button** stays the original plain, unfilled icon button,
  positioned to the left of the title.
- the **month net** (`Δ`, money-ledger sum for the focused month) sits after
  the title. Today, title, and net form one cluster centered as a block via
  `mainAxisAlignment.center` — the title is not dead-center of the full
  header, matching the pre-existing layout feel.

The default chevron padding/margin is overridden to 40dp touch targets
(table_calendar's default claims 64dp each, a third of a phone's width for
two arrows the user can also swipe). Only the title text is `Flexible` with
an ellipsis under pressure — the Today button and the net stay at their
intrinsic size.

#### [`MonthYearPickerSheet`](../lib/widgets/month_year_picker_sheet.dart)

A full-date picker for jumping the calendar — distinct from
`CalendarDatePickerSheet` (§6.5), which is the grid used for event date entry.
One screen, no drill-down (a day → month → year drill was built here once and
rejected outright), with two input modes behind a toggle pinned top-right:

- **Wheels** (default): three `ListWheelScrollView`s side by side — day |
  month | year (the dd/mm/yyyy order, so both modes read the same way) — that
  scroll up/down independently, so a flick crosses days, months or decades
  without leaving the screen. `Apply` commits the centred rows. The **day
  wheel is bounded by the month** (`_daysInMonth`, `day 0` of next month —
  leap-aware); when the month or year moves the day is clamped back inside it
  (`_clampDayToMonth`: Jan 31 → Feb → 28/29) and the day wheel is realigned by
  a post-frame `jumpToItem`, because its child count shrinks in the same
  build. Kept intentionally quiet after an over-designed version was rejected:
  one faint `surfaceContainerHighest` band marks the selected row, a
  `ShaderMask` fades the top/bottom edges so it reads as a wheel and not a
  clipped list, and the only accent is the selected label's colour.
- **Typed**: a single text field, canonical form `dd/mm/yyyy` (the hint), with
  forgiving parsing (`_parse`). Separators and order are free-form:
  `15/08/2026`, `15.8.2026`, `2026-08-15` all give the 15th (a 4-digit year on
  either end fixes d/m/Y vs Y/m/d — the month is the middle number). Shorter
  forms work too: `08/2026` keeps the wheel's day, `15 august 2026` /
  `15 aug` read the day next to a named month, a bare `2026` keeps month+day,
  a bare number `>12` is taken as a day. Impossible days (`31/02`) clamp to
  the month length. Unparseable input and out-of-range years surface as field
  errors instead of silently doing nothing.

`Apply` commits either mode; `Today` moves the wheels to the current date
(animated) rather than closing, so it composes with a manual tweak. The
mode-toggle icon shows a keyboard in wheel mode and `calendar_month` in typed
mode (a `filledTonal` button — the earlier `view_day` icon was rejected).
Month names come from `intl` + `toBeginningOfSentenceCase` (locales like
Romanian spell them lowercase), never an ARB matrix. The mode switch is
wrapped in `AnimatedSize`, because typed mode is shorter than the wheels and a
fixed height would overflow with the keyboard up; the keyboard inset is read
from the **sheet's** context, not the caller's, since only that one rebuilds
when the keyboard opens.

### 6.2 Day list

Tapping a date opens a list of that day's events. Each tile is colored by
category, optionally overridden with a custom icon. When fasting traditions
are enabled (§4.4) the list also carries one violet row per tradition naming
the fast and the day's rule. The whole bottom panel sits inside a
`SafeArea(top: false)` so its last rows clear the device's system
navigation bar instead of rendering underneath it.

Rows carry the event's **description** below the scheduling line, rendered as
markdown and clamped to two lines with an ellipsis (`MarkdownInlineText`, §6.6),
plus a small notes icon next to the title when one exists. The agenda inherits
this by construction — both surfaces render `EventSummaryProvider` entries, and
that sharing is deliberate.

Tapping a row — in the day panel **or** the timeline, which render the same
day and so must agree — opens the **read-only**
[`EventDetailSheet`](../lib/widgets/event_detail_sheet.dart):
title, category, date/time, recurrence (with scope), priority, the fully
rendered description, the linked-note button, and the next 5 occurrences.
Editing is one button away (`EventDetailAction.edit` → the editor sheet);
opening the linked note routes through the page's existing resolver.
"Read-only" has one exception: description checkboxes on **single-occurrence**
events toggle in place and write back through `onEventChanged` (§6.6).

### 6.3 [`EventEditorSheet`](../lib/widgets/event_editor_sheet.dart)

A bottom-sheet form (`heightFactor: 0.92`), organized **category-first**
into three `_GroupHeader` zones (accent-colored label + divider; the
per-field `_SectionLabel`s stay inside each zone):

**What** (`eventSectionWhat`):
1. **Type** — category picker (`CategoryPickerSheet`), deliberately the
   very first control: picking a category tailors the rest (the birthday
   built-in pre-fills yearly recurrence). This is also why the title field
   lost its autofocus — a keyboard popping open would bury the tile the
   flow starts with.
2. **Title** — single-line `TextField`, `maxLength: 120`.

**When** (`eventSectionWhen`):
3. **Repeat mode** — segmented control `oneTime` / `recurring`, leading the
   zone: it decides everything the zone renders below it (date chips vs
   start date + recurrence config), so it sits above what it switches — in
   its old spot below the date and time sections, toggling it mutated
   content *above* the control, which read as if nothing happened.
4. **Date(s)** — `CalendarDatePickerSheet` (§6.5), bounded by
   `CalendarBounds`: fixed wide bounds, **not** the old ±20-year
   slide around the current date, because a birthday's start is the birth
   year and the occurrence-count age (§3.4) depends on it being real. The
   Until picker keeps the start date as its lower bound. One-time
   events edit their whole date set in one multi-select pass; recurring
   events pick a start date, then frequency chips, interval stepper, weekly
   weekday chips, occurrence-scope chips (§3.3), the count-occurrences
   switch (§3.4, periodic kinds only), and the optional Until date — one
   contiguous recurrence block under the toggle.
5. **Time** — all-day switch, start/end pickers, closing the zone (shared
   by both modes).

**Details** (`eventSectionDetails`):
6. **Description** — markdown source in a real `ModernEditorWrapper` /
   re_editor surface, live-rendered Obsidian-style by the note editor's own
   `MarkdownEditorSpanBuilder` (see §6.6), with a `count / limit` counter
   above it. The eye/pencil preview toggle survives only for users who turned
   live rendering off. Money is disabled throughout (see §6.6).
7. **Icon** — icon picker with reset-to-default action.
8. **Color / priority / linked note** — appearance override, P1–P5 chips,
   note link.

**(if editing) Delete** — destructive button with a confirmation dialog,
last in the scroll.

Header: inline cancel + save in the same row as the title — no detached
bottom action bar.

`_canSave` requires a non-empty title and, for weekly, at least one weekday.

### 6.4 Validation rules currently enforced by the editor

- Title trim non-empty.
- Weekly weekday set non-empty.
- Until date ≥ start date (clamped via `firstDate`).
- Start date moving forward past Until silently clears Until.
- The multi-date picker cannot confirm an empty set (Save is disabled), so a
  one-time event always keeps at least one date.

### 6.5 [`CalendarDatePickerSheet`](../lib/widgets/calendar_date_picker_sheet.dart)

The in-app replacement for `showDatePicker`, so date entry happens on the same
grid as the rest of the calendar. Two modes:

- `pickSingle` → `DateTime?`; tapping a day confirms immediately.
- `pickMulti` → `Set<DateTime>?`; days toggle, a footer shows the count with
  Clear / Today, and Save returns the edited set. Never returns empty.

It renders through `CalendarDayCell` / `CalendarDayBars` with the user's
`CalendarAppearance` (week start, accent, today style, week numbers), so it
cannot drift from the real grid, and it reuses the same collision-free row
height formula. An optional `dayLoad` callback draws a neutral "busy" bar on
days that already carry events — the calendar page passes
`CalendarBloc.eventsForDay`, which is the memoized O(1) lookup, so the picker
issues **no** extra queries.

This sheet picks **days**. Jumping the calendar to another month/year is a
different job with a different surface —
[`MonthYearPickerSheet`](../lib/widgets/month_year_picker_sheet.dart) (§6.1),
which the header's month title opens (`_openMonthYearJump`), exactly like the
calendar page's own header. In single mode its Apply confirms the
wheeled/typed date outright (the wheels carry a full date; re-tapping it on
the grid would be redundant); in multi mode it only jumps the grid there —
day toggling stays a grid gesture so a navigation intent can never edit the
set. Do **not** re-inline month/year *stages* into this sheet itself: that
was tried and turned a date-entry surface into a navigation maze. Linking
out to the dedicated jump surface is the sanctioned composition.

The appearance is **passed in** (page → editor sheet → picker), not re-read:
`getCalendarAppearance()` is eight sequential settings reads, and resolving it
after the first frame visibly re-lays-out the grid because week start and row
height both move. The page already holds a current copy and refreshes it when
returning from settings. The colour palette threads the same way (page →
bottom panel → rows) for the same reason plus staleness: a panel-local load
would happen once in `initState` and never see an edit.
`CalendarAppearance.showRecurrenceLabels` (a Calendar Settings switch,
default on) rides the same object and threads page → bottom panel →
`EventSummaryProvider` / `AgendaListView`: off, row subtitles drop the
repeat-pattern segment ("Daily", "Every 2 weeks", …) — for timed routines it
reads as redundant next to the time. Count labels (§3.4) and times stay.

Its mode enum is `CalendarDatePickerMode` — **not** `DatePickerMode`, which
`material.dart` already exports; the collision compiles inside the declaring
file and breaks any file importing both.

The multi mode deliberately knows nothing about *why* the dates matter (it
takes a set, returns a set). That is what lets the same surface later drive
per-occurrence skip dates without a UI rewrite.

#### Navigable range — [`CalendarBounds`](../lib/constants/calendar_bounds.dart)

**1900-01-01 … 2100-12-31**, one constant shared by the grid
(`_CalendarTable._firstDay/_lastDay`), both day pickers and the month/year
jump wheel. Single source of truth on purpose: a date the user can anchor an
event on must also be a date they can browse to, and the two drifting apart
is what made a 1991 birth year unreachable while the age count depended on
it.

The **1900 floor is the computus domain floor**, not a guess: the Julian
calendar's lag behind the Gregorian became 13 days in 1900 (12 through the
1800s), and that 13 is exactly what
`LiturgicalComputus.julianToGregorianOffset` returns for the 1900–2099
window, degrading to a flat 13 below it. Flooring at 1900 means every
Orthodox-Easter-derived holiday and fasting date stays correct instead of
silently landing a day off. Do not lower it without fixing that function.

Range width is **free at runtime**, which is why the old narrow windows
bought nothing:

- `TableCalendar` pages months through a lazy `PageView`; only the visible
  month is built (2412 months in range, ~1 built).
- The year wheel is a `ListWheelChildBuilderDelegate` — 201 rows, built as
  they scroll into view.
- `FastingCalendar` computes a year on first touch (O(365) of O(1) date
  math) and memoizes it, bounded at 12 years.
- `PublicHolidays.holidayOn` answers years outside the seeded window
  (current year + 5) from a **static fixed-date map** — one map probe, no
  database, no seeding. Browsing 1991 shows its fixed holidays (Christmas,
  New Year…) and no Easter-derived ones, exactly as it already did for any
  past year inside the old 2000 floor.

### 6.6 Markdown in descriptions

Descriptions are stored as **raw markdown source** and rendered on demand.
Nothing pre-rendered is persisted or cached in the database.

- **Rows** (day panel, agenda) use
  [`MarkdownInlineText`](../lib/widgets/markdown_inline_text.dart): the same
  `LineBasedMarkdownBuilder` as the preview — there is one grammar in this app
  and this adds no second one — with display-only adjustments. Headings render
  at body size via the new `LineMarkdownStyle.flattenHeadings`, blank lines are
  dropped and only the first 3 lines are kept, and **every tap callback is
  null**, which is what keeps the builder from allocating a single
  `TapGestureRecognizer` and makes the spans inert, cacheable and safe to drop.
  A process-wide memo (128 entries, oldest-inserted evicted first) is keyed on
  the raw source and invalidated wholesale when the render config
  (`brightness`, `fontSize`, colour, `palette.source`, `primary`) changes. The
  **hit path allocates nothing** — this runs in `build` for every visible row
  on every scrolling frame, so the config is compared field-by-field instead of
  through a composed key string, and the line-collapsing pass only runs on a
  miss.
- **Detail sheet** (and the editor's fallback preview) use
  `SimpleMarkdownPreview` — full fidelity, no flattening.
- **The editor sheet's description is a real re_editor surface.** It builds a
  `ListAwarePasteController` over a `CodeLineEditingController` whose
  `spanBuilder` is a sheet-owned `MarkdownEditorSpanBuilder`, hosted in the
  note editor's `ModernEditorWrapper` (`showScrollIndicator: false`). That is
  what makes live rendering, tap-to-toggle checkboxes, list continuation, Tab
  indent, ghost runs and the selection toolbar behave identically in both
  places without a second implementation. The whole stack is created and
  destroyed with the sheet; a ≤ few-dozen-line description makes the span
  builder's incremental line index and LRU memos effectively free. The global
  **live markdown rendering** setting is honoured, and a late-resolving
  setting is applied with `configureColors` + `forceRepaint()` — **never** by
  remounting the editor, which crashes re_editor's controller-delegate handoff
  mid-initialization (the same rule the note editor documents for money
  config). The editor box is height-bounded (120–260 px) because a
  `CodeEditor` owns its own scroller and cannot be unbounded inside the
  sheet's `SingleChildScrollView`; taking focus scrolls it into view, since a
  `CodeEditor` is not an `EditableText` and nothing does that automatically.
- **The markdown bar appears on description focus**, below the sheet's scroll
  view (so the form never shifts), reduced to `splitEnabled: false`, no
  settings / reorder, and undo+redo+paste as its only utility buttons.
  Shortcuts come from the app-wide `MarkdownBarBloc`'s active profile, with
  **counter-bound shortcuts filtered out** — `{c1}` resolves against a note
  context an event does not have. Ghost / colour-slot shortcuts route through
  the shared
  [`MarkdownShortcutInserter`](../lib/controllers/markdown_shortcut_inserter.dart),
  extracted from the note editor so both surfaces keep one implementation.
- **Checkboxes toggle only where "checked" has one meaning.** In the editor
  sheet, tapping a task box edits the buffer and persists on Save like any
  other keystroke. In the read-only detail sheet, tapping is enabled **only
  for `OneTimeRecurrence` events**: the description is a single string on a
  single row, so a checked box on a repeating (or specific-dates) event would
  read as checked on every occurrence — per-occurrence state would need an
  occurrence-keyed table. Those events keep inert boxes and are edited through
  the pencil. Detail-sheet toggles update local state immediately and coalesce
  into **one** `UpdateCalendarEvent` after 600 ms (flushed on close, on
  routing to edit, and in `dispose` so a drag-dismiss never loses a tap),
  because every write invalidates the bloc's day cache. The sheet renders and
  rewrites the **same trimmed string**, since the builder reports absolute
  source offsets for the `[ ]` / `[x]` bracket.
- **Description length is a setting, enforced by refusing to save.**
  `SettingsKeys.eventDescriptionLimit` (default 2000, slider 500–10000 in
  steps of 500, under Calendar Settings → Events, included in reset-to-
  defaults) replaces the old hardcoded `TextField(maxLength: 2000)`, which
  re_editor has no equivalent for. It is **never** enforced by truncation —
  the description is markdown the user typed, and dropping its tail silently
  is worse than refusing. Over budget: the counter above the field turns red,
  a line explains why, and Save is disabled. A **grandfather rule** keeps the
  guard from locking anyone out: a description is also allowed at any length
  it already had when the sheet opened (`_initialDescriptionLength`), so
  lowering the limit blocks *growth*, not editing. The getter/setter clamp to
  the slider bounds, so a corrupted value can never make every event
  unsavable. Both the counter and the Save button track the controller
  through `ListenableBuilder`s rather than keystroke-wide `setState` — but via
  the sheet's `_descriptionRevision` relay, **never the controller directly**:
  `_CodeEditorState.initState` wraps the controller in its own delegate and
  that `delegate =` setter calls `notifyListeners()` synchronously *while the
  framework is building*, so any builder mounted above the editor throws
  "setState() called during build" on the first frame. The relay is a
  `ValueNotifier<int>` that defers a mid-frame notification to a post-frame
  callback; keystrokes arrive outside the frame and take the fast path. Since
  v24 **each description scope carries its own budget and its own
  grandfather** (`_initialTemplateLength` / `_initialDayLength`), and
  `_canSave` checks both — reading only the live controller would let
  over-limit day text through while the template view is on screen.
- **Descriptions can be per-occurrence (v24; opted into per event since
  v28).** `CalendarEvent.perOccurrenceDescriptions` — an editor switch above
  the description field; the v24 global setting is gone (see the v28
  addendum) — turns the event's `description` into a **template**: a day with no row of its own
  renders the template, and the first edit or tick on a day materialises a row
  in `calendar_event_occurrences` seeded from it (copy-on-write). The table
  holds **only user deltas**, exactly like `public_holidays` since v22, so a
  daily event costs zero rows until it is touched.
  - **One resolution entry point**: `OccurrenceDescriptions.descriptionFor(event, day)`
    (`lib/constants/occurrence_descriptions.dart`). Never resolve a description
    for a day any other way, or the template fallback drifts between the day
    panel, the agenda, the detail sheet and search.
  - **The gate is the event's flag plus `rule is OneTimeRecurrence`, and
    nothing else.** An event
    firing on one day has nothing to separate; a `SpecificDatesRecurrence` is a
    list of distinct occasions and *does* participate. Never gate on the
    editor's `_RepeatMode`, which files specific-dates under `oneTime`.
  - **A row that exists always wins, including when empty.** `overrideFor`
    returns non-null (possibly `''`) for a present row and `null` only for a
    missing one — that is what keeps a deliberately blanked day blank instead
    of falling back. "Reset this day" **tombstones** the row (since v28); it
    never writes `''`. This also makes the notes-icon badge per-day-correct
    for free.
  - **Reversible in both directions.** Turning the setting on moves nothing;
    turning it off leaves rows dormant rather than deleting them. Rules that
    change so a day no longer occurs keep their row — a stored delta is the
    only durable record of a deliberate act. Deleting an event cascades
    (one transaction in `CalendarEventService.deleteById`/`deleteAll`).
  - **Static facade published by the service, not a page.** `EventOccurrenceService`
    publishes the cache at `getInstance()` — the
    `PublicHolidayService` shape, deliberately not `FastingCalendar`'s, whose
    post-first-frame `configure` would render templates for one frame and then
    flip every row on a cold start into the calendar. `reset()` must clear the
    singleton **and** the facade.
  - **Agenda search needs two passes.** `EventAgenda._matches` runs in the
    candidate pre-filter, *before* the day is known, so it is a deliberate
    **superset** test (title OR template OR *any* override); `_matchesOnDay`
    then narrows per day inside the scan. Testing only the superset would emit
    every occurrence of an event whose hit lives on one day.
  - **Writes skip the day cache.** `SetOccurrenceDescription` /
    `ClearOccurrenceDescription` bump `CalendarPageLoaded.occurrenceRevision`
    and deliberately do **not** call `_invalidateDayCache()` — that cache
    answers "which events occur on this day", and description text is not an
    input. (Ticking a box used to wipe all 512 entries via the whole-event
    update; it no longer does.) The revision is load-bearing twice over: the
    state is `Equatable`, so an otherwise-identical copy would be dropped, and
    `AgendaListView`'s identity-based row memo would keep serving stale text.
    `UpcomingAgendaView` forwards it but must never rescan on it.
  - **Editor scope control**: a `SegmentedButton` ("All days" / "This day")
    above the description, shown only when `initialEvent != null && occurrenceDay != null &&
    enabled && rule-has-many-occurrences`. **One controller throughout** —
    only its text is swapped, with the inactive scope buffered in a plain
    `String`. Swapping controllers would orphan `ModernEditorWrapper`'s
    listener (it binds in `initState` and has no `didUpdateWidget`), the span
    builder and the search controller, and drag re_editor through a delegate
    handoff nothing else in this app exercises. `clearHistory()` after every
    swap is mandatory: `set text` runs as a revocable op, so without it undo
    pulls the *other* scope's text into the active one and Save persists it.
    Flipping the form to one-time hides the control and calls
    `_syncScopeToRule`, which parks the day text unwritten — never merge an
    occurrence's text into the template. The sheet never persists: it reports
    `(occurrenceDay, occurrenceDescription)` on `EventEditorSaved` and the page
    dispatches, event write first.
- **Money is always disabled** in descriptions (`MoneyDisplayConfig.disabled`).
  A ledger balance is a per-note concept; a `$+ 50` line in an event
  description would render a balance derived from nothing, so those lines stay
  literal text.
- The colour palette threads from `SettingsService.getColorPalette()` through
  the calendar page / bottom panel, so `{name:text}` runs show the user's
  custom colours. It is value-equal on its persisted `source`, which is what
  makes it a legal cache-key component.

---

## 7. Backup & restore

The app-global backup is owned by
[`BackupService`](../lib/services/backup_service.dart). It serializes every
persisted store into a single JSON document with a `version` number.

**Backup version 4** (introduced when user-creatable categories were added)
adds a `calendarCategories` array alongside the existing `calendarEvents` and
`publicHolidays`. Categories are imported **before** events on restore so each
event's `categoryId` resolves. A v3 (or earlier) backup imports cleanly — the
missing `calendarCategories` key just leaves the seeded built-ins in place.

**Backup version 3** includes:

```jsonc
{
  "version": 3,
  "calendarEvents": [
    {
      "id": "…", "title": "…", "category": "gym",
      "startDateMs": 1717113600000,
      "allDay": true, "iconKey": null,
      "ruleKind": "weekly", "rulePayload": "{\"weekdays\":[1,3,5]}",
      "endDateMs": null,
      "startMinute": null, "durationMinutes": null,
      "createdAtMs": 1717100000000, "updatedAtMs": 1717100000000
    }
  ],
  "publicHolidays": [
    { "dateMs": 1735689600000, "nameKey": "newYear", "customLabel": null },
    { "dateMs": 1735776000000, "nameKey": "custom",  "customLabel": "Birthday" }
  ]
}
```

### 7.1 Round-trip discipline

- **Calendar events** mirror the row shape exactly. Reserved
  `startMinute` / `durationMinutes` are written even though application
  code doesn't set them — so a future version that introduces time-of-day
  events can still import an old backup without losing data.
- **Public holidays** mirror the row shape exactly. Custom rows survive
  verbatim. Built-ins are also dumped, but the seeder will re-fill any
  missing built-in for the seeded window on next start.

### 7.2 Backward compatibility on import

`BackupService.importFromJson()` reads new keys with `data['…'] as List?`,
so v1/v2 backups (no `calendarEvents` / `publicHolidays`) load cleanly and
leave existing calendar/holiday data in place. A v3 backup loaded by an
older binary simply ignores the unknown keys.

### 7.3 Behavior the user should know

- Restoring a v3 backup **deletes all** existing calendar events and
  holidays first, then inserts the backup contents — same destructive
  pattern used by other restore paths.
- After restore, the public-holiday seeder runs again on next start and
  re-adds any built-in row missing from the seeded window. **A built-in
  the user had deleted will come back after restore.** This is a known
  limitation; fixing it requires a tombstone column.

---

## 8. Concurrency & threading

- All database operations go through Drift, which serializes I/O on a
  background isolate.
- The in-memory caches (`CalendarEventService._cache`,
  `PublicHolidays._cache`) are mutated only on the UI isolate after a write
  resolves, so there is no read/write race.
- `CalendarBloc.eventsForDay` is synchronous and called from build methods.
  It writes into `_dayCache` during build, which is safe: Dart is
  single-threaded so a build and a bloc event handler never interleave, and
  the cached lists are `List.unmodifiable(...)`.

---

## 9. Localization

All user-visible strings live in the three ARB files
([app_en.arb](../lib/l10n/app_en.arb),
[app_de.arb](../lib/l10n/app_de.arb),
[app_ro.arb](../lib/l10n/app_ro.arb)).

Calendar-relevant key families:

- `eventCategory*` — category labels.
- `recurrence*` — rule kind labels, the formatted weekday list, the
  interval-aware summaries (`recurrenceEveryDays/Weeks/Months/Years`,
  `recurrenceEveryWeeksOn`) and the stepper strings
  (`recurrenceIntervalLabel`, `recurrenceUnit*`, `recurrenceInterval{In,De}crement`).
- `publicHoliday*` — named built-in holidays.
- `eventTitle`, `eventType`, `eventDate`, `repeatMode`, `repeatOnce`,
  `repeatRecurring`, `frequency`, `weekdays`, `weeklyDaysHint`, `startsOn`,
  `pickCategory`, `pickIcon`, `iconLabel`, `iconCustom`, `iconDefault`,
  `resetToDefault`.
- **v11 additions** — `eventUntilLabel`, `eventUntilNone`, `eventUntilHint`,
  plus the time-of-day strings (`eventAllDay`, `eventStartTime`,
  `eventEndTime*`, `eventCrossesMidnight`).
- **v12 additions** — `eventDescription`, `eventDescriptionHint`.
- **v14 additions** — `eventLinkedNote`, `eventLinkNoteHint`,
  `eventLinkedNoteMissing`, `eventOpenLinkedNote`, `eventRemoveNoteLink`.

The interval summaries use ICU `plural` so the `=1` form collapses to the
plain label ("Weekly") while `other` reads "Every N weeks"; Romanian adds the
`few` form. Plural placeholders must stay intact across all three ARBs.

After editing ARBs, re-run `flutter gen-l10n` to refresh
`AppLocalizations`.

---

## 10. Reserved / forward-compat surfaces

### 10.1 `start_minute` / `duration_minutes` (shipped)

Reserved in schema v11 and **now in active use**. The time-of-day path:

- [`EventTime`](../lib/models/calendar_event.dart) value object holds
  `startMinute` (minutes since local midnight, `[0, 1440)`) and an optional
  `durationMinutes` (`>= 1`; may exceed the remaining day to cross midnight).
- `CalendarEvent.time` is the single source of truth; `allDay` is derived as
  `time == null` and `all_day` is a write-time mirror used only for SQL.
- `_eventToCompanion` / `_rowToEvent` round-trip `start_minute` /
  `duration_minutes`; backup carries them too.
- The editor sheet shows a start/end time section whenever "All-day" is off.

### 10.2 `allDay`

Derived, not stored as the source of truth: `time == null`. The `all_day`
column (present since v10) is kept in sync on write purely so future SQL
filters can use it without decoding `time`.

---

## 11. Known limitations

| Limitation                                                         | Impact   | Mitigation                                                                             |
| ------------------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------- |
| No skip-this-occurrence (exceptions)                                | Medium   | Would need an `event_exceptions(event_id, date)` table; checked in `occursOn`. The multi-date `CalendarDatePickerSheet` (§6.5) is already the UI for it. |
| Retroactive events export forward-only to `.ics`                    | Low      | RFC 5545 has no pre-`DTSTART` occurrences; the clamp is deliberate (§3.3).            |
| `.ics` exports the template, never per-occurrence descriptions       | Low      | A **scope call, not a format limit**: RFC 5545 supports it via a second `VEVENT` with the same `UID` plus `RECURRENCE-ID`, and `EXDATE`/`RDATE` already prove per-day components are cheap here (§6.6). |
| No "mark done" / completion log                                    | Medium   | Would need a `completions(event_id, date)` table; surfaces as a check on the day card. |
| Linked note opens read-through only                                 | Low      | The link is one-way (event → note); a note does not list events that reference it.     |
| Movable feasts have no out-of-window fallback                      | Low      | Acceptable; users only see seeded window.                                              |
| No reminders / notifications                                       | Medium   | Requires platform plugin work; intentionally deferred.                                |
| Recurrence math has no automated test coverage                     | Medium   | Pure, deterministic logic; high-value target for unit tests (interval phase, Feb-29, day-31 skips). |

---

## 12. File map (quick reference)

| Concern                  | Path                                                                              |
| ------------------------ | --------------------------------------------------------------------------------- |
| Domain model             | [lib/models/calendar_event.dart](../lib/models/calendar_event.dart)               |
| Category model           | [lib/models/calendar_category.dart](../lib/models/calendar_category.dart)         |
| Category cache facade     | [lib/constants/calendar_categories.dart](../lib/constants/calendar_categories.dart) |
| Category service          | [lib/services/category_service.dart](../lib/services/category_service.dart)        |
| Category table / DAO       | [lib/database/tables/calendar_categories_table.dart](../lib/database/tables/calendar_categories_table.dart), [lib/database/daos/calendar_category_dao.dart](../lib/database/daos/calendar_category_dao.dart) |
| Category UI                | [lib/widgets/category_editor_sheet.dart](../lib/widgets/category_editor_sheet.dart), [lib/pages/calendar_categories_page.dart](../lib/pages/calendar_categories_page.dart), [lib/widgets/category_picker_sheet.dart](../lib/widgets/category_picker_sheet.dart) |
| Recurrence rules         | [lib/models/recurrence_rule.dart](../lib/models/recurrence_rule.dart)             |
| Occurrence override facade | [lib/constants/occurrence_descriptions.dart](../lib/constants/occurrence_descriptions.dart) |
| Occurrence override service | [lib/services/event_occurrence_service.dart](../lib/services/event_occurrence_service.dart) |
| Occurrence table / DAO   | [lib/database/tables/event_occurrences_table.dart](../lib/database/tables/event_occurrences_table.dart), [lib/database/daos/event_occurrence_dao.dart](../lib/database/daos/event_occurrence_dao.dart) |
| Holiday enum + facade    | [lib/constants/public_holidays.dart](../lib/constants/public_holidays.dart)       |
| Drift table (events)     | [lib/database/tables/calendar_events_table.dart](../lib/database/tables/calendar_events_table.dart) |
| Drift table (holidays)   | [lib/database/tables/public_holidays_table.dart](../lib/database/tables/public_holidays_table.dart) |
| DAO (events)             | [lib/database/daos/calendar_event_dao.dart](../lib/database/daos/calendar_event_dao.dart) |
| DAO (holidays)           | [lib/database/daos/public_holiday_dao.dart](../lib/database/daos/public_holiday_dao.dart) |
| Schema constants         | [lib/database/migrations/database_schema.dart](../lib/database/migrations/database_schema.dart) |
| Migrations               | [lib/database/migrations/database_migrations.dart](../lib/database/migrations/database_migrations.dart) |
| Calendar indexes         | [lib/database/migrations/database_indexes.dart](../lib/database/migrations/database_indexes.dart) |
| Service (events)         | [lib/services/calendar_event_service.dart](../lib/services/calendar_event_service.dart) |
| Service (holidays)       | [lib/services/public_holiday_service.dart](../lib/services/public_holiday_service.dart) |
| Backup integration       | [lib/services/backup_service.dart](../lib/services/backup_service.dart)           |
| Editor UI                | [lib/widgets/event_editor_sheet.dart](../lib/widgets/event_editor_sheet.dart)     |
| Category icons & colors  | [lib/constants/calendar_icons.dart](../lib/constants/calendar_icons.dart), [lib/constants/calendar_colors.dart](../lib/constants/calendar_colors.dart) |
| L10n                     | [lib/l10n/app_en.arb](../lib/l10n/app_en.arb), [lib/l10n/app_de.arb](../lib/l10n/app_de.arb), [lib/l10n/app_ro.arb](../lib/l10n/app_ro.arb) |

---

## Addendum (schema v15–v18): panel system, agenda, timeline, `.ics`, priority scale

Written 2026-08. Everything in this section shipped after the v14 snapshot
above; where the two disagree, this section wins.

### Bottom panel system

The area under the grid is now a mode-switched panel owned by
[lib/widgets/calendar_bottom_panel.dart](../lib/widgets/calendar_bottom_panel.dart):

- **`CalendarPanelMode`** ([lib/models/calendar_panel_mode.dart](../lib/models/calendar_panel_mode.dart)):
  `day` (the original day summary), `timeline`, `upcoming`. Persisted by name
  (`calendar_panel_mode`, forward-compatible fallback to `day`).
- `CalendarBottomPanel` owns the mode **and** the agenda filters *below* the
  page, so agenda keystrokes rebuild only the panel subtree — never the
  `TableCalendar` grid. It loads its persisted state once in `initState`;
  nothing on the settings page edits it, so it does not participate in the
  page's reload-on-return path.
- **Expand toggle** (in the mode bar): collapses the grid to zero height via
  `AnimatedSize` on the page so the panel can take the whole screen.
  Deliberately transient — restoring a hidden calendar across app opens
  would read as "the calendar disappeared".

### Upcoming agenda (search across events)

- Pure scan module [lib/utils/event_agenda.dart](../lib/utils/event_agenda.dart):
  `occurrencesInRange` expands recurrences over a clamped range
  (`maxRangeDays = 366`) using the same `CalendarEvent.occursOnUtcDay` as the
  bloc's day cache (the allocation-free hot-path variant of `occursOn`, which
  requires an already date-only UTC day); **never runs inside `eventLoader`**.
  Before the day loop it **prunes candidates** whose `[startDate, endDate]` span
  cannot intersect the window and **buckets one-time events by day** (so they
  cost zero `occursOn`), leaving only real candidates in the O(days ×
  candidates) scan — `SpecificDatesRecurrence` is the one rule left unpruned
  because it has no pre-start guard. Every survivor is still validated through
  `occursOnUtcDay`, so pruning only ever drops non-occurrences.
  `holidayDaysInRange` walks the same resolved range; `compareWithinDay` is the
  **single comparator** for same-day event order (also used by
  `EventSummaryProvider`, with `DaySummaryResolver.resolve` made stable so the
  order survives).
- Filters are one value object,
  [lib/models/upcoming_agenda_filters.dart](../lib/models/upcoming_agenda_filters.dart)
  (range preset / custom range / priority set / query / holidays + fasting
  toggles / event-type / **category allowlist** / collapse-recurring /
  collapse-fasting / follow-selected-day), persisted
  via `SettingsService.getUpcomingAgendaFilters` / `saveUpcomingAgendaFilters`.
  The query write is debounced 500 ms and flushed on dispose. **Empty priority
  set means "all"** — the filter off, never "nothing matches" (the category
  allowlist `categoryIds` works the same way: empty = every category, sorted-CSV
  codec). An elapsed custom range is dropped on load.
- **Category allowlist**: a chip section inside the filters sheet, multi-select
  over `CalendarCategories.all` (read on every build so a database switch cannot
  leave it stale), with an "All categories" reset. Applied in the scan's
  candidate pre-filter (`categoryIds.isNotEmpty && !contains`), **composed on top
  of** the inherited calendar-global `hiddenCategoryIds` — both apply, so a
  globally-hidden category stays hidden even if allowlisted. O(events), same tier
  as the priority/hidden checks; a stale allowlisted id (deleted category) is
  harmless since no event carries it.
- **Collapse recurring** (`collapseRecurring`, off by default): a switch in the
  filters sheet that, when on, shows each recurring event **once** — its next
  in-window occurrence — instead of one row per occurring day. Applied as a
  **post-filter** on the scan's `result` (two passes: tally per recurring id,
  then keep the first-seen occurrence carrying that tally as
  `EventOccurrence.occurrenceCountInWindow`; one-time events untouched), so
  `occursOn` counts are unchanged. The row's recurrence label ("Daily",
  "Weekly") carries the cadence and a "N× in window" badge says what it stands
  in for. Being an opt-in toggle, it collapses *all* recurring events
  (specific-dates included), not just high-frequency ones — the toggle is the
  escape hatch. See
  [upcoming-agenda-dense-recurrence-roadmap.md](upcoming-agenda-dense-recurrence-roadmap.md).
- **Fasting presentation** (`fastingDisplay`, an `AgendaFastingDisplay` of
  `everyDay` / `periods` / `summary`, **`periods` by default**): a
  `SegmentedButton` in the filters sheet's Display section, shown only when
  `FastingCalendar.isEnabled`. It replaced the `collapseFasting` bool on
  2026-08-23 — three mutually exclusive presentations of one thing, where a
  second bool stacked on the first would have encoded "collapse *and*
  summarize". Persisted by name under `calendar_upcoming_fasting_display`;
  when that key is **absent** the retired `calendar_upcoming_collapse_fasting`
  boolean is read once as a fallback (`true` → `periods`, `false` →
  `everyDay`) and never written again, so no configuration resets on update
  and no migration pass was needed.
  - **`periods`** is the shipped collapse, structurally different from
    collapse-recurring — fasting days never enter the event scan, and a Lent is
    a *run of one period*, not a repeated id. `EventAgenda.fastingRunsInRange`
    groups the in-window days **per (tradition, period)** — never by the
    boolean `isFastingDay`, which is wrong in both directions: a period the
    personal weekday/month scope sparsified would shatter into one-day rows,
    and two different periods that happen to touch would fuse into one span. A
    **multi-day** period (`greatLent`, `apostlesFast`, `dormitionFast`,
    `nativityFast`, `cheesefareWeek`, `lent`, `advent`, `ramadan` — the ones
    whose days can legitimately be sparse) bridges a gap of up to **7 days**;
    everything else, the year-round weekly fasts included, keeps strict
    contiguity, because bridging the weekly rule would fuse a whole window into
    one meaningless span. Each run's edges are then walked **outward past the
    window** under the same gap rule (capped at `maxRangeDays` *steps* per
    direction, via the memoized `FastingCalendar.on` — never `occursOn`), so a
    clipped period still reports its true extent. `FastingRun.dayCount` counts
    the days actually **marked**, not the calendar distance between the edges —
    for a contiguous run they agree, for a sparse one only the count is honest.
    `buildAgendaRows` emits one row per run on its first in-window day, taking
    the provider entry matching the run's tradition (entries are keyed
    `fasting:<tradition>`, and several runs may open on the same day) with its
    subtitle swapped for "Nov 15 – Dec 24 · 40 days"; a run of one marked day
    keeps the day's regime instead.
  - **`summary`** is one card for the whole window, **per enabled tradition**
    (not per fast — a window holding Lent *and* the weekly rule would otherwise
    be right back at several cards). `EventAgenda.fastingSummariesInRange`
    walks the window once, accumulating one `FastingSummary` per tradition:
    the weekday set actually marked, first/last marked day, the marked-day
    count, and the distinct span periods present in first-seen order. Every
    number is **window-scoped** — unlike a run, which reports a period's true
    extent because it *is* the period, a summary describes "fasting in this
    window", and claiming days outside it would make the card disagree with the
    list it summarizes. Traditions with no marked day produce nothing, and the
    result follows `FastingTradition` declaration order (matching
    `FastingCalendar.on`). `buildAgendaRows` emits the cards **before the first
    month/day header** as `AgendaFastingSummaryRow`s — deliberately *not*
    `AgendaEntryRow`s, so the panel's "N entries" count leaves them out with no
    extra logic: a card summarizes entries rather than being one. The entry is
    synthesized in the agenda layer (icon/colour/description/priority from the
    tradition's `FastingTraditionStyle`, exactly as a run row resolves them),
    with the title preferring `titleOverride`, then the window's single named
    fast, then the tradition's name. The subtitle is three fragments joined by
    `' · '`: the weekday pattern (all 7 → `recurrenceDaily`, Mon–Fri →
    `recurrenceWorkdays`, Sat–Sun → `recurrenceWeekends`, else abbreviated
    locale weekday names joined with `', '` — Monday-first, no conjunction,
    whose placement is locale-dependent), the span (exact `rangeLabel` up to
    **62 days**, a `monthRangeLabel` beyond it), and `upcomingFastingSpanDays`.
    Tapping the card focuses its first in-window day.
  - **`everyDay`** is the uncollapsed listing, one row per marked day.
  - The query filter is handed to the run walk **and** the summary scan, so
    neither can claim days the search excluded. `fastingDisplay` stays out of
    `restrictiveFilterCount` and the summary-chip row for the same reason
    `collapseRecurring` does: it condenses rows, it never hides content.
- **Three independently-suppressible layers.** The sheet presents them as three
  peer toggles — **Events / Holidays / Fasting** — with All / Recurring /
  One-time as a `SegmentedButton` *under* Events. The model underneath is
  unchanged: one mutually-exclusive `AgendaEventType` axis where **Events off ⇔
  `none`**, applied in the scan's candidate pre-filter (`recurring` =
  `rule is! OneTimeRecurrence`, so specific-dates counts as recurring; `none`
  short-circuits the event scan to empty, which is how "upcoming holidays
  without events" is expressed). The `upcomingEventTypeNone` ARB key is gone —
  the state is now reached by switching Events off, and the *summary* chip for
  it reads `upcomingEventsHidden` ("No events"). Holidays and fasting are day
  annotations toggled independently and interleaved by `buildAgendaRows`'
  three-cursor ascending merge (`EventAgenda.fastingDaysInRange` mirrors
  `holidayDaysInRange` and reuses `FastingSummaryProvider`). The **fasting chip
  is hidden** unless a tradition is configured (`FastingCalendar.isEnabled`),
  and the priority + category sections hide while Events is off. Both annotation
  scans respect the text query (matched against their localized labels).
- **The window starts today, unless `followSelectedDay` is on** (default off).
  The anchor is **panel-owned state** (`_CalendarBottomPanelState._agendaAnchor`
  → `UpcomingAgendaView.anchorDay`), not `CalendarPageLoaded.selectedDay`,
  because the selection and the window are two different things. `_syncAnchor`
  holds every rule: following off ⇒ the anchor is today (which also picks up a
  date rollover on the next rebuild); no `previous` ⇒ resolve from scratch
  (filters loaded, or the toggle just flipped on); an
  `CalendarSelectionSource.agendaRow` selection **never** re-anchors; anything
  else follows a selection that actually changed. A custom range still overrides
  the anchor entirely, and the rescan stays guarded (`anchorChanged =
  !hasCustomRange && anchor moved`), so an anchor move under a pinned range
  costs nothing. Not persisted: reopening starts from today. The three
  wall-clock reads that must **stay** on `now()` — the picker's initial range,
  the Today/Tomorrow row headers, and `withoutElapsedRange` — are not anchor
  material.
- **`SelectCalendarDay` carries a `CalendarSelectionSource`**
  ([lib/models/calendar_selection_source.dart](../lib/models/calendar_selection_source.dart)):
  `grid` (a day cell), `agendaRow` (a row in the agenda) or `navigation`
  (initial load, "today", the month/year picker). Required on the event, so a
  new dispatch site has to decide rather than silently inheriting a default that
  would make the agenda re-anchor on its own rows again. It rides on
  `CalendarPageLoaded.selectionSource` and is **excluded from both
  `sameGridInputs` and `samePanelInputs`** — nothing renders from it, so
  re-selecting the same day from a different surface must not repaint 42 cells;
  a source change that matters always arrives with a `selectedDay` change, which
  both tests already catch.
- **The anchor rescan stays cheap and unsurprising** (2026-08 regression fix,
  [calendar-anchor-perf-regression-2026-08.md](calendar-anchor-perf-regression-2026-08.md)):
  a query-only change debounces the scan ~200 ms (the field stays live); an
  anchor-driven rescan is synchronous and scrolls the agenda to the top so the
  tapped day becomes the first row; and the panel's `BlocBuilder` uses
  `CalendarPageLoaded.samePanelInputs` (every input **except** `focusedDay` /
  `format`), so month paging no longer rebuilds the panel or re-runs the scan —
  paired with `_onChangeFocusedDay`'s no-op guard against the page-settle emit.
- **Filter chrome lives in a sheet, not the panel** (2026-08-22 redesign,
  [upcoming-agenda-redesign-roadmap.md](upcoming-agenda-redesign-roadmap.md)).
  [agenda_filters_sheet.dart](../lib/widgets/agenda_filters_sheet.dart) holds
  Period / Show / Priority / Categories / Display, edits a **local draft** and
  returns it on Apply (never live-applies — that would rescan behind the sheet);
  its Reset restores every sheet-owned field but **preserves `query`**, which
  the sheet does not own. Inline the panel keeps only: the search field, a
  `Badge.count` on the tune button, one horizontally-scrolling row of removable
  summary chips, and the header line. `filtersExpanded` and its settings key are
  retired (the orphaned stored value is inert; no migration).
- **Summary chips show only what is *narrowing* the list** — custom-or-non-default
  window, event type, priorities, categories. `UpcomingAgendaFilters
  .restrictiveFilterCount` is the single definition the badge and the chip row
  share. Layer additions (holidays, fasting) and the collapse switches are
  deliberately excluded: they add or condense rows, so they can never answer
  "why is this missing", which is the question the row exists for. Each chip's
  body opens the sheet and its "×" (tooltip `upcomingRemoveFilter`) resets that
  one filter.
- **The Custom period chip is an `InputChip`** whose delete "×" (tooltip
  `upcomingClearRange`) clears the range back to the anchored preset window; the
  "×" shows only while a range is active. `showCheckmark: false` keeps the
  `date_range` avatar as the chip's identity instead of swapping in a checkmark.
  It now lives in the sheet's Period section, labelled with the active range.
- **The header line carries the anchor chip.** While the anchor drives the
  window and sits off today (`!hasCustomRange && anchorDay != today`), an
  `InputChip` reads `upcomingAnchorFrom` ("from Aug 25") and its "×"
  (`upcomingResetAnchor`) returns the window to today. With `followSelectedDay`
  off the anchor is always today, so the chip never appears.
- Text matching folds case *and* diacritics through the note search's
  `normalizeForSearch`, so "sarbatoare" finds "Sărbătoare" here exactly as in
  note search. Holiday labels match localized.
- Rendering: [lib/widgets/upcoming_agenda_view.dart](../lib/widgets/upcoming_agenda_view.dart)
  (controlled; owns nothing persistent) over
  [lib/widgets/agenda_list_view.dart](../lib/widgets/agenda_list_view.dart)
  (row list memoized on input identity + locale; holiday days interleave so a
  holiday-only day still gets a header; rows reuse `EventSummaryProvider`, so
  agenda and day panel cannot drift). `AgendaRow` has **three** variants:
  `AgendaMonthHeaderRow` (emitted only when the built rows span ≥ 2 months, with
  `showYear` when the window crosses one), `AgendaDayHeaderRow`, and
  `AgendaEntryRow` (carrying `occurrenceCount`). **Every entry row is an
  `_AgendaCard`** — the roomier `Card` + accent-stripe + `ListTile` +
  `CircleAvatar` layout, holidays and fasting included (those get
  `trailing: null`, having no event to edit or open). Two restylings were tried
  on 2026-08-22 and both reverted: a denser card interior, and slim tinted
  annotation rows for the `entry.event == null` entries. The bigger card is the
  intended look on every row type — do not restyle without asking. All four
  `DateFormat` skeletons the agenda uses are cached per locale on
  `AgendaListView` (`rangeLabel`, `anchorLabel`, `monthLabel`,
  `dayHeaderLabel`) — never construct one per row. Note `buildAgendaRows` now
  formats dates for a collapsed fasting span, so a bare unit test of it must
  `initializeDateFormatting` first; in the app the localization delegates
  already have.

### Day timeline

[lib/widgets/day_timeline_view.dart](../lib/widgets/day_timeline_view.dart) +
pure layout [lib/utils/day_timeline_layout.dart](../lib/utils/day_timeline_layout.dart):
the only surface rendering `EventTime.durationMinutes`. Overlapping events
pack into side-by-side columns **per overlap cluster**; all-day events pin to
a chip strip above the grid; a "now" line shows on today. Blocks use
`colorValue ?? category.color` (the `EventDayBarProvider` rule). All vertical
placement goes through one `_offsetOf` helper so gridlines, blocks and the
now-line cannot drift.

### `.ics` export

[lib/utils/ics_serializer.dart](../lib/utils/ics_serializer.dart) →
`ImportExportService.exportCalendar` → `ExportCalendarRequested` on
`ImportExportBloc` → `shareExport`. Floating local time (the app stores no
timezone); `DTSTART` moves to the first *real* occurrence so `BYDAY`/interval
phase can't drift; workdays emit `BYDAY=MO..FR` + `EXDATE`s for holidays;
holidays-only and specific-date sets emit `RDATE`s; expansions bounded by
730 days. `ExportFormat` was deliberately **not** extended (it would leak
into note-format pickers); `.ics` is registered with `sweepStaleExports`.
Entry point: calendar app-bar overflow menu.

### Priority scale (v18): 1 is highest

- Stored priorities read like **P1..P5 — lower number = higher priority**.
  The v18 migration flips existing rows (`p -> 6 - p`) inside the upgrade
  transaction, flips the persisted agenda priority filter, and folds the
  retired `calendar_upcoming_min_priority` threshold key into
  `calendar_upcoming_priorities`.
- **Backup version is now 7**; backups < 7 carry the old 5-is-highest values
  and are flipped on import in `BackupService.importFromJson`.
- Display lives in one place:
  [lib/constants/event_priorities.dart](../lib/constants/event_priorities.dart)
  (`iconFor`: double-up / up / drag-handle / down / double-down;
  `labelOf`: Highest..Lowest). The editor picks priority with icon+label
  ChoiceChips (the numeric stepper died with the flip — a "+" that lowers
  priority cannot be made unambiguous); the agenda's filter chips carry the
  same icons; agenda row badges show the label for non-Normal priorities.
- Ranking sites all agree: `EventAgenda.compareWithinDay` (ascending),
  day bars / day summary map `event.priority - kMinEventPriority` into the
  0-is-top band, and the `.ics` `PRIORITY` maps 1→1, 3→5, 5→9 (RFC 5545
  shares the 1-is-highest direction).

### Navigation fix that lives here

Opening an event's linked note (and last-location restore) now passes
`NoteRepository.noteToMetadata(row)` to the editor, so the title bar shows
the real note title instead of "New note".

## Addendum (schema v26): presence tracking

Recurring events can opt in to **presence tracking** (`tracks_presence`, v26
additive column; editor switch at the end of the When section, shown when
the rule has many occurrences, save mirror `recurring && flag` like
`retroactive`'s). A missed day is one live row in `calendar_event_absences`
— PK `{event_id, day}`, plus the five notes/folders CRDT columns, stamped in
`EventAbsenceDao` (`db.generateHlc()`, `db.deviceId`, read-then-write
`version + 1`). Un-marking **tombstones** the row; re-marking resurrects it
with `created_at` intact — a last-writer-wins element set, cloud-ready from
birth (cloud-sync phase-02 — now **v31** — wires transport; absences
**sync**, and since v28 per-occurrence descriptions do too).

- **One read entry point**: `EventPresence`
  (`lib/constants/event_presence.dart`) — `appliesTo(event)` is
  `tracksPresence && rule is! OneTimeRecurrence` (specific-dates
  participates), `isMissed(eventId, day)` is an O(1) probe safe inside
  `DayBarProvider.barsFor`. Published by `EventPresenceService` (the
  `EventOccurrenceService` shape minus the global flag — opt-in is per
  event); `reset()` clears the singleton **and** the facade.
- **Presence is render-only.** It never changes `occursOn`, the bloc's day
  cache, `EventAgenda` scans, `countOccurrences` labels, or `.ics`.
  `SetOccurrenceMissed` / `ClearOccurrenceMissed` bump `occurrenceRevision`
  and never `_invalidateDayCache()`.
- **Display**: `CalendarMissedDisplay` (`faded` | `hidden`) on
  `CalendarAppearance` (`SettingsKeys.calendarMissedDisplay`, default
  `faded`, Calendar Settings → Events, in reset-to-defaults). Grid bars fade
  with `CalendarColors.missedEventAlpha` or are skipped before consuming a
  `maxDayBars` slot; the agenda (mode in its row-memo key; a day whose only
  occurrence is hidden loses its header, though the panel-level count still
  counts hidden occurrences) and the timeline (all-day chips included,
  filtered before layout) follow the setting; the **day summary panel always
  shows missed rows, faded** — it is the toggle surface. Marking: a trailing
  `IconButton` on presence-tracked day-panel rows (replaces the chevron), or
  the Present/Missed `SegmentedButton` in the detail sheet (immediate write
  + haptic, no debounce).
- `DaySummaryEntry` carries `presenceTracked` / `missed` (both in `props` —
  the agenda's identity-based row memo depends on them).
- **Backup**: additive `eventAbsences` key — live rows only, no CRDT fields
  (backups are not a sync channel; `importAbsence` regenerates identity
  while preserving `createdAt`/`updatedAt`), no version bump, and the same
  absent-key-with-present-`calendarEvents` clear rule as occurrences.
- Since v27, a single-event delete tombstones the event and bulk-tombstones
  its absences in one transaction; occurrence descriptions are still
  hard-deleted (device-local), and bulk wipes stay hard.
- Design record: `docs/presence-tracking-roadmap.md`.

## Addendum (schema v27): `calendar_events` CRDT + agenda/detail fixes

`calendar_events` carries the five CRDT columns since v27 — with
`DEFAULT ''` on `hlc_timestamp`/`device_id` (an `ALTER TABLE` on a populated
table demands a default; the migration backfills real identity in one
`UPDATE` bound to `generateHlc()`/`deviceId`, and every write path stamps,
so `''` never survives a write). Layering is unchanged: the domain
`CalendarEvent` has no CRDT field; everything lives in `CalendarEventDao`.

- `upsert` — read-then-write: miss → `version 1`; hit → fresh HLC/device,
  `version + 1`, `createdAt` masked, and **explicit `isDeleted: false` +
  `deletedAt: null`** — an id-reusing restore over a tombstone must
  resurrect, never update an invisible row. `importData`'s hard wipe stays
  hard forever as the second belt.
- Single-event delete = `softDeleteById` (the `softDeleteNote` shape) +
  `EventAbsenceDao.tombstoneForEvent` (bulk, one shared HLC) + the
  occurrence cascade (hard here; tombstoning since v28), in one transaction.
  `deleteAll` and import wipes stay hard — "Delete all events" promises
  permanence; cloud-sync phase-02 (now **v31**) owns the synced-wipe
  decision and needs only `owner_id` + transport.
- `reassignCategory` — one `customUpdate`: `version = version + 1`, one
  shared HLC, `Variable<DateTime>` binds, `AND is_deleted = 0`.
- `getAll()` filters `is_deleted = 0` behind the now-**partial**
  `idx_calendar_events_start_date`; the migration `DROP`s the full index
  first (`IF NOT EXISTS` would strand upgraders on the full one). One
  filtered read path → grid, panels, agenda, timeline, backup export and
  `.ics` agree for free. A real v26→v27 migration test pins the backfill,
  the index swap and idempotence.

Agenda: rows are built once by the pure top-level `buildAgendaRows`
(`agenda_list_view.dart`; pure *given* the `EventPresence` /
`OccurrenceDescriptions` facades — memos over it must key
`occurrenceRevision`). `UpcomingAgendaView` owns the six-key memo and
derives the panel header count from the `AgendaEntryRow`s it renders —
exact in hidden mode, counting visible entries (holiday entries
individually). `AgendaListView` is a stateless renderer of `rows`. The day
summary panel's count is deliberately unchanged — it always shows missed
rows, so its count already matches its screen.

Detail sheet: the date row shows the opened occurrence day (`widget.day`;
the presence toggle directly beneath marks that date), and a label-less
`Icons.event_repeat_rounded` row — `eventDetailsSeriesStart`, "Repeats
since {date}" — follows the recurrence-pattern row for recurring events
whose series anchor differs.

Design record: `docs/calendar-cloud-readiness-roadmap.md`.

## Addendum (schema v28): per-event description scope + occurrence CRDT

The v24 global per-occurrence-descriptions setting is gone. Each recurring
event carries `per_occurrence_descriptions` (default 0, the
`tracks_presence` twin): on, the event keeps a separate description per day
with its own description as the template; off, one shared description
updates everywhere. The v28 migration converted intent settings-driven —
exactly when the stored value of the frozen literal
`'event_per_occurrence_descriptions'` was `'true'`, every live repeating
event was flagged on (`WHERE rule_kind != 'oneTime' AND is_deleted = 0`),
so a global-ON user saw zero change; the `SettingsKeys` constants and the
service's whole flag half (`enabled`/`setEnabled`/`_readEnabled` and the
post-import re-reads) are deleted, and the settings-page entry is gone.

- **The gate lives in the facade**: `OccurrenceDescriptions.appliesTo` =
  `event.perOccurrenceDescriptions && rule is! OneTimeRecurrence`. Because
  `descriptionFor` calls it, the detail sheet, day-panel badge, agenda
  narrowing and both row surfaces followed the flag with no widget edits.
- **The editor reads its draft, never the saved row**: `_scopeGateOpen`
  (= rule-has-many-occurrences && the sheet's `_perOccurrenceDescriptions`
  state) gates `_scopeControlVisible`, `_resolveOccurrenceOutcome` and
  `_syncScopeToRule`'s early-out. The switch sits in Details directly above
  the description field; flipping it off mid-edit parks the day text
  exactly like flipping to one-time, and Save mirrors `recurring && flag`.
- **`calendar_event_occurrences` carries the five CRDT columns** (the
  second populated-table conversion: `DEFAULT ''` identity + one-statement
  backfill). `EventOccurrenceDao` is the `EventAbsenceDao` shape plus
  `description`: `getActive`, read-then-write `upsert` (explicit
  `isDeleted: false` + `deletedAt: null` on the update branch — re-writing
  a reset day resurrects its row, `created_at` intact), `tombstone`
  (= "reset this day"), `tombstoneForEvent`, `importOccurrence` (fresh
  identity, audit timestamps preserved); the hard variants serve
  wipes/import only.
- **A single event delete tombstones all three tables** — event, absences,
  occurrences — in one transaction, one statement each.
- **Backups**: the flag rides the event map additively; version stays 7.
  Pre-v28 backups restore with every flag off and rows dormant — the flag
  was never in the settings allowlist, and an archive that never carried
  intent is not mined for it; enabling an event restores its imported day
  texts.
- Phase-02 (renumbered **v31**) syncs occurrences —
  `keyLastEventOccurrenceHlc = 'last_event_occurrence_hlc'`, delta feeds in
  the notes shape.

Design record: `docs/description-scope-roadmap.md`.

---

## Addendum (schema v29): event templates

Reusable presets: everything an event needs **except a date**. Applying one to
a day stamps out a `CalendarEvent` anchored there.

- **A separate entity from categories, deliberately.** A category is a
  taxonomy — one row per kind of thing — while a user wants several presets
  inside one ("Push day" and "Leg day" both under Gym). Folding defaults into
  `calendar_categories` would cap that at one preset per category forever.
- **`calendar_event_templates`** (PK `id`) carries category, `rule_kind` /
  `rule_payload`, `start_minute` / `duration_minutes`, description, icon,
  colour, `tint_icon`, priority, `retroactive`, `count_occurrences` /
  `count_style`, `tracks_presence`, `per_occurrence_descriptions`,
  `sort_order`, audit timestamps and the five CRDT columns **from birth** (the
  v27 retrofit priced the alternative: five ALTERs plus a backfill; a table
  that starts empty gets the shape for free, with no `DEFAULT ''` deviation).
- **`name` doubles as the stamped title** — no `title` column. Categories set
  the one-label precedent; a separate column is additive later.
- **No `note_id`**: a linked note is per-instance, and stamping one note onto
  many events would break the money ledger's per-(day, note) attribution.
- **Nullable means "defer to the default at apply time"**, and only where
  `null` already means that on the event: `icon_key`, `color_value`,
  `start_minute` / `duration_minutes` (null time = all-day, which is why there
  is **no `all_day` column**), `description`, `rule_payload`.
- **`SpecificDatesRecurrence` collapses to one-time on capture** — absolute
  dates are meaningless in a template.
- **`EventTemplate.buildEvent` clears the repeat-only flags for a one-time
  rule** (`retroactive`, `countOccurrences`, `tracksPresence`,
  `perOccurrenceDescriptions`), matching the editor's own save guards.
- **No index**: the read path is one `getAll()` into memory at startup over a
  table of dozens of rows (the v24 occurrences precedent).
- **`RecurrenceCodec`** (`lib/models/recurrence_rule_codec.dart`) is now the
  one encoding of a rule into `rule_kind` / `rule_payload`;
  `CalendarEventService` delegates to it. Two hand-written copies would drift
  the first time a rule kind is added, and a template that encodes `weekly`
  differently from an event is a rule that silently changes meaning when
  applied.
- **Two entry points, and only two.** Primary: **long-press a day cell** →
  `EventTemplatePickerSheet` → **immediate create** plus an Undo snackbar,
  because the two things that normally need confirming — title and date — are
  already decided. When the rule does not fire on the pressed day (a weekly
  template whose weekday set excludes it) the snackbar names the day it will
  actually land on instead of letting it look like nothing happened. Secondary:
  **"Save as template"** at the bottom of the event editor's scroll body, above
  Delete — the inline header stays `close | title | Save`.
- **Backups**: additive key `eventTemplates`, version stays 7. Strand rule
  keyed to **categories**, not events: an absent key alongside a present
  `calendarCategories` clears the table, because the category import just wiped
  the id space templates point into. Imported after categories.
- `ImportExportService.archiveVersion` stays **1** — the notes `.zip` carries
  no calendar data.

## Addendum (schema v30): skip this occurrence

Cancelling a single occurrence of a recurring event. **Not** the same thing as
marking one missed, and the difference is the whole design:

| | missed (v26) | skipped (v30) |
| --- | --- | --- |
| gate | `tracksPresence` opt-in | any recurring event |
| layer | rendering | **membership** |
| `occursOn` | still true | **false** |
| day cache | must **not** invalidate | **must** invalidate |
| revision | `occurrenceRevision` | **`membershipRevision`** |
| `.ics` | exports as an occurrence | exports as an `EXDATE` |

- **A new table, not a `status` column on `calendar_event_absences`.** A
  discriminator would make "a live row means missed" — the invariant three
  surfaces and the backup strand rule are built on — conditional on every
  reader remembering to filter it. The roadmap's floated `status` column
  remains available *within* the absence table for partial/late.
- **The filter lives in `CalendarEvent.occursOn`, and only there.** That is the
  one choke point the day cache, `EventAgenda`, `monthNetFor`, the detail
  sheet's upcoming chips and the date pickers already go through, so a skip
  reaches all of them without any of them knowing skips exist. Reading a static
  facade from the model layer follows the precedent `RecurrenceRule.occursOn`
  already set with `PublicHolidays`.
- **This is the deliberate inverse of the hidden-category filter**, which is
  render-time only, forever: hiding a category changes what you are looking at,
  cancelling an occurrence changes what is there. Both rules must stay stated
  side by side.
- **The `OneTimeRecurrence` gate** keeps a stale row from ever hiding a
  one-time event — cancelling its only occurrence is a delete, offered
  separately.
- **`membershipRevision` cannot ride `occurrenceRevision`.** That revision
  contractually means "the overlay changed, do **not** rescan";
  `UpcomingAgendaView` forwards it into its row memo but never re-runs its
  scan on it. A skip must rescan. It is also load-bearing for the emit itself:
  after a skip `allEvents` is value-equal, so without a bump `Equatable` drops
  the state and the grid keeps drawing an occurrence that no longer exists.
- **Counts are unaffected**, and correctly so: `RecurrenceFormatter.countLabel`
  is elapsed-*period* arithmetic from `startDate`, so a cancelled Week 3 leaves
  Week 4 as Week 4. This mirrors decision 3 of the presence roadmap.
- **`markSkipped` also clears any absence mark on the day** — an occurrence
  that does not exist cannot have been missed, and leaving the mark would
  resurface it the moment the skip is undone.
- **`.ics` needs explicit handling.** `IcsSerializer` queries `event.rule`
  directly so it can drop `retroactive`, which drops the skip filter with it.
  Three sites: `_firstOccurrenceOf` skips cancelled days so `DTSTART` is always
  real; `_exceptionDates` emits an `EXDATE` per cancelled day **only for rules
  that actually emit an `RRULE`** (`_hasRrule`); `_additionalDates` filters
  cancelled days out of the `RDATE` list, since an RDATE that is also an EXDATE
  is noise.
- **UI, two entry points, both routed through the page** so persistence stays
  on one path: "Skip this day" in the detail sheet (returns
  `EventDetailAction.skipOccurrence`, page dispatches with Undo — the sheet
  cannot write, because the occurrence it describes is about to stop existing),
  and a **"Skipped days"** `_PickerTile` in the editor's When zone (editing +
  recurring only) opening `CalendarDatePickerSheet.pickMulti`. The sheet stays
  write-free: `EventEditorSaved.skippedDays` (null = untouched) is diffed
  against the facade by `calendar_page.dart`.
- **`pickMulti` gained `allowEmpty`** (default false, preserving its contract).
  Skips are the first caller where an empty set is legitimate — clearing it is
  how the user restores every occurrence.
- **Backups**: additive key `eventSkips`, version stays 7, standard event-keyed
  strand rule. Getting this wrong is worst of the three: a stale skip does not
  render a wrong colour, it **hides** occurrences of whatever event later takes
  the id. Same reason `EventSkips.resetCache()` in the reset contract matters
  more here than for presence.

## Addendum: day-cell tint layers

The day cell's background is now a general, settings-driven **tint layer**
system rather than a single hardcoded fasting wash.

- `CellTintProvider` / `CellTintResolver`
  (`lib/services/cell_tint_resolver.dart`) mirror `DayBarProvider` /
  `DayBarsResolver`, including the purity contract: `tintFor` runs for every
  visible cell on every rebuild, so static facade probes only — no I/O, no
  BLoC, no recurrence expansion.
- The cell paints at most one **wash** plus one **edge stripe**, both arriving
  with alpha already applied. `CalendarDayCell` stays a dumb painter and never
  learns which source won.
- **Event tint**: exactly one event contributes — the top one by
  `EventAgenda.compareWithinDay`, the same event the panel lists first.
  Averaging a day's colours yields a hue no event on it actually has. Colour
  follows the day-bar rule (`colorValue ?? category.color`) and ignores
  `tintIcon`, like every other grid surface. **Alpha encodes priority**
  (`CalendarColors.eventTintAlphaByPriority`, P1 strongest) — that is the whole
  point of the feature, so the ramp must stay monotonic.
- A missed occurrence keeps the wash it won but fades by `missedEventAlpha`; a
  hidden one cannot claim it at all.
- **Conflict is a user setting**, `CalendarTintConflict { eventWins,
  fastingWins, both }`. Under `both` the winner paints the wash and the
  runner-up a 3px left stripe at `CalendarColors.cellEdgeAlpha` — two stacked
  washes blend into a third colour belonging to neither source. A non-uniform
  `Border` cannot carry a `borderRadius`, hence the `Stack`.
- **Off by default** (`calendar_event_tint`): it repaints most cells on a busy
  calendar and competes with the marker strip the user already reads.
- Adding a source (holiday, money, training block) is implementing
  `CellTintProvider` and picking a band in `CellTintResolver.defaults` — no
  call site changes.

## Addendum: presence adherence, and calendar perf

- **Adherence stats** ship as a pure util, `PresenceAdherence.compute` — see
  the addendum in `docs/presence-tracking-roadmap.md`.
- **`monthNetFor` moved into `CalendarBloc`** and is memoized per month, paired
  with `NoteMoneyLedgerService.revision`. It used to be an un-memoized O(all
  events) scan running from `headerTitleBuilder` on every grid rebuild. The
  revision pairing is load-bearing: the ledger's per-note change stream
  rewrites entries **outside** every handler that invalidates the day cache.
- **`EventDayBarProvider` now sorts by `EventAgenda.compareWithinDay`** and
  `DayBarsResolver.resolve` uses the stable insertion-index sort
  `DaySummaryResolver` already had. Equal-priority stripes previously fell back
  to the resolver's `event:<uuid>` tie-break, so the grid and the day panel
  disagreed about which event was on top. **Visible change**, intended.
- `_buildDayCell` no longer calls `DateTime.now()` and `accentOr` per cell (42×
  a frame); both are hoisted into the grid build. The bar and tint resolvers
  are memoized on `_CalendarViewState`.
- `CalendarColors.moneyPositive` / `moneyNegative` replace the literals
  duplicated across three money surfaces, and `category_editor_sheet.dart` now
  reads `CalendarColors.swatchPalette` instead of its own copy.
