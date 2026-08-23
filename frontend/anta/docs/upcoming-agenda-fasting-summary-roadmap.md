# Upcoming Agenda — Single Fasting Summary Card (Roadmap)

**Status: shipped 2026-08-23.** Planned with the user (Fable) on 2026-08-22,
implemented as designed; both "confirm at kickoff" items shipped on their
recommended defaults (card first in the list and excluded from the entry
count; one combined card per tradition). See "Deviations" at the end for the
handful of places the implementation went past the plan. Grounding:
[upcoming-agenda-redesign-roadmap.md](upcoming-agenda-redesign-roadmap.md)
(the filters sheet, summary chips, `AgendaRow` variants),
[calendar-events-feature.md](calendar-events-feature.md) (Upcoming agenda
section — collapse-fasting as shipped, period-aware runs), and
[fasting-schedule-roadmap.md](fasting-schedule-roadmap.md) (weekday/month
scopes). Load the `anta-context` and `calendar-events` skills before starting.

## The problem, in the user's words

Even with "Collapse fasting periods" on, the agenda still shows one row per
fasting **run** — and the year-round weekly fast deliberately never bridges
(see the period-aware-runs design), so a 90-day window with a Wed/Fri practice
still carries ~26 weekly-fast rows plus the named-fast spans. The user wants
**the option** of exactly **one card** for fasting in the upcoming agenda,
saying "which days, which months, in a smart and short way".

## Decisions locked

| Question | Decision | Why |
| --- | --- | --- |
| Control shape | **A three-way enum replaces the `collapseFasting` bool**: `AgendaFastingDisplay { everyDay, periods, summary }` on `UpcomingAgendaFilters`. The sheet's "Collapse fasting periods" `SwitchListTile` becomes a labelled `SegmentedButton<AgendaFastingDisplay>` ("Every day / Periods / One card") in the Display section, shown only when `FastingCalendar.isEnabled`. Default `periods` (= today's behaviour). | Three mutually exclusive presentations of one thing; a third bool stacked on `collapseFasting` creates nonsense combinations (collapse *and* summarize). Precedent for the segmented control: the event-type sub-choice in the Show section. |
| Persistence | New name-keyed setting `calendar_upcoming_fasting_display` (forward-compatible `fromName`, fallback `periods`). On read, when the new key is **absent**, fall back to the old `calendar_upcoming_collapse_fasting` bool (`true` → `periods`, `false` → `everyDay`); always write the new key. Keep the old `SettingsKeys` constant with a doc note marking it a read-only legacy fallback. | Nobody's configuration resets on update. No migration pass — a read-time fallback, like the schedule's legacy weekday CSV. |
| Card granularity | **One card per enabled tradition**, not per fast. Title/colour/icon/description come from the tradition's `FastingTraditionStyle` exactly as run rows do today. | One card per fast would put a Lent-plus-weekly window right back at multiple cards. Everything needed is already keyed per tradition (`styleOf`, `colorOf`, `iconFor`, `titleOverride`), matching the provider's `'fasting:<tradition>'` keying. |
| Rendering | Through the existing **`_AgendaCard`**, with the entry synthesized in the agenda layer (the span-row precedent) — never a new row style, never a provider change. | The user's standing rule from the redesign: every agenda row is the roomier card; two restylings were tried and reverted. `FastingSummaryProvider` feeds the day panel too and must not learn agenda-only presentation. |
| Badge / summary chips | `fastingDisplay` stays **out** of `restrictiveFilterCount` and the inline summary-chip row. | It condenses rows, it does not hide content — the chips answer "why is something missing", which this never causes. Same reasoning that excludes `collapseRecurring`. |
| Scope of the digest's numbers | **Window-scoped**: first/last **in-window** marked day, in-window marked-day count. No outward walk. | Run rows show a period's true extent because they *are* the period; the digest describes "fasting in this window", and claiming days outside it would make the card disagree with the list it summarizes. |

## Confirm at kickoff (defaults chosen, user may override)

1. **Placement + counting.** Default: the card is emitted as the **first row
   of the list**, above the first month/day header, scrolling with the list
   (no sticky machinery), and it is **excluded from the "N entries" count** —
   it summarizes entries rather than being one. The alternative the user was
   offered (card placed on the first in-window fasting day, counted normally)
   was not chosen but not explicitly rejected.
2. **Lent + weekly in one window.** Default: one **combined** card per
   tradition — its weekday pattern, span and count cover *all* marked days,
   named fasts and weekly days together. The alternative (foreground the named
   fast, ignore weekly days in the numbers) was not chosen but not explicitly
   rejected.

## Design

### A. Model (`lib/models/upcoming_agenda_filters.dart`)

- New enum beside `AgendaEventType`, same shape:

  ```dart
  enum AgendaFastingDisplay {
    everyDay,
    periods,
    summary;

    static AgendaFastingDisplay fromName(String? name) { /* fallback: periods */ }
  }
  ```

- Replace `bool collapseFasting` with `AgendaFastingDisplay fastingDisplay`
  (default `periods`): constructor, `copyWith`, `props`. Do **not** touch
  `restrictiveFilterCount`.

### B. Settings (`SettingsKeys` + `SettingsService`)

- `calendarUpcomingFastingDisplay = 'calendar_upcoming_fasting_display'`,
  default `'periods'`.
- `getUpcomingAgendaFilters`: read the new key; when absent, read
  `calendarUpcomingCollapseFasting` and map `true → periods`,
  `false → everyDay`. `saveUpcomingAgendaFilters` writes only the new key.
- Doc-comment the old constant as legacy read-only fallback.

### C. Pure summary scan (`lib/utils/event_agenda.dart`)

New value type + helper beside `fastingRunsInRange` (which stays untouched —
`periods` mode still uses it):

```dart
class FastingSummary {
  final FastingTradition tradition;
  final Set<int> weekdays;      // DateTime.weekday values actually marked
  final DateTime first;         // first in-window marked day (tap target too)
  final DateTime last;          // last in-window marked day
  final int dayCount;           // in-window marked days
  final List<FastingPeriod> spanPeriods; // distinct multi-day periods present,
                                          // first-seen order (reuse _isSpanPeriod)
}

static List<FastingSummary> fastingSummariesInRange({
  required DateTime from,
  required DateTime to,
  bool Function(DateTime day)? dayFilter,
})
```

- One in-window walk over `FastingCalendar.on(day)` (O(1) memoized), one
  accumulator per tradition, `dayFilter` applied at day level exactly as
  `fastingRunsInRange` does (a filtered-out day is unmarked for every
  summary). Traditions with zero marked days produce nothing. **Never calls
  `CalendarEvent.occursOn*`** — the occursOn-budget tests must stay green.
- Result ordered by `FastingTradition` declaration order (matches `on(day)`).

### D. Row building (`lib/widgets/agenda_list_view.dart`)

- New sealed variant:

  ```dart
  class AgendaFastingSummaryRow extends AgendaRow {
    final FastingSummary summary;
    final DaySummaryEntry entry; // synthesized, see below
  }
  ```

- `buildAgendaRows` gains `List<FastingSummary> fastingSummaries = const []`.
  In summary mode the view passes summaries and **empty**
  `fastingDays`/`fastingRuns` (the three modes are mutually exclusive at the
  call site). Summary rows are emitted **before** the first month/day header,
  one per summary. They are `AgendaFastingSummaryRow`, not `AgendaEntryRow`,
  so the existing `_entryCount` (which counts `AgendaEntryRow`) excludes them
  with no extra logic — call that out in a comment.
- Entry synthesis per summary (agenda-layer only, mirroring `_fastingEntries`):
  `icon`/`color` from `FastingCalendar.iconFor/colorOf`; `description` from
  `styleOf(tradition).description`; `priority` from the style; **title**:
  `titleOverride`, else — when `spanPeriods.length == 1` —
  `periodNameOf(spanPeriods.single, l10n)`, else
  `traditionNameOf(tradition, l10n)`; **subtitle**: see E.
- Renderer: the summary row draws the same `_AgendaCard` (no trailing
  actions — no event), `onTap: () => onDaySelected(summary.first)`. Bottom
  padding 8 like entry rows; the first day/month header after it keeps its
  normal top gap (it is not index 0 — adjust the index-0 padding tests).

### E. The "smart and short" subtitle

Joined with `' · '`, fragments in order:

1. **Weekday pattern** from `summary.weekdays`: all 7 →
   `l10n.recurrenceDaily` ("Daily"); Mon–Fri → `l10n.recurrenceWorkdays`;
   Sat–Sun → `l10n.recurrenceWeekends`; otherwise abbreviated locale weekday
   names joined with `', '` ("Wed, Fri") — derive names via `DateFormat.E`
   anchored on 2024-01-01 (a Monday), the appearance system's existing
   precedent; cache the format per locale on `AgendaListView` like the other
   skeletons. No "&" conjunction — locale-dependent, deliberately avoided.
2. **Span, adaptive**: when `last.difference(first).inDays <= 62`, the exact
   range `AgendaListView.rangeLabel(first, last)` ("Mar 2 – Apr 18"); when
   wider, a month range "Aug – Dec" via a per-locale cached `DateFormat.MMM`
   (same-month degenerate case: single month name). Make 62 a named private
   constant with a one-line why (two months: exact dates stay readable up to
   that, months are the useful unit beyond).
3. **Count**: the existing `upcomingFastingSpanDays(dayCount)` plural.

Examples the implementation should reproduce: `"Wed, Fri · Mar 2 – Apr 18 ·
14 days"`, `"Daily · Nov 15 – Dec 24 · 40 days"`, `"Wed, Fri · Aug – Dec ·
44 days"`. Optional garnish (only if trivially clean): when
`spanPeriods.length >= 2`, nothing extra — the tradition-name title already
signals plurality; do **not** add a "+N" fragment without a proper l10n key.

### F. View wiring (`lib/widgets/upcoming_agenda_view.dart`)

- State gains `List<FastingSummary> _fastingSummaries = const []`.
  `_recomputeFasting` becomes a three-way switch on `filters.fastingDisplay`,
  each branch zeroing the other two lists; the query `dayFilter` threads into
  all three (`_fastingMatches`, unchanged).
- `didUpdateWidget`: the fasting-only branch's test becomes
  `o.showFasting != n.showFasting || o.fastingDisplay != n.fastingDisplay`.
  No event rescan for a display-mode change.
- `_rowsFor` memo: add `_rowsForFastingSummaries` identity key alongside the
  existing days/runs keys; pass `fastingSummaries:` into `buildAgendaRows`.

### G. Filters sheet (`lib/widgets/agenda_filters_sheet.dart`)

Replace the "Collapse fasting periods" `SwitchListTile` with, under the same
Display section and only when `FastingCalendar.isEnabled`: a row label
(`upcomingFastingDisplayTitle`) + `SegmentedButton<AgendaFastingDisplay>` with
the three options, compact style matching the event-type control. Draft
copies below; `upcomingCollapseFasting` becomes unused — remove it from all
three ARBs.

### H. Localization (en/de/ro together, then `flutter gen-l10n`)

Reused: `recurrenceDaily`, `recurrenceWorkdays`, `recurrenceWeekends`,
`upcomingFastingSpanDays`, `fastingTradition*`, the `periodNameOf` strings.
Removed: `upcomingCollapseFasting` (×3). New (drafts — finalize at
implementation):

| Key | en | de | ro |
| --- | --- | --- | --- |
| `upcomingFastingDisplayTitle` | "Fasting rows" | "Fasten-Zeilen" | "Rânduri de post" |
| `upcomingFastingDisplayEveryDay` | "Every day" | "Jeder Tag" | "Fiecare zi" |
| `upcomingFastingDisplayPeriods` | "Periods" | "Zeiträume" | "Perioade" |
| `upcomingFastingDisplaySummary` | "One card" | "Eine Karte" | "Un card" |

Check `untranslated.txt` after gen-l10n.

## Testing (standing permission; extend the existing suites)

- `test/utils/event_agenda_test.dart` (`fastingSummariesInRange` group, reuse
  the existing `FastingCalendar.configure` setUp/tearDown pattern):
  weekday set / first / last / dayCount for a sparse Wed-Fri config
  (`weekdayScope: allFasts`); a contiguous Nativity window → weekdays = all 7
  present in range, `dayCount == 40` when fully in window (or the clipped
  count — window-scoped!); `spanPeriods` lists the named fasts present once
  each; `dayFilter` that matches nothing → empty; **zero `occursOn` calls**.
- `test/models/` (or wherever `UpcomingAgendaFilters` codec lives —
  settings-service level tests don't exist for it, so model-level):
  `AgendaFastingDisplay.fromName` fallback; `copyWith`/props include the enum.
- `test/widgets/agenda_rows_test.dart`: summary rows come **first**, before
  any month header; they are not `AgendaEntryRow` and the header counts /
  entry totals ignore them; title rule (override > single span period >
  tradition); subtitle exact-vs-month-range adaptivity across the 62-day
  threshold; per-day and per-run modes byte-identical to today when
  `fastingSummaries` is empty.
- `test/widgets/upcoming_agenda_view_test.dart`: switching
  `fastingDisplay` re-runs no event scan (`debugOccursOnCalls == 0` across
  the mode change, the existing counting pattern).
- Settings fallback: a stored `collapse_fasting = false` with the new key
  absent loads as `everyDay` (test at whatever level the suite reaches —
  model-level mapping helper is acceptable if the read stays inline).

## Verification

`flutter gen-l10n` → `dart analyze lib` (zero issues) → full `flutter test`
(currently 592 + 2 skipped; all must pass). On-device visual pass afterwards:
the segmented control in the sheet, the card at the top of a real Lent
window, dark theme.

## Docs sync (same change)

- This file → shipped, with a deviations section if any.
- [calendar-events-feature.md](calendar-events-feature.md): the Upcoming
  agenda collapse-fasting bullet becomes the three-mode story.
- `.claude/skills/calendar-events/SKILL.md`: the "Collapse fasting" sentence →
  `AgendaFastingDisplay`, summary card rules (per tradition, top of list,
  excluded from entry count, window-scoped numbers).
- `COPILOT_CONTEXT.md`: the matching `collapseFasting` sentence.

## Change-set (ordered)

1. Model: `AgendaFastingDisplay` + `fastingDisplay` field (A).
2. Settings: new key + legacy-bool read fallback (B).
3. `event_agenda.dart`: `FastingSummary` + `fastingSummariesInRange` (C).
4. `agenda_list_view.dart`: `AgendaFastingSummaryRow`, `fastingSummaries`
   param, entry synthesis + subtitle formatting (D, E).
5. `upcoming_agenda_view.dart`: three-way `_recomputeFasting`, memo + rescan
   keys (F).
6. `agenda_filters_sheet.dart`: segmented control (G).
7. ARB ×3 → `flutter gen-l10n` (H).
8. Tests → `dart analyze lib` → `flutter test`.
9. Docs sync.

No schema change, no migration, no backup-format change. One new settings
key; one retired to read-only legacy status; one l10n key removed, four added.

## Deviations (as shipped, 2026-08-23)

Everything above shipped as written except these.

1. **The month range carries the year when the window crosses one.**
   `AgendaListView.monthRangeLabel` uses the planned per-locale
   `DateFormat.MMM` only while both ends share a year; across years it falls
   back to a second cached `DateFormat.yMMM`. A window may reach
   `EventAgenda.maxRangeDays` (366), so a bare "Aug – Aug" was reachable and
   says nothing — and the month-header row already resolves exactly this
   ambiguity with its `showYear` flag. Locale data, not a new ARB key, so the
   "no fragment without a proper l10n key" rule is untouched. The
   single-month collapse tests year **and** month, never the formatted string.
2. **Single-day fasts contribute a weekday but never a `spanPeriod`.** Not a
   design change — a consequence of reusing `_isSpanPeriod` — but worth
   recording, because it is visible: a September window whose only marks are
   the Wed/Fri rule plus the Exaltation of the Cross (a Monday in 2026) reads
   "Mon, Wed, Fri", and its card falls back to the tradition's name because no
   named multi-day fast is present. That is the intended reading: the pattern
   describes days the user fasts, the title names the fast when there is one.
3. **The settings fallback got a service-level suite**, not the model-level
   mapping helper the plan allowed as a fallback:
   `test/services/upcoming_agenda_fasting_display_test.dart` drives the real
   `SettingsService` over an in-memory database and covers both legacy
   mappings, the new key winning over a stale boolean, a newer build's value
   degrading, and — the one a migration would have destroyed — that saving
   leaves the legacy row untouched.
4. **No index-0 padding tests needed adjusting**; the row tests are pure and
   assert row *order* and types, not padding. The summary card's own padding
   (bottom 8, no top special-case) is what keeps the first header's normal gap.
5. **One suite beyond the plan**:
   `test/widgets/agenda_filters_sheet_test.dart` covers the segmented control
   itself — absent while fasting is inert, three labels laid out without an
   exception, a pick surviving Apply, and Reset returning to `periods`. It
   stands in for the on-device visual pass on the one layout most at risk
   (three labels in one segmented row; they ellipsize like the event-type
   control above them).

Test counts: 592 + 2 skipped before, **632 + 2 skipped** after.

## Follow-on — the card gained a drill-down (2026-08-23)

Shipped hours later, with the holiday summary card that reused this design.
The fasting card as planned here was a dead end: tapping it jumped to
`summary.first` and there was no way to see the forty days it stood for.

It now carries a trailing `IconButton` opening the shared
`AgendaDayListSheet` (`lib/widgets/agenda_day_list_sheet.dart`), which lists
its marked days with each day's period and regime and focuses the tapped one.
Two consequences for this document:

- **`FastingSummary` gained `days`** — the marked days themselves, not just
  `dayCount`. The card claims a number and the sheet lists the days, so
  re-walking the window in the sheet would drop this scan's `dayFilter` and
  quietly disagree with the card. `_OpenFastingSummary` now accumulates the
  list and `dayCount` **is** `days.length`, so the two cannot drift.
- **The sheet's scope is the card's scope** — the same window-scoped rule the
  "Decisions locked" table already set for the digest's numbers, applied one
  level down.

See `calendar-events-feature.md` for the holiday half and the shared sheet's
rules.
