# Calendar — the review (2026-10-26)

**Status: PLANNED 2026-10-26 (Fable 5.1), as the owner's "resources for a
calendar review": ten sessions B1–B8 on the same runner as the sync
review, run after it (sync review D6 A). The scope is §1's default until
the owner states one (§5 D1). Night 3 is complete: B1, B2, B3a, B3b, B4a and
B4b ran on 2026-10-28 and filed C1–C82 (§3) — C44, C45, C46 and C58 are the
four H rows of this review, and the last of them is C46's category twin, so
B7 fixes the pair with one seam. **B5 ran last on 2026-10-28 and filed C83–C111**
(four M, no H), among them C85 — C71's page-side twin, the review's second pair
for B7 to fix with one seam — which closes night 3 at 111 ids: five H once C83 was
lifted on 2026-10-28 (§5). Night 4 (2026-10-28) is B5b — D1 flipped to C, the
alert surfaces — then B6, B7, the sync record's A10 and B8; B8 writes the
closing status header.** The calendar is
23,700 lines in 57 files and changed in four reworks this October — the
overview list (`c4f5697` … `f3e0bc8`), the category alerts and digests
(`038b6d4`, v42), the conformity and snackbar pass, the QA rework's five
app fixes (`945c0c3`) — and the sync engine now reloads its eleven tables
under a loaded page (`docs/cloud-sync-phase-02-own-space.md` §3.5). Each
rework was reviewed in its slice; none was read whole afterwards.

The mechanics are the sync review's §0 (`docs/cloud-sync-phase-02-review-2026-10-26.md`:
the runner, the kickoff, what every session does, the reviewer and fix
briefs, the ledger shape, the probe rule). This record carries only what
differs. Ids here are `C1`, `C2`, …; the fix session is B6 for B1–B3b's
files and B7 for B4a–B5's.

## Contents

0. How to run this — what differs from the sync review
1. Scope
2. The sessions B1–B8
3. The ledger
4. Must not change
5. Decisions (D1–D5)
6. Budget

---

## 0. How to run this

```
tool\review\overnight.ps1 -Sessions B1,B2,B3a,B3b,B4a,B4b,B5     # night 3: the reviews
tool\review\overnight.ps1 -Sessions B5b,B6,B7,A10,B8 -Commit             # night 4: B5b (the alert surfaces), the fixes, the sync record's A10, the gate
```

The kickoff names this record. Differences from the sync review's §0:
the diff is not one range — a reviewer reads the files as they are and
`git log --since=2026-10-01 -- <file>` for what moved this month; the
skills are `calendar-events` and `anta-context`, `calendar-ui` and
`ui-language` for a sheet, `flutter-principles` for a hot path; the gate
in a fix session adds `qa pass calendar` and `qa pass alerts` (B8 runs
them; a fix session runs the unit suite only); a golden may change only
when a ledger id says the screen changes, and the fix session re-renders
it on purpose and says so. A1a–A5 of the sync review are not
prerequisites; A3b (the calendar bindings) is the only sync session a
calendar reviewer reads the ledger of, to not repeat it.

---

## 1. Scope

**Default (D1 A): correctness and regression, read-only reviewers, fixes
gated.** The questions: does every surface show the rows the services
hold, after every write path and after a sync reload; does the
recurrence, presence, skip and alert math hold at the edges (DST, leap
days, month ends, all-day, the past); do the October reworks' decisions
(the overview's D1–D33, the digests' D1–D23, the QA rework's slice 6a)
still hold together; where does a page rebuild or re-query more than it
must.

**Out by default:** the alert surfaces — `alarm_page.dart`,
`android_alert_gateway.dart`, `alert_scheduler.dart`, the alarm fork —
reviewed whole on 2026-09-21 (74 findings) and redesigned through
2026-10-10 (D1 C adds them); visual conformity to the UI language (D2 B
adds a `design-reviewer` per surface group); perf measurements beyond
what a reviewer notes in passing (the perf roadmap is CLOSED, the
benchmarks in the suite are the guard).

---

## 2. The sessions B1–B8

Every block: **Goal** · **Files** · **Read** · **Questions** · **Agents** ·
**Writes**, as the sync review's §2. Every reviewer: "report by turn 60".

### B1 — Data, services and the recurrence engine (Opus lead; `reviewer`)

**Goal.** The rows and the math under every surface. **Files.**
`lib/services/calendar_event_service.dart`, `lib/database/daos/calendar_event_dao.dart`,
`lib/models/calendar_event.dart`, `lib/models/recurrence_rule.dart`,
`lib/services/event_occurrence_service.dart`, `event_presence_service.dart`,
`event_skip_service.dart`, `event_template_service.dart`,
`public_holiday_service.dart`, `day_summary_resolver.dart`; the suites
beside them under `test/services/` and `test/database/` (by name).
**Read.** `calendar-events` skill: Hardest constraints; Recurrence,
dates, times; Presence, skips, occurrences; Holidays and fasting;
`docs/calendar-events-feature.md` §3 (recurrence) and §5 (persistence),
by subsection. **Questions.** (1) Recurrence at the edges: a series
across a DST day (local midnight plus a `Duration` is an hour off —
`DateTime(y, m, d, 0, minutes)` is the rule), the until bound inclusive
or not, count and `countStyle`, `retroactive`, 29 February yearly, the
31st monthly, weekly across a year boundary, `yearBoundsOf`. (2) Day
keys: a skip or a presence day at a DST boundary, a skip of a day the
series does not occur on, a presence day of a deleted event, the
`eventId|dayEpochMs` key the sync binding reproduces. (3) After v43:
every read path filters tombstones; the ten services' `reload()` under
the sync hooks in the recorded order — a cache read while its service
reloads; `tombstoneAll` and the alert registrations. (4) Templates:
applying one keeps or drops recurrence and alerts as the record says. (5)
Holidays: validity years, substitute days, a removed built-in restored;
the fasting engine's dates for 2026 and 2027 against a known calendar
(spot check). (6) Presence adherence and the missed display's math. (7)
Digests: the planned and delivered states, a month with no events, a
device-local delivery flag against a synced row. **Agents.** One
`reviewer`. **Writes.** Ledger ids; session log.

### B2 — The bloc and the grid (Opus lead; `reviewer`)

**Goal.** The state under the month grid: caches, revisions, races, the
restore after a sync reload. **Files.** `lib/bloc/calendar/calendar_bloc.dart`,
`calendar_event.dart`, `calendar_state.dart`, `lib/pages/calendar_page.dart`
(the state paths and this month's hunks), `lib/widgets/calendar_day_cell.dart`,
`calendar_day_rail.dart`, `calendar_day_bars.dart`, `calendar_bottom_panel.dart`,
`lib/models/calendar_grid_filters.dart`, `lib/widgets/calendar_filter_sheet.dart`.
**Read.** `calendar-events` skill: Bloc, caches, revisions; Grid and
cells; Grid filters and presets; Panel, agenda, FAB; `flutter-principles`
(hot paths); QA rework record §4 slice 6a (the restore rule).
**Questions.** (1) `eventsForDay` and `monthNetFor` invalidated on every
write path and on `ExternalCalendarChange`; the in-place reload keeps
the mode, the filters and the drill-down picked since init (a
pointer-down on the bar counts; an early filter change replays onto the
stored filters). (2) Generation guards: a month swipe racing a reload, a
filter change racing a load, the cross-event race the navigation round
fixed. (3) The panel's restore and persistence, the keyboard-coupled
grid motion, the FAB's states. (4) Rebuilds per month swipe and per day
tap — what rebuilds that need not (`RepaintBoundary`, `const`,
selectors); the suite's existing counts as the yardstick. (5) Filters:
persisted merged, a preset applied over a live filter, the summary text.
(6) The cell styles per theme (solid, fade, outline) and the stripe —
correctness only. **Agents.** One `reviewer`. **Writes.** Ledger ids;
session log.

### B3a — The overview page (Opus lead; `reviewer`)

**Goal.** The 3,951-line page read by region: the period control, the
modes, the day list, the totals, the saved views, presence. **Files.**
`lib/pages/calendar_overview_page.dart`, `lib/widgets/agenda_period_nav.dart`,
`agenda_year_scroll.dart`, `agenda_year_pager.dart`, `agenda_month_grid.dart`,
`agenda_year_grid.dart`, `overview_options_sheet.dart`, `overview_view_sheet.dart`,
`lib/services/overview_view_service.dart`. **Read.**
`docs/calendar-overview-list-roadmap.md` §2 (D1–D33, by the decisions
named) and its traps; `calendar-events` skill: Overview, drill-down,
years. **Questions.** (1) Period math: ranges, stepping, home, the year
mode's scroll (D26–D30) and the five traps the record lists. (2) Saved
views (v41): round-trip, the default view, a view naming a deleted or
hidden category. (3) The presence button (D31) and the hidden missed
display (D32) in every state. (4) Totals per category under filters and
the query post-filter. (5) The detail sheet over the list and the sheet
guard. (6) The page's cost on a period change: `setState` storms, work
done for rows off screen. **Agents.** One `reviewer`. **Writes.** Ledger
ids; session log.

### B3b — The agenda, the day list and their stores (Opus lead; `reviewer`)

**Goal.** The scans and indexes every list reads. **Files.**
`lib/widgets/upcoming_agenda_view.dart`, `agenda_list_view.dart`,
`agenda_filters_sheet.dart`, `agenda_day_list_sheet.dart`, `agenda_day_list_rows.dart`,
`day_summary_panel.dart`, `day_timeline_view.dart`, `lib/models/agenda_day_list.dart`,
`upcoming_agenda_filters.dart`, `lib/utils/event_agenda.dart`,
`agenda_month_store.dart`, `agenda_day_list_index.dart`. **Read.**
`calendar-events` skill: Panel, agenda, FAB; `docs/calendar-events-feature.md`
addendum "Upcoming agenda"; `docs/calendar-overview-list-roadmap.md` §3
(the day list's rows and extents). **Questions.** (1) `compareWithinDay`
ties, all-day against timed, `yearBoundsOf`; the search across events
and its debounce (the stale-keystroke rule). (2) The month store's
invalidation after a write and after a sync reload; the index's batched
resolution and exact extents. (3) The day list's modes (list, month,
year drill-down) and `PopScope`. (4) The timeline's overlap layout. (5)
Presence from rows. **Agents.** One `reviewer`. **Writes.** Ledger ids;
session log.

### B4a — The event editor and its dates (Opus lead; `reviewer`)

**Goal.** The write path of every event. **Files.**
`lib/widgets/event_editor_sheet.dart`, `event_repeat_sheet.dart`,
`event_look_sheet.dart`, `event_description_sheet.dart`, `event_detail_sheet.dart`,
`calendar_date_picker_sheet.dart`, `lib/controllers/event_sheets_flow.dart`,
`lib/utils/sheet_guard.dart`, `lib/constants/event_title.dart`. **Read.**
`calendar-events` skill: Event editor and sub-sheets;
`docs/calendar-events-feature.md` §6.3–§6.5; the status headers of
`docs/event-editor-redesign-roadmap.md` and
`docs/event-description-editing-roadmap.md` (its deviations block).
**Questions.** (1) The validation rules of §6.4 and the save path: two
HLCs per save (the readiness record left it as found — still so?), a
recurrence change on an event with skips or per-occurrence descriptions
(orphans), the semantics of editing one occurrence. (2) The dates sheet:
three views over one set, DST, the multi mode. (3) The header stacking
and the description's minimum height (`945c0c3`) at text scale 2.0. (4)
The description's editor seam (the markdown engine inside a sheet: the
five traps the description record lists). (5) The unsaved-changes dialog
and the sheet guard when a sync reload lands under an open editor: on
save the user's version wins (LWW) — say so and check it. **Agents.** One
`reviewer`. **Writes.** Ledger ids; session log.

### B4b — Alerts in the editor, the quick alarm, templates, categories (Opus lead; `reviewer`)

**Goal.** The sheets around an event, and the two services behind the
alerts and digests (the small files are read whole). **Files.**
`lib/widgets/alert_editor_sheet.dart`, `alert_offset_sheet.dart`,
`alert_sound_sheet.dart`, `alert_type_row.dart`, `event_alert_badge.dart`,
`quick_alarm_sheet.dart`, `lib/utils/alert_offset.dart`, `quick_alarm.dart`,
`lib/widgets/event_template_editor_sheet.dart`, `event_template_picker_sheet.dart`,
`category_picker_sheet.dart`, `category_editor_sheet.dart`,
`lib/services/event_alert_service.dart`, `event_digest_service.dart`,
`category_service.dart`. **Read.** `calendar-events` skill: The alert
sheet and the quick alarm; Category alerts and digests; Categories and
icons; `docs/category-alerts-and-digests-roadmap.md` D1–D23 (by the
decisions named). **Questions.** (1) `effectiveFor`: an inherited alert
with a per-event opt-out, an event moved between categories, a category
alert deleted while events inherit it. (2) The offset math for all-day
events and for an event already past (the countdown after a save). (3)
The quick alarm's defaults and the category it files under. (4)
Templates: alerts in a template, a template whose category was deleted.
(5) The category editor at scale (the scaling roadmap's rules), built-ins
hidden never deleted, the name limit. (6) Digests: the notification's
tap target (the overview) and a digest for a hidden category. **Agents.**
One `reviewer`. **Writes.** Ledger ids; session log.

### B5 — Settings, appearance, the categories page, the palette, the header, export (Opus lead; `reviewer`)

**Goal.** Every setting read once and reflected live; the pages that
manage the calendar. **Files.** `lib/pages/calendar_settings_page.dart`,
`calendar_appearance_page.dart`, `lib/widgets/calendar_appearance_preview.dart`,
`lib/models/calendar_appearance.dart`, `lib/pages/calendar_categories_page.dart`,
`lib/services/calendar_palette_service.dart`, `lib/widgets/calendar_header_menus.dart`,
`lib/controllers/calendar_export_controller.dart`, `lib/utils/ics_serializer.dart`,
`lib/pages/alerts_page.dart` (the hub's list and digests group only).
**Read.** `calendar-events` skill: Settings; Categories and icons;
Alerts hub, navigation, export;
`.claude/skills/calendar-events/references/colour-palette.md` (the
invariants). **Questions.** (1) Every setting through `SettingsService`
and `SettingsKeys`; a setting changed on the appearance page reaches the
grid without a restart; the Start choices' stacking (`945c0c3`). (2) The
palette's custom swatches round-trip and the one picker. (3) The
categories page: archive, hide, restore, the per-category alerts group.
(4) `.ics`: recurrence, all-day, time zones, escaping, a description
with markdown. (5) The header menus' view and period state against the
bloc. (6) The hub's digests group, and the ring-on-every-device rule
after sync (readiness D11) as the hub states it. **Agents.** One
`reviewer`. **Writes.** Ledger ids; session log.

### B5b — The alert surfaces and the scheduler (Opus lead; `reviewer` ×2)

**Goal.** The file six sessions pointed at and the surfaces that ring:
does an armed alert survive a sync reload, and does what the hub and the
alarm page show match what the OS holds. D1 → C (§5, 2026-10-28).
Read-only; its ids go to B7. **Files.** Two disjoint halves, each its own
`reviewer` (the B4b/B5 lesson: over about six files a block runs as
halves, each given the other's list as a no-go area). *Half 1 — the plan
and the registry:* `lib/services/alert_scheduler.dart` by symbol only
(`digestArmSignature` :118, `reconcileAllQuietly` :351, `hubEntries` :572,
`digestEntries` :709, `_assignOsIds`, `reconcileAll(sync)`),
`lib/utils/digest_planner.dart`, `lib/services/event_digest_service.dart`
(the reload under the hooks), `lib/bloc/calendar/alert_skip_action.dart`,
`lib/pages/calendar_settings_page.dart` at :202, :960, :991, :1220, :1338
only. *Half 2 — the surfaces:* `lib/pages/alarm_page.dart`,
`lib/controllers/alert_ring_controller.dart`, `lib/services/alert_gateway.dart`,
`lib/services/android_alert_gateway.dart` by section (arm/cancel/replay,
channels and sound, the full-screen intent, boot),
`lib/widgets/event_detail_sheet.dart` alert rows, presence rows and
`build` only (B3b's unread corner). **Read.** The `calendar-events`
skill: Hardest constraints; The alert sheet and the quick alarm; Alerts
hub, navigation, export (the registry identity, the digest rules, "never
arm over a ringing or due entry"); `docs/alert-surfaces-redesign-roadmap.md`
§3.3 States, §3.6 Data, §4.1 Must not change, §4.2 Deliberately changes;
`docs/category-alerts-and-digests-roadmap.md` D1–D23 by name; the
half-resurrection clause, phase record §3.4 (4). **Questions.** Half 1:
(1) B1's 7 — a digest's planned and delivered states across a sync
reload: `digestEntries` planned fresh against `_assignOsIds` and
`digestArmSignature`, a delivered digest re-planned, a row the reload
tombstoned mid-pass. (2) B2's — the Skip notice's `ToggleEventAlert` on an
inherited alert (`alert_skip_action.dart:50`): which row it writes and
whether `effectiveFor` still lists it. (3) B5 half 1's — the four
`reconcileAllQuietly` calls re-arm only on an arm-signature move;
`scheduleTestAlarm` beside a live ring; the reset's `setAlertDefaultAllDay`
+ `EventAlerts.configureDefaultDayMinute` against standing digests. (4) B5
half 2's — `hubEntries()` registry-truth versus `digestEntries()` planned
fresh: the one place the hub answers readiness D11 two ways; say which the
record sanctions and whether a row can show an arm this device never made.
(5) An event freshly stamped from a template: what the quiet pass plans
before the editor's alerts land. Half 2: (6) The ring page's states against
§3.3 and the `a0a82ba` stale-launch-intent replay: the keyguard path,
`unlock()` before stop, Keep one-way, Stop narrowing only. (7) Arm/cancel
idempotence: a tombstone, a skip, a presence mark and a category opt-out
each cancel exactly their rows; the Removed·Undo pair; a snooze a v41
build armed. (8) The release shrinker's `ic_alert` keep rule and its guard
test still hold. (9) Sound and volume: follow phone volume, the 0.3 floor,
the three channels' ids and importance unchanged. (10) The detail sheet's
alert and presence rows for an inherited alert and a digest, and the
presence row's write path. **No-go.** Half 1 never opens the gateways, the
alarm page or `packages/alarm/`; half 2 never judges the planner or the
registry's rules; neither restyles (D2 A), reads `alert_scheduler.dart`
end to end, adds a test, or touches `MonthYearPickerSheet` (routed to a
later review). **Brief.** The sync review's §0.4 with this record's §4;
CONFIRMED only through a tool result; ids continue from C111; fix session
B7 for every id (a B5b id B7 cannot finish is `→ deferred: owner`); report
by turn 60. **Agents.** Two `reviewer`s, one per half, in parallel.
**Writes.** Ledger ids; session log; nothing else — D1 is already C in §5.

### B6 — Fix pass I: data, bloc, grid, overview, agenda (Opus lead; `implementer`, `reviewer`)

**Inputs.** The B6 ids (B1, B2, B3a, B3b) whose severity is not `—`.
**Brief** per the sync review's §0.5 with this record's §4; the
implementer reads the record sections the ids cite; `calendar-events`,
`drift-migrations` if a DAO changes (no migration without the owner).
**Order.** H, then M, then co-located L (D4 A); over about twelve ids, two
implementer runs (data and bloc first, then overview and agenda), the
second after the first's gate. **Then** the medium-effort reviewer on
the diff; the unit gate; the commit under `-Commit`. **Writes.** `→` on
every id; session log.

### B7 — Fix pass II: the editor, the alert sheets, templates, categories, settings (Opus lead; `implementer`, `reviewer`)

**Inputs.** The B7 ids (B4a, B4b, B5, and B5b — the alert surfaces; a B5b
id this session cannot finish is `→ deferred: owner`). **Brief** as B6, with `calendar-ui`
and `ui-language` beside `calendar-events` (a sheet fix keeps the sheet's
anatomy: the row primitives, the metrics, the semantics ids); `l10n` for
any string, three ARBs together. **Then** the reviewer, the unit gate,
the commit. **Writes.** As B6.

### B8 — The gate, the device pass, the docs (Sonnet lead; `qa-runner`, `docs-writer`)

**Steps.** (1) `dart analyze lib test test_driver`; `flutter test` whole;
`flutter gen-l10n` + `untranslated.txt` empty if an ARB changed; the
goldens: byte-equal except the ones a ledger id re-rendered on purpose
(named in the session log). (2) One `qa-runner`: `qa fleet install
--build`, then `qa pass calendar -d emulator-5556`, `qa pass browser -d
emulator-5556` (the sync record's A10 touches the vocabulary DAO and both
repositories) and `qa pass alerts -d emulator-5556`, each a foreground call with a ten-minute tool timeout —
never in the background: a print-mode session cannot be woken (the sync
record's §0.3 item 8; the brief says it overrides the agent's step 4) —
one `--only` rerun per red; a flow red that was green in
the sync review's A9 is a ledger id `→ deferred: owner` and the session
ends `PARTIAL`. (3) The lead writes, `docs-writer` places: this record's
status header; one dated entry at the end of
`.claude/skills/calendar-events/references/context-log.md` ("Calendar
review 2026-10-26: what changed and why"); a `SKILL.md` rule line only
if a rule changed; an addendum line in `docs/calendar-events-feature.md`
pointing here when a behaviour changed. (4) Under `-Commit`: one docs
commit. **Writes.** Session log; the status header.

---

## 3. The ledger

### 3.1 Session log

- **B1 — 2026-10-28, PARTIAL.** One `reviewer` (Opus 5.5, high) on the
  ten files plus the four questions 5 and 7 need
  (`fasting_calendar.dart`, `fasting_schedule.dart`, `public_holidays.dart`,
  `event_digest_service.dart`). Defaults taken with the owner asleep: D1 A
  (correctness and regression, the alert surfaces out), D2 A (no
  `design-reviewer`). **C1–C13 filed**, all to B6; two M, eleven L, no H.
  Questions 1 and 5 were verified end to end through a snapshot probe
  (recurrence edges: monthly-31, yearly Feb-29, weekly interval across a
  year boundary, the inclusive `endDate` bound, `retroactive` for all four
  rules, and `candidateDaysIn`'s superset property over 10 rules × 4
  anchors × 2 scopes × 4 windows with zero failures; both Easters, Great
  Lent, the Apostles' fast, Dormition and Nativity for 2026 and 2027, the
  UK substitutes and the US observance). DST is structurally out of reach
  in these files — every date is `DateTime.utc` and the consumers
  normalise before any `add` (read, not probed). **Left open:** question 7's
  planned/delivered digest states, `includeEmpty` and the device-local
  delivery flag against a synced row (they live in `alert_scheduler.dart`,
  which D1 A puts out of scope — the owner's call whether B5 or a D1 C
  session takes them); question 5's "a removed built-in restored" (read,
  not exercised); question 6's `CalendarMissedDisplay`, which is B3b's
  file. The reviewer's first run hit its 80-turn limit before reporting
  and was resumed for the report — the next calendar reviewer gets a
  narrower file list or two sessions. A3b's R76–R86 were read and not
  re-filed; C3 and C4 are a different defect in `R86`'s file, not a
  restatement. Tree clean after the reviewer (`git status --short` empty);
  its probe lived only in a `git archive HEAD` snapshot, `subst` undone.

- **B2 — 2026-10-28, DONE.** One `reviewer` (Opus 5.5, high) on the ten
  files; all six questions answered, none left open. Defaults taken with
  the owner asleep: D1 A (correctness and regression — question 6 read for
  correctness only, no visual findings) and D2 A (no `design-reviewer`),
  B1's letters unchanged. **C14–C26 filed**: three M, ten L, no H;
  C14–C15 and C17–C26 to B6, C16 to B7 because its fix lives in B4a's
  `event_sheets_flow.dart`. Questions 1, 2 and 3 came back clean and the
  reasoning is kept here because it is the yardstick for the next reader.
  Invalidation: every write path invalidates in the emit's synchronous turn
  after its last await (create `:894`, update `:934`, delete `:972`, skip
  `:1117`, unskip `:1144`, filters `:853`, load `:690`, external `:734`,
  presence gated on `hasOccurrenceAxis` `:1053`), and the three inputs no
  handler can see — the holiday revision, `today` under `hideEnded`, the
  ledger revision under `moneyOnly` — ride `_syncGenerations`, which runs
  before every cache read in both `eventsForDay:330` and `monthNetFor:511`;
  the writes reachable from the page that bypass the bloc are covered too
  (`_removeHoliday` rides `PublicHolidays.revision`, `FastingCalendar.configure`
  bumps `_revision` so the page's `_outputGeneration` drops its three
  output caches, `_openSettings:1480` dispatches an unconditional
  `LoadCalendarEvents` for the category-delete reassignment). Guards:
  `_loadGeneration` is re-checked after every await that precedes an emit
  on both reload paths (`:676`, `:681`, `:685`, `:730`, `:733`) and
  `_externalChangeBeforeLoaded:253` closes the one case a bump cannot (a
  change arriving before the first load emitted — a bump there would make
  the first load lose its own race and nothing would emit); six
  interleavings were walked with no window where a stale list wins; the
  write handlers need no generation of their own because every
  `upsert`/`deleteById` reassigns `service.events` to a fresh
  `List.unmodifiable`, which `sameGridInputs`' `identical` check reads
  (pinned by `calendar_bloc_allevents_identity_test.dart`). Panel: the
  restore, the three pick flags, `_replayOnto` and the write-back match
  slice 6b as written, the anchor rules at `_syncAnchor:177` hold, and the
  keyboard coupling is sound because `_KeyboardInsetProbe` sits above the
  scaffold so its write reaches `_gridCollapsed`'s builder in the same
  frame. The grid's *own* filter restore does not (C15) — slice 6b fixed
  the panel and left the page. **Read and not re-filed:** A3b's R76–R86;
  none of C14–C26 restates R78 or R86. **Not reached:** no device or render
  check, so C14, C16 and C17 stay PLAUSIBLE on their visible symptom (each
  is one screenshot from CONFIRMED); C15's timing window was read, not
  reproduced (it needs the held-read harness
  `calendar_bottom_panel_mode_test.dart` already has); whether the Skip
  notice's `ToggleEventAlert` takes the own-only branch for an inherited
  alert (`alert_skip_action.dart:50` — alert surfaces out under D1 A, and
  `_onToggleEventAlert:1174`'s own-only `EventAlerts.alertsFor` read would
  silently no-op if it does not); what the day-list sheet does with a
  drill-down mode that changed under it while open (B3b's file). Two
  suspicions were dropped after checking: `CalendarGridFilters.encode`'s
  comma join of `hiddenCategoryIds` is safe because category ids are UUID
  v4 (`category_service.dart:261`), and `CalendarFilterSummary.facetsOf`
  yields exactly the 14 axes `activeCount` counts, so the app-bar badge and
  the chip row cannot disagree. Gate, run read-only by the reviewer:
  `dart analyze lib` clean, the 17 bloc/model/util suites `+149` green, the
  13 calendar widget suites `+306` green. No probe was needed, so no
  snapshot was created and none had to be removed; tree clean after the
  reviewer (`git status --short` shows only this record).

- **B3a — 2026-10-28, DONE.** One `reviewer` (Opus 5.5, high) on the nine
  files and all six questions. Defaults taken with the owner asleep: D1 A
  (correctness and regression, the alert surfaces out), D2 A (no
  `design-reviewer`, so no visual finding is filed — question 3's states
  were read for behaviour only). **C27–C34 filed**, all to B6; two M, six
  L, no H. **Verified end to end:** question 1 — every date in
  `overview_period.dart` is `DateTime.utc` (`_today` from
  `EventAgenda.dateOnly`, `event_agenda.dart:973`), so the local-midnight
  `add` trap is structurally out of reach, and `resolve`, `stepped`, the
  codec, `followingToday` and the leap and year-boundary cases are pinned
  by `overview_period_test.dart`'s 29 cases; D28's ceiling is correctly
  split, `yearSpansOf` (`event_agenda.dart:462`) giving `ceiled ⊆ full`
  with `_scrollYears` driving only the scroll, its chevrons, `_goToYear`'s
  clamp and `_clampYearToScroll` while `_step`, `_firstYearOf`,
  `_pickRange`'s bounds and month mode read `_years`. Question 2 — a view
  naming a **deleted** category (the id survives in the allowlist, narrows
  nothing because `CategoryService.deleteCategory` reassigns, and is
  dropped from the read-back by `visiblePlus`) and a **hidden** one
  (`CalendarCategories.visiblePlus:132` keeps it when the allowlist names
  it) are both sound; `missedOnly` is correctly session-only
  (`settings_service.dart:1342` writes order and rows alone); the one
  defect is C27. Question 3 — all eight states of `_presenceOffered`
  (`:2236`) walked against §3.15 and §3.16 and correct, including
  `_occurrenceMask`'s lifecycle through `_forgetMarked:704` and
  `_hasOccurrence:1263`. Question 4 — the band and the rows cannot
  disagree: the query is a post-filter through one `EventQueryMatcher`
  over a query-free store, and `_tally:1220`, `_hasEntry`, `_barsFor` and
  the nav count all read the narrowed bucket (month mode's whole-month
  totals with a day picked are §3.16 as written, not filed). Question 5 —
  the detail sheet's park/adopt contract holds (`_onStateChanged:656`
  parks while `_covered` or the guard is open, `_resumeUncovered:589`
  refuses to steal a parked state from a running trip, `_openDetail:2279`
  adopts once, `SheetGuard.run`'s `finally` cannot strand the slot); no
  finding, nothing routed to B7. Question 6 — reached; the hot paths that
  matter are guarded (the keyboard inset is read in a `Builder` below the
  chips, band and body at `:2405`; the year sections hang on a cached
  delegate and a per-year `AgendaYearTileSource` version; the list's
  scroll listener hits the layout cache; `_ExactExtentSliver` keeps
  offsets O(log n)), and what it found is C32 and C33. **Lead-verified**
  against the code, the reviewer's three structural claims: C28's
  `rowCount` capture at `:2888` against `childCount: _rows.length` at
  `:3096`, C30's short-circuit at `:2013-2019`, C34's double reversal at
  `:1106` and `:1131` — all three stand. **Left open:** nothing; all six
  questions closed. **Not reproduced:** C27 needs a clock injected into
  `OverviewViewService._load` / `_toCompanion` (which is the test C31
  asks for), and C28 and C30 need a timed widget test or one screen
  recording — each is one run from CONFIRMED, and the reviewer judged the
  snapshot rebuild against its remaining turns and read instead.
  `agenda_year_pager.dart` was read only against §4.1's "as it is for the
  day list sheet" (its own scope is B3b) — unchanged, no finding. Nothing
  already in the roadmap's §8 Deferred was re-filed, and none of C27–C34
  restates C1–C26. Gate, run read-only by the reviewer: `dart analyze lib`
  clean; `calendar_overview_page_test.dart` `+198 ~1` (the one skip is
  §8's known stale-semantics reproduction); the eight remaining
  overview/agenda/period suites `+128` green. No probe was needed, so no
  snapshot and no `subst` were created; tree clean after the reviewer
  (`git status --short` shows only this record).

- **B3b — 2026-10-28, DONE.** One `reviewer` (Opus 5.5, high) on the twelve
  files and all five questions; none left open. Defaults taken with the owner
  asleep: D1 A (correctness and regression — the alert surfaces out, and no
  file of B3b's calls into them wrongly) and D2 A (no `design-reviewer`, so
  the two sheets were read for behaviour only and no conformity finding is
  filed), B1's letters unchanged. **C35–C43 filed**, all to B6: one M, eight
  L, no H. **Verified end to end:** question 1 — `compareWithinDay`
  (`event_agenda.dart:957-971`) is total and stable (priority ascending →
  all-day before timed → `startMinute` → `titleFold` → `id`), and there is no
  missing-start-minute case to handle because `EventTime.startMinute` is
  non-nullable and asserted into `[0, 1440)` with `endMinute` derived
  (`calendar_event.dart:87-90`), so a midnight-crossing event exceeds 1440
  rather than wrapping and `_displayEnd` clamps it; `yearBoundsOf` /
  `yearSpansOf` (`:432-527`) include both ends, clamp to
  `earliestYear`/`latestYear`, always contain `todayYear`, and are pinned by
  eleven cases plus the month-key round-trip across a year boundary;
  `resolveRange` is inclusive on both ends and `start + 365` is exactly a leap
  year, so a `wholeYear` window is never clipped. **The debounce does not drop
  or stale a keystroke** and the `SearchBloc._pendingQuery` trap does not
  apply: `calendar_bottom_panel.dart:288-308` sets `_filters` in a synchronous
  `setState` per character (only the settings *write* is debounced, with
  `_flushPendingPersist` on dispose), and the view's 200 ms timer
  (`upcoming_agenda_view.dart:485-493`) captures nothing — it calls
  `_recompute()`, which re-reads `widget.filters.query` through `_syncQuery()`
  at fire time, and any concrete change cancels it and scans synchronously;
  what the window *does* get wrong in that interval is C41. Question 2 —
  `_forEachMissingRun` (`agenda_month_store.dart:111-137`) splits at a gap and
  at twelve and never truncates (thirteen contiguous months close a 12-run
  then a 1-run; pinned by the 12+1 and the thirty-month cases), and since any
  twelve consecutive months span at most 366 days the `_spanOf` assert cannot
  fire — the two worst cases (Mar 2023–Feb 2024, Feb 2024–Jan 2025) are both
  exactly 366. `forget(month)` drops bucket, bars and tally and is the one
  re-resolve; `_resolveRun` overwrites the month's tally too, so the two tiers
  cannot drift. **An external sync reload does reach the store**, through the
  events-list identity: `_appReloadCalendar` → `notifyExternalChange` → a new
  `allEvents` → `_storeStale` → a new store; the overview `forget`s only the
  marked month on a presence bump with an immediate `ensure`
  (`calendar_overview_page.dart:712-741`), never a replace, so the list cannot
  shrink under the finger. The index's extents are exact for every row kind
  (`extentKindOf:400-412`), and the gap only ever lands where the extent table
  expects it because `FormRowShell.build` returns early unless
  `last && trailingGap` (`form_rows.dart:193`) while `FormIndentedRow.build =>
  child` adds no height; the batched resolution lands on its own generation
  (`_scheduleListRun` re-checks `generation != _resolveGeneration` and
  `_covered` inside the `Future`, `:1049-1063`). Question 3 — **there is
  deliberately no `PopScope`** (`agenda_day_list_sheet.dart:47-50`): back and
  the scrim always dismiss the whole sheet with null even while a year tile has
  drilled into a month, the ← is a header affordance that pops nothing, and
  double-pop is guarded by `_popped`; pinned by the four back/scrim/✕ tests.
  **B2's open question is answered:** a drill-down mode that changes under the
  sheet while it is open has no effect — `_mode = widget.initialMode` is read
  once in `initState` and the widget is built inside
  `showModalBottomSheet`'s builder, so it is never rebuilt with a new
  `initialMode` and the external pick lands on the next open; `onModeChanged`
  fires from the chips only. The picked day is cleared deliberately on every
  transition, the year scope survives a drill-down and back, and the sheet owns
  no query. `agenda_year_pager.dart` (B3a left its scope here) needs nothing:
  its only in-build resolution is `tilesFor`, the one exception the skill
  grants the day list, and `_tilesByYear` + `_schedulePrewarm` keep it to one
  resolver run per year. Question 4 — the solver is correct: a maximal
  transitive cluster closes at `start >= clusterMaxEnd` (sound on a
  start-sorted list), greedy reuse on `columnEnds[c] <= start` is correct
  interval colouring, an event wholly inside another gets its own column, a
  zero-duration event is floored to `minBlockMinutes` then `minBlockHeight`, an
  all-day event leaves the grid for the pinned strip, and hidden-mode filtering
  happens before the solve; what it found is C38, C39 and C40. Question 5 —
  the presence contract holds as D31/D32 write it: `presenceTracked` is set
  from `EventPresence.appliesTo` on every entry
  (`agenda_list_view.dart:700-732`) with the same rule applied to
  `eventDayMarks`, the pencil outranks the button
  (`agenda_day_list_rows.dart:529-552` draws the button only `else if`), a
  press sends an explicit status and never a clear, a row tap always opens the
  sheet with no mode that changes it, the day list sheet is pencil-only
  (the button is the overview's, gated by `_presenceOffered` at `:2236-2237`),
  and `DaySummaryPanel:205-220` gates the same way. **A correction to B1's
  question 6:** `CalendarMissedDisplay` has **two** values, not three
  (`calendar_appearance.dart:106-123`: `faded`, `hidden`, `fromName` falling
  back to `faded`), and both are handled consistently at every seam —
  `buildAgendaRows` drops hidden entries before the day header is emitted so
  the per-day count stays honest, `eventDayEntries`/`eventDayMarks` drop them
  before a row or a mark exists, `occurrencesInRange`'s collapse pass refuses
  to let a hidden occurrence be the survivor or be counted
  (`event_agenda.dart:357-372`), `categorySummariesOf` takes `hideMissed` so a
  card cannot promise an empty drill-down, the index counts kept up from the
  non-missed entries and sets a day's missed bit only when nothing on it was
  kept, `buildBars` fades a missed bar, and the day panel always lists them
  because it is where they are marked; the two folds' masks agree on the "one
  kept entry wins its square back" rule, pinned twice. **Lead-verified**
  against the code, the reviewer's four structural claims: C35's capture chain
  (`late final _store` / no `didUpdateWidget` → the `onEdit` closure over the
  captured `CalendarEvent` → `_popEdit(VoidCallback)` → `editorSheet` passing
  `initialEvent` to `EventEditorSheet.show` without re-reading the bloc), C36's
  two label sites against `resolveRange`'s clamp, C37's three raw `DateFormat`
  constructions against the eight caches beside them, and C42's dead branch
  against both loops — all four stand, and C36 and C42 were upgraded to
  CONFIRMED on that static proof (neither was screenshotted). **Not reproduced:**
  nothing was exercised in a running app — C35, C36, C38, C39, C41 and C43
  would each need a widget test or a device pass, which the reviewer brief
  forbids writing, and C39's negative-width threshold (≈77 overlapping events
  on a 360 dp phone) is computed, not rendered. One thing was read and left
  unfiled because the record pins it neither way: list mode's scroll offset is
  lost on a list → month → list round-trip, because each mode builds its own
  scrollable with no `PageStorageKey`. `calendar_overview_page.dart` was read
  only at the four places questions 2 and 5 point into; its own scope was
  B3a's. **Read and not re-filed:** `R76`–`R86` and `C1`–`C34`; `R77` is
  adjacent to C35 in consequence but does not cover it (merge-side LWW against
  a tombstone, in a file B3b does not touch). Gate, run read-only by the
  reviewer: `dart analyze lib` clean; the scan, store and index suites `+107`
  green; the day-list-sheet and timeline-memo suites `+76` green; every l10n
  key the twelve files use present in all three ARBs with `untranslated.txt`
  `{}`. No probe was needed, so no snapshot and no `subst` were created; tree
  clean after the reviewer (`git status --short` shows only this record).

- **B4a — 2026-10-28, DONE.** One `reviewer` (Opus 5.5, high) on the nine files
  and all five questions. Defaults taken with the owner asleep: D1 A
  (correctness and regression — the alert surfaces out, and the editor's own
  alert *rows* left to B4b) and D2 A (no `design-reviewer`, so questions 3 and 4
  were read for behaviour only and no conformity finding is filed), B1's letters
  unchanged. **C44–C57 filed**, all to B7: three H, five M, six L. **Verified end
  to end:** question 1 — `_canSave` (`:1044-1060`) is exactly the skill's formula
  (title trim ∧ (not recurring-weekly ∨ weekdays non-empty) ∧ `_withinLimit` on
  *both* scopes, grandfathered per scope), five of §6.4's seven rules hold as
  written (title trim, the weekly weekday gate twice over with
  `EventRepeatDraft.isValid`, "start moving forward clears Until", the multi
  picker refusing an empty confirm with `allowEmpty` only on the skip picker, the
  dirty-leave ask), every repeat-only flag is correctly gated on save
  (`effectiveEnd`, `effectiveRetroactive`, `effectiveCountOccurrences`,
  `effectiveTracksPresence`, `effectiveAssumeAbsent`/`From`,
  `effectiveShowInDayRail` resolving to NULL and not false,
  `effectivePerOccurrenceDescriptions`, `effectiveRemoveAfterAlert` requiring
  `savedRule is OneTimeRecurrence`), `clearIconKey: _iconKey == null` is kept
  (`:1757`), the interval is clamped 1–99 only for the four kinds
  `RepeatKind.supportsInterval` names, weekday sets are `Set.unmodifiable`, and
  `_initRecurrenceFrom` is a sealed switch over all nine rules. **Editing one
  occurrence** writes exactly two things to the day — the per-occurrence
  description row and the skip set; title, category, look, rule, dates, time,
  every flag, priority, the linked note, the alerts and remove-after all land on
  the series, and the editor offers no per-day override for any of them.
  **Orphans:** a skip or occurrence row for a day a new rule no longer covers
  survives and resurfaces when the rule returns to an old shape, by design and by
  the service's own `///` (`calendar_event_service.dart:160-163`); what the save
  *creates* is C49. Question 2 — the three views are one set (`_selection` is the
  only store; `_selectView` changes only `_view`), so a pick in one survives any
  switch; **DST is structurally out of reach in the picker** — every date is built
  `DateTime.utc` and `Grep` for `\.add\(\s*(const )?Duration\(` over
  `calendar_date_picker_sheet.dart` returns "No matches found"; multi mode's set
  is unordered and read back sorted, Save is disabled on empty unless
  `allowEmpty`, `pickMulti` refuses an empty return a second time, and a reversed
  range is impossible because `_pickRangeEnds` restarts the span when the second
  tap precedes the start. Question 3 (behaviour only) — the header is a slotted
  render box deciding from the action's laid-out width
  (`form_rows.dart:585-634`), reading order pinned by `OrdinalSortKey` 0/1/2 with
  `computeDryLayout` and `performLayout` sharing one `_arrange`, so at scale 2.0
  the title takes two lines, the header grows and the body's `Expanded` absorbs
  it — no control leaves reach and nothing clips input (the body scrolls, the
  description box scrolls internally past its max); the description's minimum
  **is** one scaled placeholder line (`:2090-2097`, `textScale * 22`) and
  `_clamp`'s throwing case needs a text scale above 10. **Bottom clearance is
  `max(viewInsets, viewPadding)` on all four surfaces and on the right element in
  each** — the editor pads the body unfocused and the docked bar focused
  (`:2790-2792`, `:2845`, `:2935`), the description sheet the bar alone
  (`event_description_sheet.dart:466-469`), the repeat and look sheets their
  scroll view, the picker the multi footer or the body per view — never the whole
  sheet, which is the blank-sheet defect deviation 10 names. Question 4 — all five
  traps of the description record's deviations block hold on both surfaces: one
  `ListAwarePasteController` per sheet bound in `initState` and never swapped
  (which is *why* the editor buffers the inactive scope in a plain `String`),
  every seed through `loadText` + `syncLength()` and never `set text` so undo
  cannot pull the other scope's text in, **no autosave exists here at all** (both
  sheets are text-in/text-out and never persist, so the dispose-mid-autosave trap
  has no instance), dispose ordered listener → controller → revision notifier →
  focus → scroll → search on both with the build-phase relay deferring to a
  `mounted`-guarded post-frame bump, the keyboard reveal reproduced for a
  non-`EditableText` by `_revealDescription`/`_revealCaret`/`_onFormMetrics` with
  the drag-outranks-caret rule, and the v24/v28 scope handed over one scope at a
  time with its own grandfather; `configureMoney` is called in neither file.
  Question 5 — one guard serves everything (`FormSheetFrame` is
  `PopScope(canPop: false)` → `onLeave`, which the barrier's `Navigator.maybePop`
  consults too; `enableDrag: false` so the frame owns the drag and a dismissing
  drag snaps back then asks; two `_leaving` latches so a drag ending mid-dialog
  cannot ask twice; Save pops directly past it; back pops `EventEditorBack` and ✕
  `null`), the Repeat and Icon & color sheets are unguarded as the record says
  while the description sheet has its own baseline, and `SheetGuard` cannot strand
  its slot (`try`/`finally`, `:22-27`). **On save the user's version wins, and it
  wins completely:** `base.copyWith(…)` names all 23 of `CalendarEvent`'s model
  fields (the model carries no CRDT fields, `calendar_event.dart:526-549`), so
  `base` contributes only the `id` and the DAO re-reads the row for
  `version`/`hlc` — a remote edit to any column under the open editor is
  overwritten by design. What that LWW does *not* cover is C45 (a tombstone) and
  C46 (a row the user never saw); the spurious dirty ask it produces is C47.
  **Lead-verified** against the code, every H and every structural M: C44's
  `_dayBuffer` seed and its five assignment sites against the guard at `:1810`;
  C45's missing `hasEvent` guard against `_onDeleteEvent:961-962` and the DAO's
  un-tombstoning update branch; C46's `initState`-only `_alerts` against
  `EventAlertDao.replaceForEvent`'s tombstone loop; C47's live
  `EventSkips.daysFor` inside a snapshot fingerprint against
  `app_sync_apply_hooks.dart:263`; C48's two dispatch loops; C50 and C51 against
  `_buildRule`, `_setOneTimeDates`, `EventRepeatDraft.isValid` and
  `_pickEndDate`. All stand. **Three corrections to the reviewer's report, made
  here:** C45 and C46 were upgraded to CONFIRMED on that static proof (the
  tombstone and the tombstone loop are both in the code; only the pull's timing
  was not driven), C47, C48, C50 and C51 likewise; C50's reproduction as reported
  was vague and is replaced by the path lead-verified above (`_setOneTimeDates`
  moves the start without the clear `_pickDate` applies, then the repeat sheet
  hands an untouched stale `endDate` straight back) — its `file:line` and fix were
  right; C53's anchor is `:483`, not `:479`, and C55's are `:411` and `:876`.
  **Left open, for the owner to route:** `event_detail_sheet.dart` was read only
  at `show`, its state, `_flushWrite`/`_close`/`dispose`, `_computeUpcoming` and
  `_buildWhenRows` — its alert rows, presence rows, description rendering and
  `build` were not read (B3a cleared its park/adopt contract and nothing was filed
  against it); `MonthYearPickerSheet` inside `calendar_date_picker_sheet.dart` was
  not read; the editor's alert rows were read but deliberately left to B4b, which
  is where C46 may be merged; whether `EditorRenderContextCache` and
  `MarkdownEditorSpanBuilder` need unbinding on dispose is open (neither is
  unbound in either sheet; judged benign because both are per-sheet instances, one
  grep in `markdown_editor_span_builder.dart` for a `dispose`/`unbind` settles
  it). **Not reproduced:** nothing was exercised in a running app and no screen was
  rendered — C44 would be CONFIRMED-by-test with the two cases C57 names (the
  existing `open`/`saveAnd`/`pendingDay` helpers suffice), C45 and C46 need a
  reload driven under an open editor (a `notifyExternalChange()` plus a facade
  republish between mount and Save, which no existing suite sets up), C48's
  fan-out count needs a bloc test counting emits per Save, and question 3's "no
  control becomes unreachable" rests on `_arrange`'s geometry rather than on a
  2.0-scale render — the `FilledButton` Save under `maxHeight: 48` at scale 2.0 is
  the one place the reviewer suspected clipping and could not measure, so B8's
  device pass should look at it. **Read and not re-filed:** `R76`–`R86` and
  `C1`–`C43`; C45 is adjacent to C1, C35 and `R77` in consequence and restates
  none of them (different file, different missing guard). C16 (B2's, routed to B7)
  stands untouched: both `dayLoad` closures in `event_sheets_flow.dart:390` and
  `:417` still read the filtered `eventsForDay`. Gate, run read-only by the
  reviewer: `dart analyze lib` → "No issues found!"; the eight editor suites
  `+161` green; the nine picker/detail/description/clearance suites `+164` green
  (325 tests, one run at a time); no ARB touched, so no `gen-l10n`. No probe was
  needed, so no snapshot and no `subst` were created; tree clean after the
  reviewer (`git status --short` shows only this record). **B1's lesson repeated:**
  the reviewer hit its 80-turn limit before reporting — nine files and 7,700 lines
  is still too much for one run — and was resumed for the report alone, as B1 was.
  B4b and B5 should be split, or given a file list of three.

- **B4b — 2026-10-28, DONE.** **Two** `reviewer` runs (Opus 5.5, high) over
  disjoint halves of the block's fifteen files, not the one the block names:
  B1's and B4a's reviewers both hit the 80-turn limit before reporting and had
  to be resumed, and B4a's log closes by saying "B4b and B5 should be split, or
  given a file list of three" — this is that split, and it worked (both runs
  reported inside their turns, 67 and 55 tool calls). Half 1, the alerts: the
  ten alert / quick-alarm / digest files plus targeted reads of
  `event_alerts.dart`, the editor's Alerts group and `deleteCategory`. Half 2,
  the rest: the two template sheets, the two category sheets, `category_service.dart`
  plus `event_template_service.dart`, which **no block of this review was given**
  and which half 2 therefore owns. Cost: ≈ 2.8 units against §6's 1.4 for this
  session — the budget line for night 3 becomes ≈ 11.4. Defaults taken with the
  owner asleep: **D1 A** (correctness and regression; the alert surfaces stayed
  out, so `alert_scheduler.dart` is again where a question's answer lives — see
  "Left open") and **D2 A** (no `design-reviewer`: both sheets' halves were read
  for behaviour only and no conformity finding is filed), B1's letters unchanged.
  **C58–C82 filed**, all to B7: one H, six M, eighteen L.
  **Verified end to end.** Half 1: `effectiveFor`'s opt-out, D4's dedupe key
  (`(mode, offsetMinutes)` timed, `(mode, daysBefore, dayMinute ?? default)`
  all-day), the Other fallback (`CalendarCategories.fallback.id == 'other' ==
  kFallbackCategoryId`, so a stale id and a `deleteCategory` reassignment agree),
  and paused-alert invisibility at **every** reader reachable
  (`event_alert_badge.dart:40`, `event_detail_sheet.dart:267-269`,
  `ics_serializer.dart:140-144`, `calendar_categories_page.dart:388-390`,
  `event_editor_sheet.dart:1499-1506`, `AlertPlanner.plan:132-136`) — all filter
  `enabled`; `AlertPlanner.fireInstant` and `DigestPlanner._fires` both use
  `DateTime(y, m, d, 0, minutes)` over date-only UTC days, so **every date path in
  those two files is structurally DST-safe** and the one local-wall-clock rebuild
  left in the area is C60's; `AlertCountdown.nextFire` returns null when every
  fire is behind `now` (a wholly past event earns no word) and `afterSave` stays
  silent on a rename through `listEquals`; `AlertOffset`'s unit-as-a-view, the
  clamp on a unit change, days-only for all-day and Custom-writes-only-on-Done
  (`alert_offset_sheet.dart:158` pops from Done alone, `:151` pops null) all hold,
  and `FormCaptionSlot` wraps its candidates in `IgnorePointer`/`ExcludeSemantics`
  so C67's hidden steppers are not tappable; the quick alarm creates exactly one
  one-time event, one alert at its start and one Undo snackbar, opens on Alarm,
  and `quickAlarmDayFor` never yields an instant behind `now` on any non-DST
  path; the digest tap target is `main.dart:535-541` → `_serveOverviewLook` →
  `_listLook` with `options == null`, which skips `_persistPeriod`, clears the
  query and `missedOnly`, keeps Order and Rows and persists only the mode and the
  allowlist, and `AlertPayload.categoryIdSet` maps an empty CSV to `{}` while the
  overview's `_scan` passes the planner's own arguments — **so an archived
  category's digest does land on the list that counted it**; the three
  interleavings of a sync `reload()` against an in-flight `replaceForEvent` keep
  the facade consistent through `_publishFor`'s `_published` overlay; the editor's
  inherited rows are read-only with "From {category}" and re-read on a pick, Add
  alert counts `_alerts.length`, remove-after reads `_hasAlarmAlert` (own only),
  the switch is last and dims in place, `forCategory: true` gives two When rows
  both reaching `_draft` and never remove-after (`:452`), and `_afterAlertsSaved`
  is one message at most. Half 2: a template stores **nothing** for alerts (no
  column — D2 by design, so an inherited alert survives trivially, a paused one
  stays the category's row, and `removeAfter` is deliberately not inherited,
  `category_alert.dart:43-55`), which leaves C77 as the one thing the round trip
  loses; scaling invariants **3, 4, 8, 9, 10, 12 (for mutations) and 13 all
  hold** — `updateCategory` writes only name, colour and icon (`:312-323`), every
  mutation is on `_serialize` whose tail starts null, `rankCategories` sorts on
  `(band, sortOrder, id)`, `forKey` is a map lookup, `visiblePlus` is the one
  helper, seed / import / reorder are each one batch — and the one gap is
  invariant 12's: `reload()` (C74); a built-in's stored name is never written
  (`category_editor_sheet.dart:368`), the sheet has no hide and no delete, empty
  and whitespace-only names disable Save, case- and accent-folded duplicates warn
  and never block, a 40-char name saves; the picker's contract holds whole
  (`pickSingle`/`pickMulti`, `visiblePlus(initialSelection)`, no autofocus, the
  field kept while a query is live, "Hidden" as an archived row's caption, the
  bulk rows disabled over *the rows listed*, empty never collapsed, the inline
  create returning and selecting the new id with the catalog re-read in `build`),
  its two defects being C78 and C79; `setHidden`, the reorder batch, `seedMissing`
  and `importAll` are sound. **Lead-verified** against the code, the H and every
  structural M: C58's `initState` seed at `category_editor_sheet.dart:142-144`
  against `category_alert_dao.dart:60-75`'s `keep` loop; C59's `upsertDigest`
  undelete against `setEnabled`'s explicit refusal (the asymmetry is literal, and
  `setEnabled`'s own `///` states the reason); C61's and C73's missing
  `_initializing` (`grep -c` returns `0` in `event_digest_service.dart`,
  `category_service.dart` and `event_template_service.dart`, against
  `event_alert_service.dart`'s four sites); C71's `reassignCategory` SQL against
  `deleteCategory`'s untouched event service; C72's `tombstoneCascade`, which
  calls `reassignCategory`, `tombstoneForCategory` and `_tombstone` and nothing
  else. All stand. **One correction to a reviewer's report, made here:** C61 was
  filed PLAUSIBLE and is **upgraded to CONFIRMED** — both halves are quoted in the
  code (no `_initializing`, and `reset()` clearing `_instance` alone) and the
  interleaving is reachable from `AlertScheduler`'s pass, which is B4a's
  precedent for a static proof; C71's and C72's CONFIRMED are kept on the same
  footing. C71 deserves one note the reviewer itself made: `deleteCategory`'s own
  `///` at `:385-389` already accounts for the *alert pass* reading a stale event
  cache and healing on the next pass — what it does not cover, and what C71 is,
  is the **editor writing the dead id back**. **Three findings are decisions, not
  plain defects, and are marked as such in their text** — the owner may strike
  any of them: C62 (the subsystems wording versus the test that pins the current
  reading of `_demoted`), C64 (whether the Quick Settings path runs the
  permission check at all), C76 (the three siblings disagree on whether an edit
  may resurrect a tombstone — the category DAO refuses, digests and saved views
  upsert). **Left open, for the owner to route:** what a sync reload does to
  digest entries *already armed*, and whether `DigestPlanner`'s planned-versus-
  delivered state survives it, live in `alert_scheduler.dart` (`digestEntries`,
  `_assignOsIds`, `digestArmSignature`) — the **same** gap D1 A left half-open in
  B1's question 7, now named by two sessions; the hub's inherited-row switch (D5's
  way back for an opted-out event) is `AlertScheduler.hubEntries()` and
  `alerts_page.dart`, B5's and out of scope here; and what
  `reconcileAllQuietly` plans for an event freshly stamped from a template, which
  is the same file again. **Not reproduced:** nothing was exercised in a running
  app and no screen was rendered. C60 is the one finding that needs a file to
  confirm — two cases under a fixed `TZ`, which is exactly C70 — and C71, C72,
  C73, C58 and C59 are proved statically (the SQL, the missing refresh, the
  missing guard, the `keep` loop, the two opposite DAO branches) rather than
  driven, because a reviewer may not add a case; C82 spells out the two cases that
  would nail C71 and C72. C78's keyboard return is a reading of the route's
  focus-scope restore, not an observation. **Read and not re-filed:** C1–C57, and
  the digests roadmap's §11.1 residuals — the one-day `digestPeriodOf` span,
  Recent describing a digest by its current settings, the categories page's
  missing revision listener, the bell's 24 dp, the shared `created_at` second, the
  `category_alerts` column order, the category editor's drag-close returning
  `null` after a failed alert write — each checked against a finding and none
  filed. C58 is C46's category twin (a different table, a different write path,
  and narrower), C66 is the *editor* where §11.1 names the page, C75 is the
  category row's own write where C58 is its alert set, C77 is a missing column
  where C46 is a tombstone loop; each says so in its own text. The countdown's
  `before` computed without `skippedDays` (`alert_countdown.dart:101-106`) is the
  gap that method's own `///` already names, so it is house-documented, not a
  finding. Gate, run read-only by the reviewers: `dart analyze lib` → "No issues
  found!" twice; half 1's ten widget suites `+225` and its ten service/util
  suites `+184`; half 2's eight suites `+369` — 778 tests, one `flutter test` at a
  time, all green, so **every id above sits beside green tests**. No ARB was
  touched, so no `gen-l10n`. Neither reviewer needed a probe, so no snapshot and
  no `subst` were created; tree clean after both (`git status --short` shows only
  this record). **The lesson, settled:** the split is what the next session should
  copy — B5's nine files are the same size as B4b's fifteen, and it should run as
  two halves (settings + appearance + palette; the categories page + header +
  export + the hub's two groups) rather than as one reviewer with a resume.

- **B5 — 2026-10-28, DONE.** **Two** `reviewer` runs (Opus 5.5, high) over
  disjoint halves of the block's ten files, not the one the block names: this
  is the split B4b's log settles as the lesson for this session ("B5's nine
  files are the same size as B4b's fifteen, and it should run as two halves"),
  and it worked again — both runs reported inside their turns (60 and 75 tool
  calls), neither needed a resume. Half 1, settings and colour: the settings
  page, the appearance page, the appearance preview, `CalendarAppearance` and
  `CalendarPaletteService`, plus targeted reads of `calendar_palette.dart`, the
  three colour widgets, `settings_service.dart`'s calendar getters, the two
  fasting sheets, `backup_service.dart`'s settings allow-list and
  `settings_page.dart:665`/`:739` (the Start choices' stacking, which lives in
  the app settings page and not in the calendar's). Half 2, the managing
  surfaces: the categories page, the header menus, the export controller,
  `IcsSerializer` and the hub's list and Digests group, plus targeted reads of
  the bloc's six write handlers, `category_service.dart`'s page-facing methods
  and `AlertScheduler.hubEntries()`/`digestEntries()` **for the contract only**.
  Cost: ≈ 2.8 units against §6's 1.4 for this session — the budget line for
  night 3 becomes ≈ 12.8. Defaults taken with the owner asleep: **D1 A**
  (correctness and regression; the alert surfaces stayed out, and half 2 was
  briefed to read `hubEntries()` and `digestEntries()` without filing in them —
  see "Left open") and **D2 A** (no `design-reviewer`: both halves read every
  surface for behaviour only, and neither filed a conformity finding, although
  C90 and C92 are where that letter bites — a preview that disagrees with the
  grid and eight unmeasured segmented buttons are functional at 1.0 and
  unreadable at 2.0), B1's letters unchanged. **C83–C111 filed**, all to B7:
  four M, twenty-five L, no H.
  **Verified end to end.** Half 1: all 17 `CalendarAppearance` fields are in
  `_calendarAppearanceKeys`, every `SettingsKeys.defaultCalendar*` matches the
  model's own initializer, every enum parses through a forward-compatible
  `fromName`, and `getAllSettings()` is reached from none of these surfaces;
  between the two pages' resets every appearance key is written exactly once
  and **neither touches the palette** — the invariant `references/colour-palette.md`
  pins — with no markdown or foreign key written except the shared fold row
  (C88); absent-vs-empty survives both resets because `FastingSchedule.encode()`
  (`fasting_schedule.dart:185`) and `FastingAppearance.encode()`
  (`fasting_appearance.dart:242`) always emit non-empty JSON, so writing the
  const defaults cannot re-open the retired `calendar_fasting_weekdays` /
  `calendar_fasting_style` fallbacks; **every appearance write reaches the grid
  with no restart** — `CalendarPage.didPopNext` (`:733`) → `_loadSettings`
  (`:756`) → one `getCalendarPageSettings()` plus `FastingCalendar.configure`,
  with `FastingCalendar.revision` and `PublicHolidays.revision` inside
  `_outputGeneration` (`:365-382`) so the three resolver output caches drop, and
  no setting needs a page revisit or a second toggle; **there is no C15 twin on
  this group** — `calendar_page.dart` writes exactly one setting
  (`calendarGridFilters`, `:803`), so `_appearance`'s unconditional `setState`
  at `:786` has no in-session writer to race, and both settings pages hold every
  row behind `_isLoading` until the load lands (the hidden-categories selection
  the question names is not on either page: it is
  `CalendarGridFilters.hiddenCategoryIds`, restored by the very block C15 is
  filed against, so it stays C15's); the one picker holds — `ColorSwatchPicker`
  is the only colour row (five call sites) and `ColorPickerSheet` the only
  wheel/square (six), no `_ColorDot` or `ColorWheelDialog` survives, **no widget
  holds the palette service** (all four call sites resolve it per use),
  `_foldLegacyRecents` writes the destination before clearing the source and
  cannot resurrect a deleted colour, `move` is a permutation and cannot breach
  the cap, and a deleted swatch still renders where it was chosen as the orphan
  dot (`color_swatch_picker.dart:339-345`). Half 2: **the header menus are
  clean, no finding at all** — `CalendarHeaderMenus` is stateless with no local
  copy of format, view or period, the calendar's title is a `BlocBuilder` on
  `_formatOf(state)` and the vertical-swipe path dispatches the same
  `ChangeCalendarFormat` (`calendar_page.dart:2013`), one event per choice with
  `_select` a no-op on the current value, page switches through
  `AppNavigator.switchToCalendarOverview` / `switchToCalendar` /
  `toAlertsFromCalendar`, options through `AppNavigator.toCalendarSettings` on
  both pages, format rows and Export disabled in place while unloaded so the
  menu cannot change shape under the finger, and no `AppLocalizations.byKey`
  anywhere (`_labelOf` and `_formatLabel` are sealed `switch`es); on `.ics`
  every `RecurrenceRule` subtype maps or is deliberately `null` with
  `_hasRrule` as its complement, the monthly/yearly `day.day != start.day`
  clamp matches `FREQ=MONTHLY`/`YEARLY`, weekly interval phase survives moving
  `DTSTART` to `first` because `_weekIndex` is Monday-aligned with `WKST=MO`
  emitted, `UNTIL` takes `DTSTART`'s value type, all-day is `VALUE=DATE` with
  `DTEND` one day after on a UTC date-only value (**no DST hazard and no
  off-by-one**), `EXDATE`/`RDATE` value types match `DTSTART`, escaping orders
  the backslash first, the `VALARM` arithmetic checks out by hand (`PT9H`,
  `-PT4H`, `-P5DT15H`), `CalendarExportController` goes `ImportExportBloc` →
  `ExportCalendarRequested` → `IcsSerializer` → `shareExport` and never touches
  `SharePlus`, and `enum ExportFormat` still has only `json`, `markdown`, `text`
  — no `ics` variant creeping in; the categories page keeps hiding-as-archiving
  (it writes only `setHidden`, never `hiddenCategoryIds`, and leaves
  `sort_order` alone so unhiding restores the position), cannot delete a
  built-in (gated at `:579` **and** refused by the service by flag and by id) or
  rename one in storage (`category_editor_sheet.dart:368`), routes every menu
  write through `_guarded`, keeps the alerts bell filtered on `enabled`
  (`:388-390`, as §4 requires), and its drag reorder is genuinely off while
  filtering with `onReorderStart` unfocusing and `onReorderItem` handed
  post-removal indices; **the hub's structure holds whole** — `EventDigests.all`
  with one `ToggleEventDigest` switch each, tap → `DigestEditorSheet`
  (`SaveEventDigest` / `DeleteEventDigest`), Add digest only under
  `kDigestHorizon.maxDigests`, fires of **enabled** digests among the day groups
  with the switch slot held empty and inert (`_DigestFireRow:1031-1039`),
  deliveries under Recent through `AlertHistoryEntry.digest`, **no cancel, no
  snooze and no missed affordance on any digest row**, **no event-alert-creation
  affordance anywhere on the page**, row keys carrying the event id
  (`'${entry.event.id}|${entry.alert.id}|${day}|${snoozeOsId}'`, `:543`) so
  twins sharing a category alert id cannot collide, no `Timer` and no polling,
  every write through `CalendarBloc` — and **the inherited-row switch writes
  `UpdateCalendarEvent` with the `categoryAlerts` flag alone, reading the event
  from the bloc state at press time** (`:246-253`), which closes the one
  H-shaped risk this half was briefed to look for. On **readiness D11**:
  `hubEntries()` lists enabled alerts from the registry rather than from a fresh
  plan, so an alert definition that arrived by sync and this device has not
  armed is simply **absent** rather than shown as armed — honest under the
  honesty clause; C105 is the single exception, and it is a failed local write
  rather than a sync claim.
  **Lead-verified** against the code, the four M and the three structural L:
  `calendar_palette_service.dart:54-79` (C83) — `_create` sets `_instance` with
  no generation read and its `finally` clears whatever `_initializing` holds,
  while `reset()` nulls the field without cancelling the flight;
  `ics_serializer.dart:406` (C84) — the guard is `line.length <= 73` four lines
  under a `///` that says octets, and the loop below it is octet-correct, so the
  fast path is the whole defect; `calendar_categories_page.dart:193` with
  `calendar_bloc.dart:1203-1210` (C85) — `_onCategoryAlertsChanged` emits one
  `occurrenceRevision` bump and its own `///` says why ("no membership
  changed"), which is true of the editor's alert write and false of a delete
  that reassigned events; `grep -rn "CalendarCategories.revision" lib/` (C86) —
  four readers, none of them this page; `calendar_settings_page.dart:1301` (C88)
  against `calendar_appearance_page.dart:42-48` (C88) — the shared row is
  documented as shared and cleared wholesale; `settings_keys.dart:524-525` (C87)
  — `calendarMaxDayRailMarks` has `min`/`max` and `calendarMaxDayBars` has only
  a default; `calendar_appearance_preview.dart` (C90) — `grep -c missedDisplay`
  returns `0`; `calendar_categories_page.dart:222`/`:285` (C101) — `_moveToTop`
  and `_sortAlphabetically` both reach `_persistOrder` with no `_isFiltering`
  gate while `:335` renders the locked hint. All stand. **One judgement made
  here:** C83 is filed **M** on C61's precedent (the same missing-guard shape,
  filed M by B4b) although its payload is worse — `_commit` rewrites the whole
  settings row from memory, so the loser of the race does not merely serve a
  stale palette, it persists one over a restored backup. The id says so and the
  owner may lift it to H before night 4. **Two findings are the owner's scope
  call rather than plain defects** and say so in their text: C97 (the fasting
  schedule is not on the backup allow-list — pre-existing, outside B5's diff,
  filed only because the question asks what survives a restore) and C111
  (`CalendarExportController.isPending` is public for its test alone).
  **Left open, for the owner to route:** `AlertScheduler.hubEntries()`
  (`alert_scheduler.dart:572`) and `digestEntries()` (`:709`) are the asymmetry
  behind the block's question 6 — alert rows are registry-truth while digest
  fire rows are planned fresh, so a digest fire row shows a notification this
  device may never have armed; the record sanctions "planned fresh", but it is
  the one place where the hub's two halves answer D11's honesty question
  differently. Half 1 adds four calls that only hold up if
  `reconcileAllQuietly` really re-arms on an arm-signature move
  (`calendar_settings_page.dart:202, 960, 991, 1338`, plus `scheduleTestAlarm`
  at `:1220`), and whether the reset's `setAlertDefaultAllDay` plus
  `EventAlerts.configureDefaultDayMinute` leaves standing **digests**
  consistent — the same file again. **That is the fifth and sixth session of
  this review pointing at `alert_scheduler.dart`** (B1's question 7, B2's Skip
  notice, B4b's three, now both halves of B5), which is the strongest argument
  yet for flipping **D1 to C** and running B5b on the alert surfaces before
  night 4; four of this review's loose questions would land there instead of
  nowhere. One more pointer, out of half 2's files:
  `calendar_overview_page.dart:612` opens Calendar settings from the overview,
  so a fasting, holiday or appearance change made there pops back to the
  overview rather than the calendar — whether the overview re-reads
  `FastingCalendar` and the appearance on that pop is B3a's file and was not
  read. **Not reproduced:** nothing was exercised in a running app and no screen
  was rendered. C84 is the one finding proved by a probe, and the probe ran
  **outside the repo** (`/tmp/b5probe/fold.dart`, `_fold` and `_utf8Width`
  copied verbatim: `chars=73 utf8octets=138`, `folded==input: true`) because a
  probe through the real `IcsSerializer` would need a `pub get`-ed snapshot;
  C109 names the test that nails it in the tree, and it fails today. C92's
  200 % German mid-word break is derived from the Flutter 3.44.2 layout sources
  on this machine plus `app_de.arb`, not seen on screen — **B8's device pass can
  settle it in one screenshot**, and it is the only B5 id a device would decide.
  C83's race was reasoned from the code rather than driven (a probe would need a
  fake `SettingsService` whose first read is held open across a `reset()`), and
  C100, C104, C106 and C107 are proved statically. **Read and not re-filed:**
  C1 and C15 (half 1 read both and says why neither grew a twin here), C2, C59,
  C61, C64, C71, C72, C74 and C82; and the digests roadmap's §11.1 residuals,
  of which the ones the page owns did grow ids — the missing revision listener
  is C86 (with two consequences §11.1 does not name), the editor's drag-close
  returning `null` is C103 on the page's side, and the alert rows' kept
  "failed write leaves the switch" decision grew its digest twin as C105. C85
  says in its own text that it is C71's page-side twin and wants **one** seam,
  not two patches — the same shape as C46/C58, so B7 now has two pairs to fix
  once each. Gate, run read-only by the reviewers: `dart analyze lib` → "No
  issues found!" twice; half 1's eleven named suites `+177` in one run (with one
  expected in-test warning, `[BackupService] Alert reconcile after import
  failed: Bad state: AlertGateway is not registered`), half 2's eleven `+192` —
  369 tests, one `flutter test` at a time, all green, so **every id above sits
  beside green tests**. No ARB was touched, so no `gen-l10n`; no golden was
  re-rendered, and no B5 id changes a screen except C90 and C92, whose fixes
  will (B7 re-renders them on purpose and says so). Neither reviewer needed a
  snapshot probe in the tree, so no `subst` was created; tree clean after both
  (`git status --short` shows only this record). **The lesson, settled again:**
  the two-half split is now 2 for 2 — both reviewers this review gave a block of
  nine files or more needed a resume (B1 and B4a, §3.1), and none of the four
  given a half has. A block of more than about six files is briefed as halves
  from the start, and each half is given the other's file list as an explicit
  no-go area, which is what kept these two from overlapping at all.

### 3.2 Findings

Shape as the sync review's §0.6, ids `C1`, `C2`, …; fix session B6 or B7
by file.

- **C1** (M, CONFIRMED; B1) `lib/pages/calendar_settings_page.dart:1264` — "Delete all events" calls `CalendarEventService.tombstoneAll()` and tells no bloc, so a `CalendarBloc` already loaded keeps serving the wiped events for the rest of the session and saving one resurrects it. `externalRevision` is deliberately not bumped by `tombstoneAll` because "the bloc drives those" (`calendar_event_service.dart:70`) — but this caller is a settings page, so `CalendarBloc.isStale` (`calendar_bloc.dart:83`) stays false and `CalendarPage.didPopNext` → `_reloadIfStale` does nothing. Input: Calendar settings → Delete all events → back to the calendar; the grid, the panel and the agenda still draw the deleted events, and opening one and saving it hits `CalendarEventDao.upsert`'s update branch, which writes `isDeleted: false, deletedAt: null` (`calendar_event_dao.dart:83`) — the event comes back and pushes to every device. Fix: `notifyExternalChange()` after the wipe (in the caller, or in `tombstoneAll` since no bloc drives it). Fix session: B6. →
- **C2** (M, CONFIRMED; B1) `lib/services/calendar_event_service.dart:199` — `tombstoneAll` never reconciles the alert scheduler, so alarms armed for the wiped events still ring. It hard-deletes the registration rows (`:203`, `alertRegistrationDao.deleteForEvents(ids)`) and then only republishes the facade (`_refreshAlerts` → `EventAlertService.refreshAfterEventRemoval`); the platform still holds the entries, which is exactly what the single-event path reconciles for ("the platform still holds the entries — cancelling them is exactly what this pass is for", `calendar_bloc.dart:974`), and `CategoryService.deleteCategory` does the same. "A deleted event never rings" then holds only until some unrelated later reconcile reaches the stray sweep. Input: an event with an alarm due in ten minutes, Calendar settings → Delete all events, nothing else — the phone rings for an event that no longer exists. Fix: `reconcileAllQuietly(AlertReconcileReason.eventChanged)` after the wipe's facade refreshes. Fix session: B6. →
- **C3** (L, PLAUSIBLE; B1) `lib/services/event_skip_service.dart:76` (same shape `event_presence_service.dart:76`, `event_occurrence_service.dart:79`) — `_load()` clears `_byEvent` before its `await`, so a single-day write landing inside a reload republishes a partial snapshot: `_publishFor(eventId)` rebuilds that event's facade entry from the emptied map and every other skip, mark or day description of the event drops out until `_load` finishes. Input: the sync pull's `_appReloadCalendar` (`app_sync_apply_hooks.dart:253`) in flight while the user taps Skip or Missed — for those frames `occursOnUtcDay` stops subtracting the event's other skipped days (occurrences reappear in the grid) and `OccurrenceDescriptions.descriptionFor` falls back to the template, so a quick-edit sheet opened in that window loads the template text. Fix: build a local map and assign `_byEvent` only after the await; `_publishFor` no-ops while a load is in flight. Fix session: B6. →
- **C4** (L, PLAUSIBLE; B1) `lib/services/calendar_event_service.dart:116` — the same read-modify-write shape on the event cache: `_load()` assigns `_cache = rows` unconditionally, so an `upsert` that commits after the reload's `SELECT` but patches `_cache` before its continuation is overwritten and the event is missing from `service.events`. The bloc self-heals (it reloads in `_resolveAndReload`), but `AlertScheduler.reconcileAll` plans from `CalendarEventService.getInstance().events` in the same `afterRun`, so a just-created event can be planned out of that pass. Fix: as C3, or merge rather than replace while a local write is pending. Fix session: B6. →
- **C5** (L, CONFIRMED; B1) `lib/constants/fasting_calendar.dart:709` — the Catholic year-round Friday abstinence marks **Christmas Day and 1 January** when they fall on a Friday: Advent stops at Dec 24 (`:692`, `d.isBefore(christmas)`) and Dec 25 then falls through to the unconditional Friday loop. Probe (snapshot): `catholic 2026 fridayAbstinence: 42 days, 2026-01-02 .. 2026-12-25`; `catholic 2027: … 2027-01-01 .. 2027-12-31`. A fasting tint on Christmas is visibly wrong and no record claims the simplification (§4.5 names the Orthodox dispensations only). Input: Catholic tradition enabled, open December 2026. Fix: skip the Friday loop on the fixed solemnities — Dec 25 and Jan 1 at minimum, with Aug 15 and Nov 1 in the same list. Fix session: B6. →
- **C6** (L, CONFIRMED; B1) `lib/constants/fasting_calendar.dart:517` — the Orthodox weekly fast marks **Theophany (6 January)** and the other fixed great feasts when they land on a Wednesday or Friday: the only dispensations the builder knows are the four harți windows, and `free(at(1,1), 4)` ends on 4 January. Probe: `orthodox 2027 weekdayFast: 64 days, 2027-01-06 .. 2027-11-12`; 6 January 2027 is a Wednesday and the printed Romanian calendar the doc says these rules follow (§4.5) gives Boboteaza dezlegare la toate. The same gap reaches 29 June, 15 August and 8 September in the years they fall on a Wed/Fri. Fix: add the fixed great-feast dispensations (6–7 Jan at least) to `fastFree` before the weekly loop. Fix session: B6. →
- **C7** (L, CONFIRMED; B1) `lib/constants/fasting_calendar.dart:470` (`_applyForcedDays`) — a forced date inside a month turned off is marked as a generic **Personal fast** instead of the fast the tradition computed there: `FastingSchedule.keeps` dropped the tradition's entry (2026-10-26, a month off is never marked), so `out` has no key for the day and the forced pass fills it with `personalFast/oil`. Probe (December off, 20 December forced): `Dec20 forced -> [personalFast/oil]`. The method's own contract says "a day a tradition computed keeps its entry" — the day is marked, as `forceDates` must, but its period and regime (Nativity fast, strict) are lost and the day panel names the wrong fast. Fix: re-ask the tradition builders for the day's own `FastingInfo` and fall back to `personalFast` only when none claimed it. Fix session: B6. →
- **C8** (L, PLAUSIBLE; B1) `lib/models/calendar_event.dart:138` with `:512` — a one-time event whose `endDate` precedes its `startDate` never occurs at all, though the field's doc says "Ignored for one-time events (their start *is* their end)". Probe: `oneTime endDate before start -> false`. Unreachable from the editor (`event_editor_sheet.dart:1650` passes `null` unless recurring) and from `withExplicitDates`, but `CalendarEventService.importData` restores `endDateMs` verbatim beside any `ruleKind`, so an archive written by another build makes the event invisible with no surface that can see or repair it. Fix: skip the `endDateUtc` clamp when `rule is OneTimeRecurrence`, matching the doc. Fix session: B6. →
- **C9** (L, PLAUSIBLE; B1) `lib/services/recurrence_formatter.dart:55` — `countLabel` passes `event.startDate`, not `event.startDateUtc`, into `elapsedPeriods`, so an event whose `startDate` still carries a time or a local zone is labelled one period off (`DailyRecurrence.elapsedPeriods` is `day.difference(start).inDays`; `WeeklyRecurrence._weekIndex` can cross a week edge). Latent: both callers (`day_summary_resolver.dart:254`, `digest_notification_content.dart:139`) only hold DB-loaded events, which `_rowToEvent` normalises — but `startDateUtc` exists precisely to make this impossible, and a draft rendered through a `DaySummaryEntry` would hit it. Fix: `rule.elapsedPeriods(day, event.startDateUtc)`. Fix session: B6. →
- **C10** (L, CONFIRMED; B1) `test/constants/fasting_calendar_test.dart` — no test pins any tradition's **dates**: the groups are `weekly rule`, `months`, `weekday scope`, `catholic weekly rule is subtract-only`, `exception dates`, `configure invalidation`, `cellStyleFor eviction`, `resetConfiguration` — every one exercises `FastingSchedule`'s subtraction, none asserts that Great Lent 2026 runs 23 Feb – 11 Apr, that the Apostles' fast collapses to one day in 2027, or that Christmas is not a Catholic fast day, which is why C5–C7 survived. Fix: a dated-expectations group per tradition for 2026 and 2027 (the B1 probe's output is the oracle). Fix session: B6. →
- **C11** (L, CONFIRMED; B1) `lib/utils/presence_stats.dart` and `lib/constants/public_holidays.dart:500` — neither `PresenceAdherence` nor the holiday substitute/observance rules has a suite (`grep -rl adheren test/` finds nothing; the seven suites B1 ran pass, `00:01 +145: All tests passed!`, and none covers the trailing window, the streak walk, `_applyUkSubstitutes` or `_applyUsObservance`). Both units are dependency-free, so this is one pure test each. Fix session: B6. →
- **C12** (L, CONFIRMED; B1) `lib/constants/public_holidays.dart:500` — `_applyUsObservance` writes a key belonging to the **previous** year into the year it is building. Probe: `unitedStates 2022 … strays=[2021-12-31=newYear]`. Harmless today (every reader is keyed, and 2021's own map gets the same entry from the `year + 1` branch), so it is dead weight rather than a wrong answer — but any future caller that enumerates `forYear` lists a day outside the year. Fix: emit the 31 December entry only through the `year + 1` branch and drop the Saturday case for 1 January. Fix session: B6. →
- **C13** (L, PLAUSIBLE; B1) `lib/services/calendar_event_service.dart:140` — `upsert` appends the saved event to the end of `_cache`, breaking the start-date order `CalendarEventDao.getAll` documents as the store's contract ("Live events, in start-date order. The single read path for the whole feature") until the next reload. No consumer read in B1 depends on it (the bloc and the agenda sort per day, `yearSpansOf` is order-free), hence L. Fix: insert in place, or drop the ordering claim from the DAO's doc. Fix session: B6. →
- **C14** (M, PLAUSIBLE; B2) `lib/widgets/filter_preset_sheet.dart:588` (`onPick`) with `:265` (`create(name:, filters: widget.current)`), consumed by `lib/pages/calendar_page.dart:1455` and `lib/widgets/calendar_filter_sheet.dart:255` — a saved filter preset carries `panelShowsAll`, so applying one silently rewrites a panel preference that is not part of the lens. Everything else treats the field as outside the filter set: the sheet's "None" row deliberately goes through `current.cleared()`, which keeps it (`:527`, with the `///` saying why), it has no chip, and it is absent from `activeCount` and from `CalendarFilterSummary.facetsOf` — the record's words are "it can never be the reason something is missing". Input: turn **Show the whole day in the panel** on, then tap the app bar's saved-filters button (`calendar_page.dart:908`) and pick any preset saved before that — the day and timeline panels go back to the filtered day with nothing on screen saying so, nothing persisted as a choice and no chip to undo it; symmetrically a preset saved while it was on turns it on for a user who had it off. `inUse: preset.filters == current` (`:583`) also marks a preset as not in use when only this panel preference differs. Fix: pop `preset.filters.copyWith(panelShowsAll: current.panelShowsAll)` and normalise the field out when a preset is saved or updated, so a preset never carries it. Fix session: B6. →
- **C15** (M, PLAUSIBLE; B2) `lib/pages/calendar_page.dart:777` (`_loadSettings`) — the grid's filter restore has no replay, so it reverts a filter change the user made before it landed: `ChangeCalendarFilters(loaded.filters)` is dispatched once, unconditionally. This is the same defect review 3 found in the panel and slice 6b fixed *there* with `_replayOnto(stored, picked:)` (`docs/qa-pass-rework.md` §4 slice 6b); the page was left out. The write (`_persistFilters`) and the read (`getCalendarPageSettings()`) are independent, so the blob read before the user's write wins on screen while the store keeps the user's set, and the UI and the preference disagree until the next filter change. Input: cold start with a non-empty stored filter set and a slow `SettingsService.getInstance()` (the panel's own `///` at `calendar_bottom_panel.dart:136` measures that path at up to ~1.5 s cold); the user opens the Filters sheet and applies a change before `_loadSettings` returns. Reachable only through the sheet — the chip row is not mounted until `activeCount > 0` — so it needs two taps inside the restore window, which is the same window the panel's was. Fix: give the page the panel's mechanism — a `_filtersPicked` flag set in `_applyFilters`, a field-by-field replay onto the stored set before the dispatch, then persist the merge. Fix session: B6. →
- **C16** (M, PLAUSIBLE; B2) `lib/controllers/event_sheets_flow.dart:396` and `:424` — both date-picker call sites pass `dayLoad: (day) => eventsForDay(day).length`, the **filtered** day, so a busy day can look free on a scheduling surface. `CalendarDatePickerSheet._marker` (`lib/widgets/calendar_date_picker_sheet.dart:1373`) draws its one neutral bar from that count and its `///` calls it a "taken" signal; the skill's rule is that filters are render-time only — "a filtered event still occurs, exports and **counts**". Input: hide a category (or set Events → One-time, or any narrowing axis) on the grid, then open the event editor and tap a date — every day whose only events are filtered out shows no busy bar and the user schedules onto a day they were told was free; with Events → `none` the picker shows no busy bar at all. Lead-verified: the closures read `context.read<CalendarBloc>().eventsForDay` (`:390`, `:417`), and the bloc's unfiltered `allEventsForDay` exists beside it. Fix: both closures read `allEventsForDay(day).length`, so the picker's "taken" signal never inherits the grid's lens. Fix session: B7 (the two files are B4a's). →
- **C17** (L, CONFIRMED; B2) `lib/pages/calendar_page.dart:1974` (`markerBuilder`) against `:1826-1860` (the four cell builders) — one cell gives two answers to "is this day outside the month" in week and two-week format. `markerBuilder` computes `isOutside = format == CalendarFormat.month && …` (with a `///` claiming week rows "show every day at full strength"), while the cell's flag comes from *which builder table_calendar called*, and the package derives that with no reference to the format: `table_calendar-3.2.1/lib/src/table_calendar.dart:581`, `final isOutside = day.month != focusedDay.month;`, dispatched at `cell_content.dart:141`. Lead-verified: `outsideBuilder` passes `isOutside: true` unconditionally (`calendar_page.dart:1853`). So the number, chip, tint, edge stripe and rail fade to `outsideAlpha` 0.35 while the day's bars stay at full strength. Input: switch the grid to Week on a week spanning a month boundary — or let the keyboard collapse it (`:1083`, `format: keyboardVisible ? CalendarFormat.week : state.format`) — on a day in the adjacent month that carries events. Fix: make one of the two the source (pass the month-format gate into `_buildDayCell` as well, or drop it from `markerBuilder`) and assert the pair in `calendar_outside_fade_test.dart`. Fix session: B6. →
- **C18** (L, PLAUSIBLE; B2) `lib/bloc/calendar/calendar_bloc.dart:647` — the 512-entry day-cache cap is unreachable from the one path its own `///` names. The clear sits in `_evictColdDayCacheEntries`, called only from `_onChangeFocusedDay:823` and `_onSelectDay:798`, while the comment at `:636` says the cap "stays a backstop rather than disappearing: the date pickers and the day/timeline panels also call `eventsForDay`, on days that can land far outside the window with no focus change at all" — with no focus change the backstop never runs. Each such day is also outside `dayCacheWindowFor(state.focusedDay)`, so `_dayCandidates:445` falls back to the full `_visibleEvents` scan: one O(N) scan per day, 42 per picker month, run synchronously from `build` (`calendar_date_picker_sheet.dart:1373`). Input: open the editor's date picker and page through a year of months without closing it. Bounded in practice because the editor's save calls `_invalidateDayCache()`, hence L. Fix: enforce the cap inside `eventsForDay` on insert, or prune from the picker's exit. Fix session: B6. →
- **C19** (L, PLAUSIBLE; B2) `lib/widgets/calendar_bottom_panel.dart:540` (`_labelsFit`, called from `_PanelModeBar.build:584`) — the panel's mode bar measures three labels with a `TextPainter` on every day tap. `_PanelModeBar` is rebuilt whenever `_CalendarBottomPanelState.build` runs, and the panel's `buildWhen` is `!previous.samePanelInputs(current)` (`calendar_page.dart:1134`), which includes `selectedDay`; so every grid day tap, presence tick and description tick pays `Theme.of` + `MediaQuery.textScalerOf` + `Directionality.of` + `ButtonStyleButton.scaledPadding`, three `TextSpan` allocations, three `TextPainter.layout()` calls and a `dispose`. `flutter-principles` §2 is explicit that a `build` on a hot path constructs no new `TextStyle`. Neither budget suite sees it: `calendar_grid_rebuild_test.dart` counts state identity and `calendar_occurs_on_budget_test.dart` counts `occursOn` calls. Input: tap days across a month with the Day panel showing. Fix: memoize the `iconsOnly` decision on `(constraints.maxWidth, textScaler, localeName, labelLarge)`, or hoist `_PanelModeBar` above the panel's `BlocBuilder` so a selection change cannot rebuild it. Fix session: B6. →
- **C20** (L, PLAUSIBLE; B2) `lib/pages/calendar_page.dart:1505` (`_schedulePrewarm`) — the neighbour-month prewarm never re-checks that its month is still a neighbour. Each idle task re-checks `mounted` and that the state is loaded, then prewarms the **captured** `focusedDay ± 1`, while `_dayCandidates` builds its window from the **current** `state.focusedDay`; once the captured month is more than three months away every one of its 42 lookups falls outside `dayCacheWindowFor` and pays a full `_visibleEvents` scan, and the entries it writes are cold the moment they land. Input: fling the month pager through ten months — twenty tasks are queued (`Priority.idle` defers them, never drops them) and the ones that run after the fling settles do 42 full scans each, which is the opposite of what the method exists for. Fix: in the task body re-read `state.focusedDay` and return unless the captured month is still within `_prewarmMonthOffsets` of it. Fix session: B6. →
- **C21** (L, PLAUSIBLE; B2) `lib/bloc/calendar/calendar_bloc.dart:956` (`_onDeleteEvent`) against `_onCreateEvent:876` and `_onUpdateEvent:924` — the delete handler skips the money-ledger refresh the other two run, so `NoteMoneyLedgerService` keeps a ledger entry for a note no event links any more and no `revision` is bumped. Nothing user-visible diverges today (`monthNetFor:519` folds `_visibleEvents`, from which the event is gone, and `_invalidateDayCache():972` clears `_monthNetCache` anyway), so this is a stale in-memory map and an asymmetry between three handlers that otherwise share one shape. Input: delete the only event linking a note that carries ledger entries — the ledger holds that note until the next load or the next create/update. Fix: refresh the ledger with `service.events` after the delete, as create and update do. Fix session: B6. →
- **C22** (L, PLAUSIBLE; B2) `lib/widgets/calendar_day_rail.dart:260` against `:272` — the rail's base band and its mark split ask "are there marks?" with two different predicates. `baseHeight` is keyed on `hasMarks = marks.isNotEmpty && maxMarks > 0`, while `_split` can return `visible: 0` for the same inputs when `capacityFor(height - baseHeight, style) == 0`; when they disagree `_lines` gets `markSlots == 0` *and* `baseHeight == baseBandFor(height)`, so the lane draws a half-height base band with the other half empty — against the `baseShare` doc's promise that "with no marks at all the band takes the whole lane, and the result is pixel-identical to the stripe the cell used to draw". Input: a lane short enough that `floor((height − height/2) / 3) == 0`, i.e. `height < 6`, on a fasting day carrying marks. Latent: `rowHeightFor` floors the row at 52, so the `line` lane is ≥ 41 and capacity ≥ 6 — reachable only by lowering the row floor or adding a style with a taller strip. Fix: derive `baseHeight` from `split.visible > 0`, so one answer drives both. Fix session: B6. →
- **C23** (L, PLAUSIBLE; B2) `lib/bloc/calendar/calendar_bloc.dart:366` (`allEventsForDay`) — the delegation to the filtered day is gated on `isEmpty`, which is `activeCount == 0`, and `activeCount` (`calendar_grid_filters.dart:165`) counts every **layer** that is off. A layer removes a day annotation, never an event, so with only `showMoney: false` set the two day answers are identical — yet the delegation is skipped, `_unfilteredDayCache` fills, and each selected day pays a full O(N) `allEvents` scan instead of the memoized narrowed one. The class doc at `:107` claims the second map "stays **empty** while nothing is filtered"; a layer off breaks that claim. Input: turn the money layer off, turn "show the whole day in the panel" on, tap through days. Fix: gate on whether any axis narrows events or occurrences (`_narrowsEvents || hasOccurrenceAxis`, exposed as a getter) rather than on `isEmpty`. Fix session: B6. →
- **C24** (L, CONFIRMED; B2) `lib/models/calendar_grid_filters.dart:142` — `hasOccurrenceAxis`'s doc sentence states the inverse of what the getter returns: the `///` reads "True when **no** axis needs the *day* to decide — i.e. `eventsForDay` can trust the pre-filtered list wholesale" and the body is `bool get hasOccurrenceAxis => missedOnly;`, true exactly when an axis *does* need the day (lead-verified at the file). Both callers use the correct meaning (`calendar_bloc.dart:343`, `:1054`), so this is wording — but it is the sentence a reader of `_invalidateIfPresenceIsMembership` goes to for the rule. Input: none, reading. Fix: reword the first sentence to "True when an axis needs the *day* to decide"; keep the rest. Fix session: B6. →
- **C25** (L, CONFIRMED; B2) three paths in B2's file set have no suite. (a) `lib/pages/calendar_page.dart:777` — nothing covers the grid-filter restore racing an early `_applyFilters` (C15), while the panel's twin *is* pinned by `test/widgets/calendar_bottom_panel_mode_test.dart`, whose drift `QueryInterceptor` harness applies here unchanged. (b) `test/widgets/calendar_outside_fade_test.dart` builds `CalendarDayCell` directly with an explicit `isOutside` (`:37`, `:45`), so neither of the page's two derivations (C17) is exercised and there is no week-format case. (c) `lib/widgets/calendar_bottom_panel.dart:540` — the mode bar's measurement cost (C19) is outside both budget suites. Fix: one widget test per bullet — a held settings read proving an early filter change survives; one `format: week` case asserting the cell and its bars fade alike; a counter around `_labelsFit`. Fix session: B6 (with C15, C17 and C19). →
- **C26** (L, PLAUSIBLE; B2) `lib/pages/calendar_page.dart:1192` — a `ValueNotifier` is written from inside `build`: `if (trace == null) _fabTrace.value = null;` sits in the FAB's `ListenableBuilder` builder. It does not throw today because the only listener is the `ValueListenableBuilder` inside `CalendarAddFab`, a descendant of the element being built, so `markNeedsBuild` is in scope — but one new listener on `_fabTrace` turns it into "setState() or markNeedsBuild() called during build". Input: turn the add-button trace developer option off while the calendar is open. Fix: clear the notifier from the `DevOptions` listener or the toggle's own handler, not from `build`. Fix session: B6. →
- **C27** (M, PLAUSIBLE; B3a) `lib/services/overview_view_service.dart:270` — a saved view's period is re-encoded against `DateTime.now()` on every `update`, while the `OverviewPeriod` it re-encodes was decoded at the last `_load`, so a **"This year" view silently becomes a pinned past year** when the two years differ. `OverviewView.fromJson` collapses `{kind: thisYear}` and `{kind: year, year: Y}` into the same `OverviewYearPeriod(Y)` (pinned by `test/models/overview_view_test.dart:67`), and `_toCompanion` writes `thisYear` only when `year == today.year`. Input: the process starts on 31 Dec 2026 (the service's `_load` decodes `thisYear` → `OverviewYearPeriod(2026)`), the app is resumed on 2 Jan 2027 with no view written in between, the user renames that view in the views sheet (`overview_view_sheet.dart:264`, `view.copyWith(name:)`) — the stored blob flips to `{kind: year, year: 2026}` and the view lists 2026 for good; `_updateToCurrent` and `_saveCurrent` have the same shape through a stale page `_today`. Fix: keep the stored period kind across a decode (a `rollsWithToday` flag on the view, or re-`_load` before a write), so only an explicit re-pick can pin a rolling year. Fix session: B6. →
- **C28** (M, PLAUSIBLE; B3a) `lib/pages/calendar_overview_page.dart:3096` — month mode's sliver takes its `childCount` from the **field** `_rows` while the row builder beside it was captured from the page's last month build, so a rebuild of that inner `Builder` after the mode has moved on indexes past the captured list and `AgendaDayListRowBuilder.build` throws on `rows[index]` (`agenda_day_list_rows.dart:425`). `_buildList` captures both (`:2886-2888`, with the `///` saying exactly why — "the outgoing list of a mode cross-fade keeps building rows while it fades, and the fields by then hold the next mode's"); `_buildMonthBody` captures `rows`, `selected`, `empty` and `bucket` but not the count, and `_buildPickedDayRow:3123` reads `_rows.isEmpty` the same way (lead-verified: `final rowCount = layout.rows.length;` at `:2888` against `childCount: _rows.length + leadingRows` at `:3096`). Input: Month mode with the Search row open and the keyboard part-way up, tap the **List** chip — the keyboard goes on animating, `MediaQuery.viewInsetsOf` rebuilds the outgoing month body's `Builder` inside the `AnimatedSwitcher`'s cross-fade, `_rows` is by then the list's longer rows and the sliver builds an index the captured month builder has no row for. A rotation during the same cross-fade is the second trigger. Fix: capture the count beside the builder (`final count = _rows.length;` above the `Builder`, as `_buildList` does), and read `count` in `_buildPickedDayRow`'s `last:` too. Fix session: B6. →
- **C29** (L, PLAUSIBLE; B3a) `lib/pages/calendar_overview_page.dart:885` and `:907` — `_resolve` and `_resolveMarks` dereference `_occurrenceMask[key]!` / `_markedKept[...]!` for the month of every occurrence the scan returned, but the only guarantee that an occurrence lands inside the requested span is a **debug `assert`** in the store (`agenda_month_store.dart:158`, `:180`). In a release build an occurrence one day outside the run's span is a "Null check operator used on a null value" on the resolve path, which runs inside `setState`. Input: any future change to `EventAgenda.occurrencesInRange`'s boundary handling (the asserts exist precisely because it has been wrong before); not reachable from today's engine. Fix: `(_occurrenceMask[key] ?? 0) | …` and `_markedKept.putIfAbsent(key, …)`, so a stray day is dropped rather than fatal. Fix session: B6. →
- **C30** (L, PLAUSIBLE; B3a) `lib/pages/calendar_overview_page.dart:2014` — in Year mode, **"This year" from the Period menu does nothing while the scroll is already inside this year's section**. `_setPeriod` short-circuits on `period == _period` (`setState({})` + persist, no `jumpToYear`), and `_onYearScrolled:1572` has already set `_period = OverviewYearPeriod(_year)`; the nav's Today slot is disabled in the same state (`_buildYearNav:3159`, `_year == _today.year ? null : …`). Lead-verified at `:2013-2019`: the short-circuit's own `///` names this very scenario ("This year picked after scrolling back to this year") and handles only the persistence half. Input: Year mode on this year, drag down ~60 % of the section (the title still reads this year — `yearAtOffset` only flips at half a header before the next), open the title's Period menu, pick **This year**: nothing scrolls, so no control brings this year's header back to the top. §3.14 reads "This year → `_setPeriod` → `jumpToYear(_today.year)`". Fix: in Year mode land the scroll even on an unchanged period — `if (inYear) _yearScroll.jumpToYear(_firstYearOf(period));` inside the short-circuit branch. Fix session: B6. →
- **C31** (L, CONFIRMED; B3a) `test/services/overview_view_service_test.dart` — nothing covers a write crossing the year boundary, which is why C27 survived. The suite's cases are `a fresh database has no views`, `a saved list round-trips through the payload exactly`, `names are trimmed…`, `matching` ×2, `update rewrites in place…`, `reorder` ×3, `delete…`, `create refuses past the limit`, `a database switch drops the singleton`, `backup` ×4 — none injects a clock, and the one year-roll case in the tree (`test/models/overview_view_test.dart:67`) only exercises the **decode** direction (`fromJson(today: 2027)` on a blob written in 2026). Fix: one service test that loads the cache with `today` in year Y, renames, and asserts the stored payload is still `{'kind': 'thisYear'}` (with C27). Fix session: B6. →
- **C32** (L, PLAUSIBLE; B3a) `lib/widgets/agenda_period_nav.dart:223` — `_subtitleHeight` builds and lays out a `TextPainter` on **every build** of the nav, uncached, while the title's twelve candidates next to it are behind a 32-entry LRU (`_yearTitleHeights:64`) precisely because "the row is rebuilt by every `setState` of the sheet or page above it". The overview rebuilds the nav on every page `setState` — each year-scroll top-year change, each list run, each keystroke's `_applyQuery`, each presence bump — and the day list sheet shares the widget. `flutter-principles` §2 is the same rule C19 was filed under for `calendar_bottom_panel.dart:540`. Input: a fling through a decade in Year mode, or a long period resolving in runs. Fix: key the count's one-line height on `(scaler, style, direction)` in a small static cache beside `_yearTitleHeights` — it does not depend on the string. Fix session: B6. →
- **C33** (L, PLAUSIBLE; B3a) `lib/pages/calendar_overview_page.dart:2677` with `:2503` and `:2698-2699` — the page's `build` re-folds four things that only change on navigation: `_totalsLabel` walks `CalendarCategories.all` and allocates the caption's strings, `_buildViewsButton` runs `OverviewViewService.matching` (a linear scan of up to 50 views, each a `setEquals` over the allowlist), and `_buildListNav` calls `_steppedPeriod(-1)` and `_steppedPeriod(1)` — two full `OverviewPeriod.resolve` + clamp passes — only to decide whether two chevrons are enabled. Input: every page `setState` above (the same hot path as C32); none of it is in `overview_list_benchmark_test.dart` or `overview_years_benchmark_test.dart`, which count scans and tiles, not build work. Fix: fold the totals label, the view match and the two stepped periods in `_recompute` / `_setOptions` into fields, as `_titleTemplates` already is. Fix session: B6. →
- **C34** (L, CONFIRMED; B3a) `lib/pages/calendar_overview_page.dart:1132` — `_buildListRows` reverses `shown` a **second** time under Newest first, so `listed` comes out oldest-first while the rows it stands for read newest-first. Lead-verified: `shown` is filled by `for (final day in newestFirst ? days.reversed : days)` at `:1106` and consumed by `for (final day in newestFirst ? shown.reversed : shown)` at `:1131`. Harmless today — every consumer is order-free (`_tally`, the kept/missed counts, and `_EventFold.add`, which takes min and max of the days, `agenda_day_list_rows.dart:297`) — but it contradicts the method's own `///` ("in reading order") and would silently break the per-event fold the day a consumer starts trusting the order. Input: Newest first with One per event over a multi-month period. Fix: `for (final day in shown)`, since `shown` is already in reading order. Fix session: B6. →

- **C35** (M, PLAUSIBLE; B3b) `lib/widgets/agenda_day_list_sheet.dart:482` with `:607` and `lib/widgets/agenda_list_view.dart:725` — the day list sheet freezes its inputs for its whole life and its pencil then saves the **pre-reload copy** of an event. The sheet holds `late final _index` / `late final _store` and has no `didUpdateWidget` at all (`:161-163`); `_resolverFor` captures `final events = widget.events` once, at open (`upcoming_agenda_view.dart:895`); every row's `onEdit` is `() => onEditEvent(occurrence.event, occurrence.day)` over that captured `CalendarEvent` (`agenda_list_view.dart:725`, `:1029`), and `_popEdit(VoidCallback edit)` pops the closure itself, which `calendar_page.dart:1152` runs as `_sheets.openEditor(initialEvent: event)` — and `EventSheetsFlow.editorSheet` hands `initialEvent` straight to `EventEditorSheet.show` without re-reading it from the bloc (`event_sheets_flow.dart:413-420`, lead-verified). Input: a summary card's drill-down is open; `_appReloadCalendar` replaces the eleven calendar tables under it (`docs/cloud-sync-phase-02-own-space.md` §3.5) or an alert reconcile edits the event; the user taps that row's pencil and saves. The remote's newer `name` / `time` / `rule` / `categoryId` are overwritten by the sheet's old object and the local save mints a newer HLC, so it wins the merge — a silent lost update; if the event was tombstoned in the same reload, the save resurrects it. Not `R77` (that is the merge-side half of a concurrent edit against a tombstone, in a file B3b does not touch); the same capture shape exists behind any open editor app-wide, but there it is the user's own in-flight edit, while here it is a **list the user believes is current**. Fix: have `_popEdit` carry `(eventId, day)` instead of a captured `VoidCallback`, and let `calendar_page`'s `onEditEvent` re-read the event from `CalendarBloc` before opening the editor. Fix session: B6. →
- **C36** (L, CONFIRMED; B3b) `lib/widgets/upcoming_agenda_view.dart:1083-1087` — the custom-range summary chip names a window the agenda never scanned. The chip labels from the raw `filters.customStart!` / `customEnd!` while the header line right above it labels from `_resolved` (`:1178`), and `_resolved` is clamped by `EventAgenda.resolveRange` to `maxRangeDays = 366` (`event_agenda.dart:941-946`: `requestedEnd.isAfter(maxEnd) ? maxEnd : requestedEnd`). The filters sheet opens `pickRange` with `firstDate: 2000-01-01` and `lastDate: 2100-12-31` (`agenda_filters_sheet.dart:268-269`), so a longer range is pickable. Input: pick 2026-01-01 → 2027-06-30; the header reads "Jan 1 – Dec 31, 2026" (the 366 days actually scanned) and the chip under it reads "Jan 1, 2026 – Jun 30, 2027", and the chip is the thing the user reads as the explanation of the list. The feature doc's addendum states the rule the chip breaks ("a label claiming otherwise would misreport the results"). CONFIRMED is static: both label sites and the clamp were read (lead-verified); the two-line mismatch was not screenshotted. The filters sheet's own Period value (`:314-321`) carries the same raw label but has no access to the resolved window, so the chip is the fixable half. Fix: label the chip from `_resolved`, as the header does, or clamp `pickRange`'s `lastDate` to `start + maxRangeDays - 1`. Fix session: B6. →
- **C37** (L, CONFIRMED; B3b) `lib/widgets/agenda_day_list_rows.dart:609-613` — `_eventSpan` constructs one or two uncached `DateFormat`s per row, per frame (`DateFormat.yMMMd(localeName)`, plus `MMMd` or a second `yMMMd`), on the overview's per-event rows, which are the whole body in that mode. It is the **only** uncached construction in the twelve files: `grep -n DateFormat` over the six widgets returns exactly these three raw calls, while `agenda_list_view.dart:562-575` holds eight per-locale caches whose own `///` says why ("it parses a skeleton on construction and every visible day header would otherwise rebuild one") and `day_summary_panel.dart:63` does the same (lead-verified). This is the `calendar-events` skill's "never per-row `DateFormat(...)`" rule, the same rule C19 was filed under. Fix: add a `yMMMd` cache beside the others on `AgendaListView` (`_rangeFormatCache` already covers `MMMd`) and read both from there. Fix session: B6. →
- **C38** (L, PLAUSIBLE; B3b) `lib/widgets/day_timeline_view.dart:85-113` — the timeline's layout memo is keyed on `identical(_layoutForEvents, events)`, `missedDisplay` and `EventPresence.revision`, but **not on `widget.day`**, although under `CalendarMissedDisplay.hidden` the memoized value is computed through `_isMissed(event)` (`:125-127`), which reads `widget.day`. Trigger would be a `day` change with an `identical` events list. Latent today — `CalendarBloc.eventsForDay` returns a fresh `List.unmodifiable` per day key, so a day change always changes the list identity, and `day_timeline_layout_memo_test.dart` pins only events, `missedDisplay` and an unrelated rebuild. Filed because question 4 asks whether the memo keys everything it depends on: it does not, and the field it misses is the one its own `///` at `:77-84` is about. Fix: add `DateTime? _layoutForDay` to the memo key. Fix session: B6. →
- **C39** (L, PLAUSIBLE; B3b) `lib/widgets/day_timeline_view.dart:240-245` — nothing clamps the drawn column count, so a heavily overlapped day yields untappable and then negative-width blocks: `left: gutterWidth + block.column * (trackWidth / block.columnCount)`, `width: (trackWidth / block.columnCount) - columnGap`, and `day_timeline_layout.dart:114-130` gives every block in a cluster the cluster's own `columnCount`. Input: one day with N mutually overlapping timed events. On a 360 dp phone `trackWidth ≈ 308`: at N = 30 a block is 6.3 dp wide, at N = 77 it is 0, and above 77 the width is negative — `RenderStack` then lays the child out with `BoxConstraints.tightFor(width: <0)`, which fails `debugAssertIsValid` in debug and is unchecked in release. Below that the blocks are reachable only in theory (a 6 dp target cannot be hit, which is the functional half D2 A still admits). The threshold is computed, not rendered. Fix: clamp the drawn column count (`min(columnCount, trackWidth ~/ (minBlockWidth + columnGap))`) and let the overflow share the last slot. Fix session: B6. →
- **C40** (L, PLAUSIBLE; B3b) `lib/utils/day_timeline_layout.dart:101-105` — the timeline's event sort is not total: `startMinute` ascending, then `_displayEnd` descending, with no final tie-break, and `List.sort` is not stable in Dart. Two events with the same start **and** the same display end can therefore exchange `column`, and so exchange on-screen position, between two solves of the same day. This is why `agenda_list_view.dart:243-249` tie-breaks summary cards on the insertion index and why `EventAgenda.compareWithinDay` ends with `titleFold` then `id`. Narrow: the memo means a day is solved once per events-list identity, and Dart's insertion-sort path is stable in practice for short ranges, so it needs a day with ≳32 timed events. Fix: end the comparator with `titleFold` then `id`, as `compareWithinDay` does. Fix session: B6. →
- **C41** (L, PLAUSIBLE; B3b) `lib/widgets/upcoming_agenda_view.dart:405` — for the 200 ms of the query debounce the window, the header label and the rows disagree. `didUpdateWidget` calls `_updateRange()` at the top, before the branch at `:484-493` that debounces the scan (the `///` there says "Refresh the shared window before any branch below reads it"), and in `rollingDays` mode `_updateRange` widens `rawEnd` to `rawStart + 365` the moment the query becomes non-empty (`:558-566`). Input: type the first character of a query with a 30-day rolling window — `_resolved` is already the 366-day window, so the header line at `:1178` reads the wide range while `_rows` are still the 30-day scan's. The sharper variant: tapping a summary card's "show all" inside that window opens `AgendaDayListSheet` with `windowStart`/`windowEnd` = the wide `_resolved` (`:1025-1026`) but `list.entries` from the narrow scan, so list mode shows pre-query entries while month mode resolves through `_resolverFor`, which calls `_syncQuery()` and uses the new query — the two halves of one sheet disagree. Fix: snapshot `_resolved` into a `_scannedRange` inside `_recompute` and label the header from that, or move `_updateRange()` into each branch so the wide window lands with the scan that uses it. Fix session: B6. →
- **C42** (L, CONFIRMED; B3b) `lib/utils/agenda_day_list_index.dart:123-139` — the "month outside the window" branch is dead, and `windowMaskForMonth` means the **extended** window, not the requested one. `start` / `end` are first widened by any stray entry (`:82-83`), `months` is then enumerated from `start` to `end` (`:111-118`), and `startOrder` / `endOrder` are computed from the same widened `start` / `end`, so `order < startOrder || order > endOrder` at `:128` can never hold for a month in `months` (lead-verified against both loops). The suite's "a month entirely outside the window carries no window bits" passes through the `?? 0` fallback at `:174`, not through this branch. The consequence for a reader is the name: a stray entry's whole month-slice counts as in-window. Fix: drop the dead branch and say in the `///` that the mask is over the extended window (or keep the requested bounds in two extra fields if a caller ever needs them). Fix session: B6. →
- **C43** (L, PLAUSIBLE; B3b) `lib/widgets/agenda_day_list_sheet.dart:239-241` — a reversed window crashes the sheet in release instead of being refused. `_initialMonth` reads `_index.months.first` from `initState`, and the only guard is `AgendaDayListIndex.build`'s `assert(!windowEnd.isBefore(windowStart))` (`agenda_day_list_index.dart:66-69`), which is stripped in release; with `windowEnd < windowStart` the months loop yields an empty list and `.first` throws `StateError` while the modal is being built — a blank sheet over the calendar. Today's callers (`_resolved` from `resolveRange`, the overview's period) cannot produce it, so this is defence only — the same shape as C29. Fix: have `build` clamp `windowEnd = windowStart` when it precedes it, so `months` always holds at least one month without relying on an assert. Fix session: B6. →
- **C44** (H, CONFIRMED; B4a) `lib/widgets/event_editor_sheet.dart:1810` with `:669` and `:1082` — editing the **shared** description of a per-occurrence event silently forks the day the editor was opened from and pins that day to the *pre-edit* text. `_dayBuffer` is seeded in `initState` as `storedOverride ?? _templateBuffer` (`:668-669`) — the old template when the day has no row — and is reassigned nowhere else but `_setScope`, `_resetDayToTemplate` and `_syncScopeToRule`, so typing in the shared scope never moves it; `_dayText` reads it while the day scope is inactive (`:1081-1082`). `_onSave` calls `_resolveOccurrenceOutcome(_templateText.trim())` — the **new** text — and the copy-on-write guard is `if (!_dayMaterialized && dayText == template) return (null, null);` (`:1810`), comparing the **old** template against the new one: they differ, so the function returns `(day, dayText)` and `EventSheetsFlow._onSaved` dispatches `SetOccurrenceDescription` for it (`event_sheets_flow.dart:565-577`). The seed's own `///` states the rule it breaks: "Only an edit that actually diverges materializes a row" (`:655-657`). Input: an event with `perOccurrenceDescriptions: true` and a multi-occurrence rule, no row yet for the day you opened from; day cell → detail sheet → Edit → change the description in the "All days" scope → Save. Every other occurrence gets the new text; this day keeps the old one for good, as a synced `calendar_event_occurrences` row (`eventId|dayEpochMs`) the user never asked for and no surface explains. Fix: compare `dayText` against the template **as the day was seeded from it** — keep the `initState` snapshot in a field, or a `_dayTouched` flag set only by `_setScope` and the day-scope keystrokes — so an untouched, unmaterialised day writes nothing. Fix session: B7. →
- **C45** (H, CONFIRMED; B4a) `lib/bloc/calendar/calendar_bloc.dart:906-911` with `lib/widgets/event_editor_sheet.dart:1715` and `lib/controllers/event_sheets_flow.dart:413-440` — the editor's Save resurrects an event a sync pull tombstoned while the sheet was open. `_onUpdateEvent` has **no** existence guard, where `_onDeleteEvent:961-962` has `final hasEvent = current.allEvents.any((e) => e.id == event.eventId); if (!hasEvent) return;`, so `service.upsert(normalized)` reaches `CalendarEventDao.upsert`'s update branch, which skips its own `changesNothing` short-circuit for a deleted row (`if (!existing.isDeleted && …)`) and writes `isDeleted: const Value(false), deletedAt: const Value(null)` under a fresh stamp (`calendar_event_dao.dart:74-85`). The editor cannot notice either: `base = widget.initialEvent` is captured at mount, there is no `didUpdateWidget`, the sheet is built inside `showModalBottomSheet`'s builder, and `editorSheet` hands `initialEvent` straight to `EventEditorSheet.show` without re-reading the bloc. Input: open the editor on an event; `_appReloadCalendar` (`app_sync_apply_hooks.dart:253-273`) merges a remote tombstone for it; press Save. The event comes back on every device with the local copy's fields and a newer HLC — the remote delete is lost. **Lead-verified** against the three code halves; distinct from C1 (a settings-page wipe that signals no bloc), from C35 (a stale *list*, fixed in `agenda_day_list_sheet.dart`) and from `R77` (the merge-side half, in the DAO): here the capture and the missing guard are the editor's own entry path. Fix: have `editorSheet` re-read the event by id from `CalendarBloc.state.allEvents` before opening and bail with a notice when it is gone, and give `_onUpdateEvent` the same `hasEvent` guard `_onDeleteEvent` has. Fix session: B7. →
- **C46** (H, CONFIRMED; B4a) `lib/widgets/event_editor_sheet.dart:713` with `:1783` and `lib/database/daos/event_alert_dao.dart` (`replaceForEvent`) — the editor's alert set is a whole-set write built from a snapshot taken at mount, so an alert that arrived by sync under the open sheet is tombstoned on Save. `_alerts = List<EventAlert>.of(EventAlerts.alertsFor(initial.id))` is read once in `initState` (`:713`) and reassigned afterwards only by the sheet's own add/edit/remove handlers (`:1383`, `:1420`, `:1440`, `:1445`, `:1457`); `_onSave` passes `List<EventAlert>.unmodifiable(_alerts)`, which `CalendarBloc._persistAlerts` hands to `EventAlertService.replaceForEvent` → the DAO, whose loop tombstones every existing row whose id is not in `keep` (`isDeleted: true`, a new stamp, `version + 1`). Input: open the editor on an event; a pull merges a new alert for it (`_appReloadCalendar` reloads `EventAlertService`); press Save without touching the alert rows — the merged alert is deleted on every device, having never been on screen. The record's LWW decision covers the *columns of the event row*; this deletes rows the user never saw. **Lead-verified** against `event_editor_sheet.dart:713`, the service and the DAO. Touches B4b's remit (the editor's alert rows) and is filed here because it is question 1's save path; B7 may merge it with a B4b id. Fix: re-read the own-alert set from the facade at Save time and union in any id the sheet never showed — or re-seed `_alerts` from `EventAlerts.alertsFor` while `_alertsTouched` is still false and the facade's revision moved. Fix session: B7. →
- **C47** (M, CONFIRMED; B4a) `lib/widgets/event_editor_sheet.dart:1952` (`_fingerprint`) with `:1195-1196` (`_effectiveSkippedDays`) — a sync reload that touches the event's skip rows makes an **untouched** editor claim unsaved changes. `_fingerprint()` folds in `_effectiveSkippedDays`, which with `_skippedDays == null` reads the **live** facade `EventSkips.daysFor(id)` (`event_skips.dart:72-73`), while `_initialFingerprint` was captured at the end of `initState`; `EventSkipService.reload()` republishes that map wholesale on every calendar pull (`app_sync_apply_hooks.dart:263`). Every other input in the fingerprint is a snapshot — this one alone is live. Input: open the editor, type nothing, let a pull merge a skip (or an un-skip) for this event, press ✕ or back — the discard dialog appears with nothing to discard, and the guard has taught the user it lies. The `event-editor-redesign-roadmap.md` deviations block made the skipped days unconditional against a *snapshot*, not against a facade. Fix: snapshot the effective skip set once in `initState` into a field and fingerprint that, leaving `_skippedDays` as the only thing that can move it. Fix session: B7. →
- **C48** (M, CONFIRMED; B4a) `lib/controllers/event_sheets_flow.dart:588-594` (`_dispatchSkipResult`) with `lib/bloc/calendar/calendar_bloc.dart:1104-1151` — one Save that changes N cancelled days fans out into N bloc events, N DAO transactions with N HLCs, N `_invalidateDayCache()` calls, N alert reconciles and N state emits. The two loops dispatch one `SetOccurrenceSkipped` / `ClearOccurrenceSkipped` per day of the diff; each handler awaits the service, writes one row, bumps `membershipRevision` and fires `_reconcileAlerts(…, occurrenceChanged)` unawaited. Input: open Skipped days on a weekly event, select a term's worth of days (30–50), Save — the grid and the agenda rescan 30–50 times in a row, the outbox gains 30–50 rows and the OS gets 30–50 reconcile passes. **This is also question 1's answer on the stamps:** a save is no longer two HLCs but **1 (event) + 1 (alerts) + 1 (day description) + N (skips)**, which is worse than the state `docs/cloud-sync-readiness-roadmap.md:1068-1074` left as found. Fix: one `SetOccurrenceSkips(eventId, Set<DateTime> next)` event writing the diff in a single DAO transaction under one stamp, with one invalidate, one reconcile and one emit. Fix session: B7. →
- **C49** (M, PLAUSIBLE; B4a) `lib/widgets/event_editor_sheet.dart:1799` with `lib/controllers/event_sheets_flow.dart:565-577` — a save that moves the event off the day the editor was opened from still writes that day's per-occurrence row, creating an orphan the save itself made unreachable. `_resolveOccurrenceOutcome` keys on `widget.occurrenceDay`, which is never re-checked against the rule the form is about to save; the flow's `_occurrenceSurvives` (`:255-263`) correctly refuses to *reopen* the detail sheet on such a day, but the write has already been dispatched. Input: open the editor from an occurrence of a per-occurrence event, change the start date (or the repeat kind, or the Until date) so that day no longer occurs, Save — a `calendar_event_occurrences` row for a non-occurring day is written and synced, invisible to every surface (`OccurrenceDescriptions.descriptionFor` is only ever asked about days that occur). This is the *creating* half of the orphan question; a skip or occurrence row surviving a rule change and resurfacing when the rule returns is by design (`calendar_event_service.dart:160-163`). Fix: in `_resolveOccurrenceOutcome`, return `(null, null)` unless the rule being saved still occurs on `widget.occurrenceDay` — and `(day, null)` where a row already existed, so the orphan is cleaned rather than created. Fix session: B7. →
- **C50** (M, CONFIRMED; B4a) `lib/widgets/event_editor_sheet.dart:1890` (`_pickRepeat`) with `:1183-1188` (`_pickDate`) and `lib/widgets/event_repeat_sheet.dart:204-221` — §6.4's "Until date ≥ start date" is enforced on one path only, and a reachable sequence saves `endDate < startDate`, which makes the event never occur again (`calendar_event.dart:507-509`). `_pickDate` drops `_endDate` when it falls before the new start (`:1186-1188`); `_setOneTimeDates` (`:1861-1869`) moves `_date = sorted.first` and does **not**; `EventRepeatSheet._pickEndDate` floors only the picker (`initialDate`, `firstDate`) at `widget.startDate` and `EventRepeatDraft.isValid` (`event_repeat_sheet.dart:73-74`) never compares the two, so an untouched stale `endDate` is handed straight back and `_pickRepeat` assigns `_endDate = result.endDate` with no comparison. Input, **lead-verified** against the four sites: a recurring event with Until = 10 Mar and start 1 Mar → Repeat → "Does not repeat" (`_endDate` is kept, merely unused while one-time) → the Dates row → pick a set starting 20 Mar (`_date = 20 Mar`, `_endDate` still 10 Mar) → Repeat → Weekly, without touching the Until row → Save: `effectiveEnd` = 10 Mar against a 20 Mar start, and the event occurs on no day at all. Fix: clamp in `_pickRepeat`'s `setState` — `if (_endDate != null && _endDate!.isBefore(_date)) _endDate = null;` — and in `_setOneTimeDates`, so the rule holds whichever row moved last. Fix session: B7. →
- **C51** (M, CONFIRMED; B4a) `lib/widgets/event_editor_sheet.dart:1885-1894` (`_pickRepeat`) — switching a multi-date one-time event to a recurring rule keeps its extra dates alive in hidden draft state, and switching back silently restores a date set the user believed they had replaced. `_additionalDates` is reassigned only by `_setOneTimeDates`, `_pickDate` and `_initRecurrenceFrom`; `_pickRepeat` sets `_mode = recurring` and leaves the list, so the WHEN group stops showing it while `_buildRule()` ignores it in the recurring branch (`:1823-1831`) — and a later "Does not repeat" rebuilds the whole `SpecificDatesRecurrence` from `{_date, ..._additionalDates}`. **Lead-verified** against `_buildRule` and the three assignment sites. Input: a one-time event with five dates → Repeat → Weekly → Repeat → Does not repeat → Save: the event is pinned to the five old dates again, with no row having shown them since the first switch. Fix: clear `_additionalDates` when `_pickRepeat` turns the form recurring (the alternative — keeping the bundled Dates row visible while they exist — changes the WHEN group's anatomy, so take the clear and say so in the record). Fix session: B7. →
- **C52** (L, PLAUSIBLE; B4a) `lib/widgets/event_editor_sheet.dart:358` and `:1843-1845` (`_onBodyScroll`) against `lib/widgets/form_rows.dart:734-749` (`FormHeaderHairline`) — the editor's header hairline is fed by a bare `ScrollController` listener, the exact pattern the house primitive exists to replace: "A scroll view whose content gets shorter under it — the keyboard going down over a body that no longer needs to scroll — corrects its offset without telling a scroll controller's listeners, so a hairline fed by a listener alone stayed on over a body at its top." Input: scroll the form down, focus the description (the bar appears, the body shrinks), dismiss the keyboard with system back — the body snaps to its top and the 1 px hairline stays drawn. The symptom is visual, so this sits at D2 A's boundary; it is filed because what it diverges from is a primitive's own written contract, not the UI language, and the owner may strike it. Fix: wrap the body's `SingleChildScrollView` in `FormHeaderHairline.watch` and hand the header `scrolled` from it, dropping `_headerScrolled` and `_onBodyScroll`. Decision 2026-10-28: kept, built beside C46. Fix session: B7. →
- **C53** (L, PLAUSIBLE; B4a) `lib/widgets/event_repeat_sheet.dart:483` — the weekday circles' letters are derived with a local-midnight `add(Duration(days: n))`, the trap the memory note names: `final monday = DateTime(2024, 1, 1);` then `monday.add(Duration(days: weekday - 1))` for the seven cells. A `DateTime(y, m, d)` is local midnight and `add` is an absolute shift, so a DST transition inside that window would render the previous day's letter and `DateFormat.EEEE` name — and a wrong weekday circle is a wrong `WeeklyRecurrence`. No IANA zone transitions on 1–7 January, so it is unreachable today; filed as the latent half. Fix: `DateTime(2024, 1, weekday)` — 1 Jan 2024 is a Monday, so the day of month and the ISO weekday coincide and no `add` is needed. Fix session: B7. →
- **C54** (L, PLAUSIBLE; B4a) `lib/widgets/event_editor_sheet.dart:1536-1545` (`_loadSheetSettings`) — the late settings read re-baselines the dirty fingerprint only when the form was clean at that instant, so the seeded default alert can end up folded into one side of the comparison and not the other. `final wasClean = !_isDirty;` is computed **before** the `setState` that runs `_seedDefaultAlert()`, and `if (wasClean) _initialFingerprint = _fingerprint();` runs after; a keystroke that lands between mount and the settings future leaves `wasClean == false`, so the seeded alert stays in the current fingerprint while `_initialFingerprint` has none. Input: open the editor on a new event and start typing immediately (the title is autofocused, so this is the normal path), then clear the title back to empty and press ✕ — the discard dialog asks about a form that holds nothing the user put there. Low because the ask is the conservative direction. Fix: re-baseline for the *seed alone* — recompute `_initialFingerprint` with the seeded alert list substituted — rather than gating the whole re-baseline on `wasClean`. Fix session: B7. →
- **C55** (L, PLAUSIBLE; B4a) `lib/widgets/calendar_date_picker_sheet.dart:411` (`_onDaySelected`) and `:876` (`onPageChanged`) — the two focus assignments are the only ones in the file that skip `_clamp` (`:317`, `:341`, `:394`, `:457` all apply it), so a swipe or an outside-day tap can park the focus a month beyond `widget.lastDate` or before `firstDate`; `_selectView(year)` then derives `_focusedYear` from it (`:349-350`) and the year view's chevrons compare against `firstDate.year` / `lastDate.year`, so the user can land on a year whose back chevron is the only way out. Input: unreachable in the skipped-days picker (bounds are `CalendarBounds` 1900–2100); in the Until picker (`firstDate: startDate`) swipe back past the start month and switch to Year. Fix: `_focusedDay = _clamp(…)` on both assignments, as every other site already does. Fix session: B7. →
- **C56** (L, PLAUSIBLE; B4a) `lib/widgets/calendar_date_picker_sheet.dart:461-468` (`_applyRepeat`) with `:1158-1163` — the repeat projection is bounded above by `widget.lastDate` and not at all below by `widget.firstDate`, and it adds into `_selection` without the bounds check the day grid enforces: `DateStamp.project` only drops `next.isAfter(bound)` (`date_stamp.dart:45-49`) while `_onDaySelected:405` rejects any out-of-range day, so the two entry points into the same set disagree about what is selectable. Reachable only where `firstDate` sits above the projection's floor, which no current caller of `pickMulti` has — a latent inconsistency, not a live bug. Fix: hand `project` the `firstDate` too, or filter `preview.added` through the same check `_onDaySelected` applies. Fix session: B7. →
- **C57** (L, CONFIRMED; B4a) `test/widgets/event_editor_redesign_test.dart` with `event_editor_sheet_description_test.dart` — the copy-on-write rule §6.3 states ("Only an edit that actually diverges materializes a row") has **no** test for the un-materialised day, which is why C44 is in the tree. The suite pins the reset path (`:1508-1529`, `saved.occurrenceDescription` null) and the limit and counter paths; `event_editor_sheet_description_test.dart` holds five list/fence/caret-line cases; nothing asserts `saved.occurrenceDay == null` for a per-occurrence event whose day has no row. Fix: two cases on the existing `open` / `saveAnd` helpers, beside the Reset-day test — "a template edit on an unmaterialised day writes no row" and "a day edit on an unmaterialised day writes that day". Fix session: B7. →
- **C58** (H, CONFIRMED; B4b) `lib/services/event_alert_service.dart:259` — `replaceForCategory`'s whole-set save tombstones a `calendar_category_alerts` row the category editor never saw, so a category alert that arrived by sync while the sheet was open is soft-deleted on every device. Both halves are in the code: `category_editor_sheet.dart:142-144` seeds `_alerts` once in `initState` from `EventAlerts.categoryAlertsFor(initial.id)` and never re-reads it, and `category_alert_dao.dart:60-75` tombstones every live row whose id is not in `keep = {for (final entry in entries) entry.id.value}`. Narrower than C46 — this is the *category* table and it is gated on `_alertsTouched`, so a save that only renamed the category is safe. Input: the category editor open on Birthdays with two alerts, add a third, a pull applies a fourth for Birthdays from another device (`app_sync_apply_hooks.dart:264` → `EventAlertService.reload()`), press Save — the fourth is tombstoned and the tombstone pushes. Fix: hand `replaceForCategory` the id set the caller opened with and tombstone only ids in that set; C46 needs the same seam, so B7 fixes both with one. Fix session: B7. →
- **C59** (M, CONFIRMED; B4b) `lib/services/event_digest_service.dart:138` — an edit resurrects a digest tombstoned elsewhere, while the hub's switch for the same row correctly refuses to. `event_digest_dao.dart:57-68` writes `isDeleted: const Value(false), deletedAt: const Value(null)` with a fresh local stamp for any existing row, tombstone included; `:80-84` is the opposite and says why in its own `///` (`if (existing == null || existing.isDeleted || existing.enabled == enabled) return;`). Input: `DigestEditorSheet` open on a digest from the hub, a pull applies that digest's tombstone from another device, press Save — the digest returns with an HLC that beats the remote tombstone, so it is back permanently and re-arms; with ten live digests already stored this also puts the table at eleven and `DigestPlanner.plan`'s `enabled.take(horizon.maxDigests)` then silently drops one digest from every pass. Fix: refuse (or report) in `update` when `EventDigests.byId(digest.id) == null`, the `setEnabled` rule, rather than letting `upsertDigest` undelete. Fix session: B7. →
- **C60** (M, PLAUSIBLE; B4b) `lib/utils/quick_alarm.dart:75-81` — `quickAlarmAfter` round-trips an absolute instant through an ambiguous wall clock, so inside the repeated hour of a fall-back DST transition the "+20 min" and "+1 h" presets land about 23 h late. `at = now.add(offset)` is correct, but `_momentOf(DateTime(at.year, at.month, at.day, at.hour, at.minute))` rebuilds it as a local wall clock that resolves to the *first*, pre-transition occurrence — an instant already behind `now` — and `quickAlarmDayFor:93-103` then finds neither `onDay` nor `today` after `now` and rolls to the next day. This is the recorded `midnight.add` trap in its other direction. Input: Europe/Bucharest, 2026-10-25 03:30 local on the first pass of the repeated hour (04:00 → 03:00), tap "In 1 hour" — the saved alarm is 2026-10-26 03:30. Fix: keep the absolute instant — derive `(day, minute)` from `at` and compare instants, or have `quickAlarmDayFor` take the resolved instant instead of a `(day, minute)` pair; the probe is two cases under a fixed `TZ` (C70). Fix session: B7. →
- **C61** (M, CONFIRMED; B4b) `lib/services/event_digest_service.dart:40-60` — no in-flight guard on `getInstance()`, so a call racing a database switch publishes the closing database's digests and leaves `_instance` bound to a closed database. `reset()` (`:65-68`) clears `_instance` and the facade but there is no `_initializing` to invalidate, so an already-running `_create(oldDb)` continues past the switch, runs `_load()` against the closing database and then assigns `_instance` and `EventDigests.updateCache(...)` *after* the reset; every later `getInstance()` returns that dead service, the hub lists nothing and `update` / `setEnabled` / `delete` throw until the next switch. `EventAlertService` solves exactly this with `_initializing` + `_createOnce`, cleared in `reset()` (`event_alert_service.dart:44, 68-82, 101`). Input: `AlertScheduler`'s pass calls `EventDigestService.getInstance()`; the user switches database before `_load()` resolves. Fix: copy `EventAlertService`'s `_createOnce` / `_initializing` pair and clear it in `reset()`. `EventSkipService:64-67`, `OverviewViewService:60-62`, `CategoryService` (C73) and `EventTemplateService:32-35` share the gap — the owner may want one family fix. Fix session: B7. →
- **C62** (L, CONFIRMED; B4b) `lib/widgets/alert_editor_sheet.dart:352` — `_demoted` flips on *any* move to the Reminder tier, not only on an alarm this sheet demoted, so a round trip through Alarm on an alert that arrived and left a reminder clears the event's remove-after flag that a *different* alarm alert owns. `_setMode` is `if (mode == AlertMode.notify) _demoted = true;` with no comparison to `widget.alert.mode`, and `:415-416` reads `_mode == AlertMode.ring ? _removeAfter : _removeAfter && !_demoted`. The written contract is "`false` only when this sheet turned an alarm into a reminder" (`references/subsystems.md` § The alert sheet and the quick alarm), but `test/widgets/alert_editor_sheet_test.dart:657-673` pins the current reading ("It was an alarm here and is saved a reminder: the removal goes"), so this is a wording-versus-test call, not a plain defect. Input: a one-time event with an alarm alert and `removeAfterAlert = true` plus a second reminder alert; open the reminder, tap Alarm, tap Reminder, Done — `event_editor_sheet.dart:1449` writes `_removeAfterAlert = false` and the event no longer deletes itself after its real alarm rings. Fix: owner's call — either `_demoted = widget.alert.mode == AlertMode.ring` at the demotion (and re-pin the test), or reword the subsystems line to "this sheet showed an alarm and left a reminder"; `AlertSheetRobot.chooseTier` + `save` cover it either way. Decision 2026-10-28: the written contract stands — `_demoted` only when this sheet opened on an alarm and made it a reminder; B7 re-pins `alert_editor_sheet_test.dart:657-673` to it (the sheet's constructor says whether `widget.alert` is present for an edited alert). Fix session: B7. →
- **C63** (L, PLAUSIBLE; B4b) `lib/widgets/quick_alarm_sheet.dart:310-312` — the Tonight chip stays enabled after 21:00 until something else rebuilds the sheet, and the tap is then a silent no-op. `onTap` is decided from the `now` captured in `build` while `_applyPreset` re-reads `widget.now()`, so `_momentFor` returns null and `:140`'s `if (moment == null) return;` exits without a `setState` — no move, no message, no visual change. Input: open the quick alarm at 20:59, wait a minute without touching anything, tap Tonight — nothing happens. Fix: on a null moment, `setState(() {})` so the chip redraws disabled in place (it must still never mean tomorrow night). Fix session: B7. →
- **C64** (L, PLAUSIBLE; B4b) `lib/pages/calendar_page.dart:1357` — the quick alarm is the one path that creates an Alarm-tier alert without `AlertPermissionCheck.afterSave`, so on a phone with notifications or full-screen intents off the alarm is armed and never speaks, with no word to the user. The record names three callers (`event_sheets_flow.dart:491`, `alerts_page.dart:96,107`, `category_editor_sheet.dart:391`) and does not name this one, so it is a gap rather than a contradiction — but "the first alert on the phone may be a category's" is exactly the rule the shared check exists for. Input: revoke the notification permission, open the quick alarm from the Quick Settings tile, Save — "Alarm set for 21:00" and silence. Fix: `unawaited(AlertPermissionCheck.afterSave(context))` after the dispatch, placed after the Undo snackbar so the two do not fight for the bar; or the owner's decision that the tile path stays quiet. Decision 2026-10-28: run the check — `afterSave` posts through `CustomSnackbar.showWithAction` (`alert_permission_check.dart:47`) and follows the Undo bar rather than replacing it. Fix session: B7. →
- **C65** (L, PLAUSIBLE; B4b) `lib/services/event_alert_service.dart:329` and `:386` — neither `importCategoryAlerts` nor `importData` enforces `kMaxAlertsPerCategory` / `kMaxAlertsPerEvent`, and `CategoryAlertDao.mergeRemoteCategoryAlert:187` deliberately does not either, so D6's "effective ≤ 10 per event" is guaranteed only by the two sheets (`category_editor_sheet.dart:255`, `event_editor_sheet.dart:1397`). A restored archive or a merge can leave a category with twenty alerts; the editor then just hides Add alert and the owner cannot see where the extra fires come from. No crash — `AlertHorizon.total` bounds the plan. Input: restore a backup whose `categoryAlerts` key holds 20 rows for one category. Fix: either accept it and say so in the roadmap's §11.1, or clamp on import to the first `kMaxAlertsPerCategory` by `created_at` — a merge cannot be clamped without breaking CRDT convergence, so the honest fix is import-only. Fix session: B7. →
- **C66** (L, PLAUSIBLE; B4b) `lib/widgets/event_editor_sheet.dart:718` with `:1518` — `_inheritedAlerts` is read once in `initState` and again only on a category pick, with no listener on `EventAlerts.revision`, so a category-alert write landing while the editor is open (a pull through `app_sync_apply_hooks.dart:264`, or the category editor reached from the picker's inline create) leaves the inherited rows and the Category alerts switch showing the old set. The sibling of the digests roadmap's §11.1 residual "no revision listener on the categories page", but a different surface, so it is not that residual. Input: open the event editor on a Birthdays event with no category alerts (so no switch row), a pull adds one — the switch never appears and the inherited row is never drawn. Fix: rebuild `_inheritedAlerts` from `_categoryAlertsOf(_categoryId)` on a revision tick, the way that residual's intended fix reads the revision. Fix session: B7. →
- **C67** (L, PLAUSIBLE; B4b) `lib/widgets/alert_offset_sheet.dart:100-114` with `:209-213` — for a timed event `_everyOffset` builds **112** read-back captions (59 minutes + 23 hours + 30 days) in one `Stack` on every `setState`, each calling `widget.readBack(stored)`, which for the alert sheet is `widget.alert.copyWith(offsetMinutes: value).describe(l10n, _timedEvent)` (`alert_editor_sheet.dart:568-580`) — an `EventAlert` allocation and a localized lookup per entry, all laid out and measured. Every stepper tap pays for all 112. Input: hold the increment button on the Custom sheet with the minutes unit selected. Fix: size the slot from the few candidates whose *rendered length* can differ (the longest number per unit, e.g. `{1, unit.max}`) — six captions instead of 112. Fix session: B7. →
- **C68** (L, PLAUSIBLE; B4b) `lib/widgets/alert_sound_sheet.dart:274` — where `AlertGateway.supportsSoundPicker` is false (the Windows and macOS builds) the "Choose from phone" row is hidden outright, so an alert that *stores* a picked URI shows no checked row at all, against the class's own doc at `:51-52` ("a value that *names* a picked sound is still shown as chosen"). Input: set an alert sound on Android, sync or restore to the desktop build, open that alert's Sound row — three rows, none checked, and the stored sound is invisible. Fix: show the row disabled with its caption when `current is AlertSoundUri` even where the picker is missing, instead of omitting it. Fix session: B7. →
- **C69** (L, PLAUSIBLE; B4b) `lib/widgets/alert_editor_sheet.dart:169-176` — `AlertEditorSheet.draft`'s all-day branch seeds no `offsetMinutes` from `timedDefault`, while the timed branch at `:178-188` deliberately seeds *both* sets ("the alert survives a flip to all-day"), so an alert drafted on an all-day event and later flipped to timed arrives at "At start" rather than at the Calendar-settings timed default. Input: set a timed default of "30 min before", add an alert to an all-day event, then turn All day off in the editor — the row reads "At start". Fix: add `offsetMinutes: timedDefault?.offsetMinutes ?? kDraftAlertOffsetMinutes` to the all-day branch, mirroring the timed one. Fix session: B7. →
- **C70** (L, CONFIRMED; B4b) `test/utils/quick_alarm_test.dart:38-49` — `quickAlarmAfter` and `quickAlarmDayFor` have no DST case; every existing case sits on 2026-09-23/24, nowhere near a transition, which is why C60 is untested and why it could only be filed PLAUSIBLE. Fix: two cases under a fixed `TZ` — "+1 h inside the repeated hour stays on the same day" and "the next quarter hour inside the spring gap moves forward, not back" — on the existing plain-function API; pure-util, so no robot change. Fix session: B7. →
- **C71** (M, CONFIRMED; B4b) `lib/services/category_service.dart:396` — `deleteCategory`'s cascade rewrites `calendar_events.category` in SQL but nothing refreshes `CalendarEventService._cache` or signals the bloc, so every event of the deleted category keeps the **dead id in memory** and the next save of one writes that dead id back over the reassignment. Both halves: `calendar_event_dao.dart:248-251` is `'UPDATE calendar_events SET category = ? … WHERE category = ? AND is_deleted = 0'`; `category_service.dart:390-406` touches no event service; `calendar_categories_page.dart:193` sends only `CategoryAlertsChanged`, whose handler (`calendar_bloc.dart:1203-1210`) bumps `occurrenceRevision` alone; `CalendarPage._reloadIfStale` is gated on `isStale` = `_seenExternalRevision != CalendarEventService.externalRevision` (`calendar_bloc.dart:83-84`), which the delete never bumps; the editor seeds `_categoryId = initial?.categoryId` (`event_editor_sheet.dart:687`) and saves it verbatim (`:1713`). The method's own `///` at `:385-389` accounts for the *alert pass* reading a stale event cache and healing next pass — it does not cover the editor writing the dead id back. Input: Settings → Categories → delete a custom category that has events → back to the calendar → open one of those events → Save with nothing changed; the row's `category` goes from `other` back to the dead uuid, and until then the agenda's allowlist drops those events (`event_agenda.dart:415`) even with Other ticked. Fix: after the cascade, `await (await CalendarEventService.getInstance()).reload()` then `CalendarEventService.notifyExternalChange()` — the shape `AppSyncApplyHooks._appReloadCalendar` uses. Fix session: B7. →
- **C72** (M, CONFIRMED; B4b) `lib/services/category_service.dart:390` with `lib/database/daos/calendar_category_dao.dart:212-221` — `tombstoneCascade` reassigns events and tombstones the category's alerts but never touches `calendar_event_templates.category`, so a template keeps the dead id: the picker and the templates page draw it as "Other" (`event_template_summary.dart:20` → `CalendarCategories.fallback`) while `buildEvent` stamps the dead id onto every event it creates (`event_template.dart:81`, `calendar_page.dart:1313-1317`) with no editor pass in between — which breaks the service's own contract at `:33-34` ("no event is ever orphaned") going forward. Input: create category "Yoga" → save a template in it → delete "Yoga" → long-press a day → pick that template: the new event's `category` is the dead uuid, it is dropped by any category allowlist (`event_agenda.dart:415`) and exported as that uuid in `.ics` (`ics_serializer.dart:90`). Fix: reassign templates inside `tombstoneCascade` (one `UPDATE calendar_event_templates … WHERE category = ?` under the same stamp, rows queued) and `EventTemplateService.reload()` after the link; no new column, no migration. Fix session: B7. →
- **C73** (M, CONFIRMED; B4b) `lib/services/category_service.dart:54` — no in-flight guard on `getInstance()`: two concurrent first calls each run `_seedBuiltIns` + `_load` and each publish the facade, and a database switch landing between the start and the end of `_create` lets the late `_create` assign `_instance` (`:89`) to a service holding the **closed** database (`_db` / `_dao` captured at `:85-86`) *after* `reset()` cleared it — every later category read and write then hits a closed database, and the re-registered reset handler only fires on the *next* switch. `grep -c _initializing` is `0` in both this file and `event_template_service.dart`, against `EventAlertService`'s `_createOnce` + `_initializing` cleared in `reset()`. This is the family's **third** instance after C61. Input: a backup restore or a database switch while the calendar's first touch is still seeding the catalog. Fix: copy `_createOnce` / `_initializing` into `CategoryService` and `EventTemplateService` and clear `_initializing` in both `reset()`s — one family fix with C61. Fix session: B7. →
- **C74** (L, PLAUSIBLE; B4b) `lib/services/category_service.dart:114` — `reload()` is the one path that **writes** (`_seedBuiltIns`'s `seedMissing` batch) and republishes the facade outside `_serialize`, against scaling invariant 12. It now has a caller — `app_sync_apply_hooks.dart:255`, once per pulled page — so a reload racing a user `create` or `reorder` can issue its `getAll` first and its `updateCache` last, dropping the just-created category or the new order from `CalendarCategories` until the next mutation, while the grid memo keys on the bumped revision and repaints the stale list. Input: a sync pull applying while a category save is in flight. Fix: `Future<void> reload() => _serialize(() async { await _seedBuiltIns(); await _load(); });`, and correct the scaling roadmap's now-false "`reload()` has no caller" line (`docs/category-scaling-roadmap.md:755-757`) in the same change. Fix session: B7. →
- **C75** (L, PLAUSIBLE; B4b) `lib/widgets/category_editor_sheet.dart:372` — `updateCategory` is a deliberate silent no-op on a tombstoned row (`calendar_category_dao.dart:164-166`: `_liveById` filters `is_deleted = 0`, then `return`), but the sheet sets `_written = saved`, pops `saved` (`:375`, `:396`) and reports success, so the caller refreshes against a category that does not exist and the picker's inline-create path ticks a dead id into its selection — the edit is lost with no message. Differs from C58 on the same file: that one is the *alert set* tombstoning a row the sheet never saw, this is the *category row's own* write reporting success when the DAO wrote nothing. Input: a pull merges another device's delete of the category while its editor is open; Save. Fix: have `CategoryService.updateCategory` return the DAO's "did write" and, on false, raise `l10n.categorySaveFailed` and pop `null`. Fix session: B7. →
- **C76** (L, PLAUSIBLE; B4b) `lib/database/daos/event_template_dao.dart:72` with `lib/widgets/event_template_editor_sheet.dart:419` — the update branch writes `isDeleted: const Value(false)`, so an edit **resurrects** a template tombstoned meanwhile; because the no-change short-circuit at `:63` is gated on `!existing.isDeleted`, even a Save that changes nothing brings it back. The three siblings disagree: `CalendarCategoryDao.updateCategory:164-166` refuses this, digests and saved views deliberately upsert (`calendar_bloc.dart:1213-1215`) — so this is a decision to settle, not clearly a defect. Input: the template editor open while a pull merges another device's delete; Save. Fix: either skip the write for a tombstoned row (the category rule, and then C59's rule too) or state the upsert rule in the DAO's doc comment. Decision 2026-10-28: the upsert stands — per-row LWW (phase record §3.4 (4): an upsert newer than a local tombstone resurrects); the category DAO refuses because its events already moved to the fallback (`calendar_category_dao.dart:157-160`), a template has no dependant, and C59's digests refuse for the `maxDigests` horizon — so B7 adds the `///` at `:63` and a pinning test. Fix session: B7. →
- **C77** (L, PLAUSIBLE; B4b) `lib/models/event_template.dart:76` with `lib/widgets/event_editor_sheet.dart:1604` — a template has no `categoryAlerts` field, so "Save as template" silently drops D3's per-event opt-out and `buildEvent` leaves `CalendarEvent.categoryAlerts` at its `true` default (`calendar_event.dart:300`): every event stamped from a template inherits the category's alerts even when the event it was captured from had them off. Input: an event in a category with alerts, "Category alerts" switched off → Save as template → stamp it on a day; the new event rings. Fix: either add the flag to `EventTemplate` and the table — **a synced column, so it needs its binding and v44, the owner first** — or write "the opt-out is per-event and never captured" into the template form's doc comment and the subsystems reference. Fix session: B7. →
- **C78** (L, PLAUSIBLE; B4b) `lib/widgets/category_picker_sheet.dart:199` — `_createCategory` opens the editor without the `_blur()` every other surface does first (the trap is recorded at `category_editor_sheet.dart:216-221`), so when the editor pops, the picker's route hands focus back to its search field and the keyboard rises over the list — in the one sheet whose contract is "deliberately **no autofocus**… raising the keyboard on every open pushes the list up" (`:40-42`). Input: 13+ categories, type a no-match query, tap "Create …", Save — the keyboard is up over the rows. Fix: `FocusManager.instance.primaryFocus?.unfocus();` as the first line of `_createCategory`. Fix session: B7. →
- **C79** (L, PLAUSIBLE; B4b) `lib/widgets/category_picker_sheet.dart:231` with `lib/widgets/event_template_picker_sheet.dart:105` — both pickers read their facade in `build` with no listener on `CalendarCategories.revision` / `CalendarTemplates`, so a sync reload under an open picker leaves the rows, the captions and the search threshold stale, and in multi mode `_selected` keeps an id the pull tombstoned so Done re-asserts it into the caller's allowlist or denylist. Distinct from the digests roadmap §11.1's "no revision listener on the categories page" (that residual is the page's bell going stale after an import); this is a modal sheet's *answer* carrying a category that no longer exists. Input: `pickMulti` open while `_appReloadCalendar` applies a remote delete of a selected category; Done. Fix: filter the popped set through `CalendarCategories.byId` on Done, and rebuild both sheets off a listenable revision. Fix session: B7. →
- **C80** (L, PLAUSIBLE; B4b) `lib/services/event_template_service.dart:289` — `_toCompanion` writes `sortOrder` from the caller's captured model, so `updateTemplate` carries the form's opening `sortOrder` (`event_template_editor_sheet.dart:398`) back to the row — exactly the write scaling invariant 13 makes `updateCategory` omit. Harmless today because nothing reorders templates locally, but `sortOrder` is in the sync binding (`calendar_event_templates_binding.dart:6`), so a pulled order landing while the form is open is undone by its Save. Fix: leave `sortOrder` absent on the update path (`_toCompanion(…, {bool withOrder = false})`), as the categories' `_persistUpdate` does. Fix session: B7. →
- **C81** (L, CONFIRMED; B4b) `lib/services/event_template_service.dart:44` — `forTesting` returns an existing singleton without checking it is bound to the same `AppDatabase`, so a suite that forgets `reset()` in `tearDown` runs green against the previous test's database. `CategoryService.forTesting` carries exactly that assert after the same trap, with the reason in its own comment (`category_service.dart:67-80`: "Returning a singleton bound to some *other* database silently runs the caller against the previous test's data instead of failing"). Fix: keep the `AppDatabase` on the service and copy the `assert(identical(existing._db, db))`. Fix session: B7. →
- **C82** (L, CONFIRMED; B4b) `test/services/category_service_test.dart:403` — the group "deleteCategory cascades to its alerts (v42)" pins the cascade for events and alerts and for nothing else, which is why C71 and C72 are in the tree: no case asserts a template's category after its category is deleted, and none asserts the event cache. Fix: two cases in that group — "a template in the deleted category is reassigned to the fallback" and "the deleted category's events are gone from `CalendarEventService.events`" — plus one in `event_template_service_test.dart`'s `buildEvent` group, "a stamped event cannot carry an unresolvable category id"; service-level, so no robot change, and if the owner wants it driven through the form instead, `TemplateFormRobot` needs a reader for the Category row's value (`SemanticsIds.templateCategory`).  Fix session: B7. →
- **C83** (H, CONFIRMED; B5) `lib/services/calendar_palette_service.dart:54-79` — `reset()` does nothing to a `_create()` already in flight, so the pre-reset read can land last, publish a stale palette, and let the next colour picked overwrite the restored swatches. `_create` awaits two things (`SettingsService.getInstance()`, `_load()`) without reading `DatabaseLifecycle.generation`, and its `finally { _initializing = null; }` clears whatever future the field currently holds rather than its own — so after a reset there are two creates in flight and the loser can win. `_initializing`'s own `///` (`:29-37`) exists for exactly this payload: "this one owns a list it rewrites whole", and `_commit` (`:226-235`) rewrites the whole settings row from memory. Input: a backup restore (`backup_service.dart:503-504` resets *and immediately re-initialises* inside one database lifetime) or a database switch, with any `getInstance()` in flight — `ColorSwatchPicker.initState` (`color_swatch_picker.dart:129`), `ColorPaletteSheet.initState` (`color_palette_sheet.dart:77`), or either settings page's prewarm (`calendar_settings_page.dart:139`, `calendar_appearance_page.dart:87`); the facade then shows the pre-import swatches and the next add, remove or move persists them over the restored row. Fix: capture `DatabaseLifecycle.generation` at the top of `_create`, bail before `_instance = service` when it moved, and clear `_initializing` only when it still holds this future. C61's sibling (the same missing-guard shape in `event_digest_service.dart`) with a worse payload — a whole-row rewrite rather than a stale cache; the owner may lift it to H — lifted on 2026-10-28 (the restored palette row rewritten whole is persisted data lost, the ledger's H). Fix session: B7, first. →
- **C84** (M, CONFIRMED; B5) `lib/utils/ics_serializer.dart:406` — `_fold`'s fast path measures UTF-16 code units (`if (line.length <= 73) return line;`) while the folding loop below it and the method's own `///` ("break at 75 octets … Measured in UTF-8 bytes") measure octets, so any content line of 73 characters or fewer but more than 75 octets is emitted unfolded, against RFC 5545 §3.1. Input: export an event whose title is about 60 characters of Romanian or German with diacritics — `SUMMARY:` plus 65 `ă` is 73 characters and 138 octets and comes back unfolded (reviewer probe, the two functions copied verbatim outside the tree: `chars=73 utf8octets=138`, `folded==input: true`). A long `DESCRIPTION` is safe because it takes the loop, so the defect lands exactly on the short non-ASCII `SUMMARY`, `CATEGORIES` and `DESCRIPTION` lines, the common case in de and ro; a strict importer may reject the file or truncate the line. Fix: count octets in the guard (`line.runes.fold<int>(0, (a, r) => a + _utf8Width(r)) <= 75`). Fix session: B7. →
- **C85** (M, CONFIRMED; B5) `lib/pages/calendar_categories_page.dart:193` — the categories page's delete tells the bloc `CategoryAlertsChanged`, which re-renders and does not re-read events, so every event the cascade moved onto Other keeps the tombstoned category id in `CalendarEventService._cache` and `state.allEvents`. `_onCategoryAlertsChanged` (`calendar_bloc.dart:1203-1210`) emits one `occurrenceRevision` bump and nothing else, for the stated reason "no membership changed" — true of the editor's alert write, false of a delete that rewrote `calendar_events.category` in SQL. Input: delete a custom category that has events and return to the calendar without a restart; a grid or agenda filter on Other does not match the moved events, and saving one of them writes the dead id back over the cascade's reassignment into a synced column. Fix: call `CalendarEventService.notifyExternalChange()` on a successful delete (the bloc's own path at `calendar_bloc.dart:722` answers it with `_resolveAndReload()` plus `_invalidateDayCache()`). **This is C71's page-side twin and wants the same seam** — if B7 fixes C71 inside `deleteCategory` with that call, C85 disappears; fix the pair once, the way C46 and C58 are fixed once. Fix session: B7. →
- **C86** (M, CONFIRMED; B5) `lib/pages/calendar_categories_page.dart:101` — the categories page has no listener on `CalendarCategories.revision` (the facade's four other readers do: `calendar_overview_page.dart:628`, `calendar_page.dart:371`, `category_editor_sheet.dart:170`, `upcoming_agenda_view.dart:251`), and `_refresh` runs only from the page's own writes, so the page persists a reorder built from a stale catalogue and reports a delete it did not do. Input: leave the page open while the catalogue changes underneath it — `app_sync_apply_hooks.dart:255` reloads `CategoryService` after every pulled page, and a backup import does the same. Then (a) a drag, **Move to top** or **Sort A–Z** calls `reorder([for (final c in _categories) c.id])` with a list that omits the arrived category and still names the removed one; `CalendarCategoryDao.reorder` (`calendar_category_dao.dart:328`) numbers only the ids it is handed and leaves every other live row alone, so the arrived category keeps a now-colliding `sort_order` and its position becomes arbitrary — the dense `0..N-1` order the scaling roadmap's invariant 13 pins is broken on a synced row; and (b) Delete on a row the pull already removed no-ops in the service and returns `void`, so `_guarded` answers `true` and the page shows `categoryDeleted` for a delete that happened on another device. Fix: subscribe to the facade revision in `initState` and call `_refresh()` plus `_refreshCounts()` when it moves (the overview's `_categoryRevision` guard is the existing shape). The digests roadmap's §11.1 names only the bell half of this; (a) and (b) are new. Fix session: B7. →
- **C87** (L, CONFIRMED; B5) `lib/services/settings_service.dart:758` and `:1849` — `calendarMaxDayBars` is the one count setting clamped nowhere: `setCalendarMaxDayBars` passes the value straight to `_setInt` and `_decodeCalendarAppearance` reads it through a plain `_decodeInt`, while its sibling `calendarMaxDayRailMarks` is clamped on both sides through `SettingsKeys.min/maxCalendarMaxDayRailMarks` (`settings_keys.dart:524-525`) and `eventDescriptionLimit` likewise; there is no `min/maxCalendarMaxDayBars` at all, and `calendar_appearance_page.dart:501-503` carries `min: 1, max: 6` as bare literals. Input: a `calendar_max_day_bars` row of `0` or `20` — a restore or a sync from a build with different bounds; `SliderSettingRow` hands the value to `Slider(value:, min:, max:)` unclamped (`slider_setting_row.dart:114-118`) and `Slider` asserts `value >= min && value <= max`, so the appearance page throws in debug and profile, and in release the thumb paints off the track while `CalendarDayBars.stripHeight(0, …)` feeds `rowHeightFor` a degenerate strip. Fix: add the two `SettingsKeys` bounds, clamp in the setter and the decoder, and use them for the slider. Fix session: B7. →
- **C88** (L, CONFIRMED; B5) `lib/pages/calendar_settings_page.dart:1301` — calendar settings' *Reset to defaults* clears the whole shared fold row (`setCalendarSettingsCollapsedSections(const {})`), and `CalendarAppearancePage` stores its six `appearance_*` ids in the same row by design (`calendar_appearance_page.dart:44-48`: "They share the calendar settings page's stored set … each renders only its own"). Input: fold three sections on the Appearance page, go back, Reset to defaults on Calendar settings — the Appearance page's folds are cleared too, although that page has its own reset and that reset deliberately leaves them alone. The comment at `:1296-1301` justifies clearing *this* page's folds, not the other page's. Fix: keep the ids that are not this page's — `setCalendarSettingsCollapsedSections(_collapsedSections.where((id) => id.startsWith('appearance_')).toSet())`. Fix session: B7. →
- **C89** (L, CONFIRMED; B5) `lib/pages/calendar_settings_page.dart:508` — `CustomSnackbar.showError(context, 'Failed to switch holiday profile: $e')` is hardcoded English raised to the user when `PublicHolidayService.setProfile` throws; every other snackbar on the page goes through `l10n`. Input: a failing profile switch on a de or ro install. Fix: one new key in `app_en.arb`, `app_de.arb` and `app_ro.arb` together, then `flutter gen-l10n` with an empty `untranslated.txt`. Fix session: B7. →
- **C90** (L, CONFIRMED; B5) `lib/widgets/calendar_appearance_preview.dart:75-82` — the pinned preview contradicts the grid for two of the settings it sits under: `overflowRailMarks` is built with `missed: i == 0` and the file reads `appearance.missedDisplay` nowhere (`grep -c` returns `0`; the readers are `calendar_page.dart`, `calendar_overview_page.dart`, the three resolvers and the four panel widgets), and it reads `showWeekNumbers` nowhere either (that one is read only in `calendar_page.dart:1779`, `agenda_month_grid.dart:88`, `calendar_date_picker_sheet.dart:750`). Input: set **Missed display = Hidden** (the row two above the preview, `calendar_appearance_page.dart:521`) — the preview keeps drawing the missed rail mark while the grid drops it (`day_rail_resolver.dart:77`, `day_bars_resolver.dart:148`), so the preview shows the opposite of what the grid will do; turn **Week numbers** on and the preview does not move. Both break the preview's own written contract (`:16-18`, "the exact widgets the calendar grid uses — so every appearance option is visible"). Fix: drop the `missed` mark when `appearance.missedDisplay == CalendarMissedDisplay.hidden`, and either draw the week-number column or say in the `///` that it is not previewed. Fix session: B7. →
- **C91** (L, CONFIRMED; B5) `lib/pages/calendar_appearance_page.dart:829` — the Colors row's subtitle is `l10n.colorPaletteCount(CalendarPalette.custom.length)`, resolved once per page build, and only that row's own `onTap` rebuilds the page (`:839-842`). Input: on the appearance page add a colour with the accent row's eyedropper dot, or long-press a custom swatch and Delete; the strip repaints (it is a `ValueListenableBuilder` on `CalendarPalette.listenable`) and the count beside it keeps the old number until something else rebuilds the page. Fix: listen to `CalendarPalette.listenable` in `initState` and `setState` (removed in `dispose`) — the count must come from a page rebuild, because `SettingsEntry.description` is pre-rendered with the search highlight. Fix session: B7. →
- **C92** (L, PLAUSIBLE; B5) `lib/pages/calendar_appearance_page.dart:234, 332, 365, 412, 465, 536, 602, 692` — eight `SegmentedButton`s built inline with no fit measurement, while `945c0c3` added exactly that measurement to `settings_page.dart`'s `_choiceRow` because "a segmented button never moves a word to another segment, so a word wider than its third broke mid-word". Input: German at text scale 2.0 on 360 × 780 — the segment box is `min(maxIntrinsic, constraints.maxWidth / n)` (`segmented_button.dart:958-978`; `minWidth` is 0 here because nothing forces full width), so a segment gets about 99 dp and, after the scaled `h:8` padding, about 82 dp of text room for a 28 px font, against "Flächig", "Verlauf", "Umriss", "Gefüllt" and "Striche" (`app_de.arb:1923, 1933, 2017-2019`); the `Text` then breaks inside the word. PLAUSIBLE because it is measured from the SDK's layout code and the ARB rather than seen on a device — B8's device pass can settle it. Fix: lift `_choiceRow` and `_choiceWordsFit` out of `settings_page.dart` into a shared widget and route these eight rows through it. Fix session: B7. →
- **C93** (L, CONFIRMED; B5) `lib/pages/settings_page.dart:739-774` — `_choiceWordsFit` omits two things both of its sibling measurers apply, so the Start choices can still break mid-word: it never merges `FontWeight.bold` although `Text.build` merges it when `MediaQuery.boldTextOf(context)` is true (SDK `text.dart:722`), which makes the drawn label wider than the measured one by more than the 0.5 px slack; and it passes no `locale:` to the `TextPainter`. `_widestProfileName` (`calendar_settings_page.dart:435`) and `_YieldingTile._painter` (`:1413`) both merge the bold weight and both pass `Localizations.maybeLocaleOf(context)`. Input: Android's "Bold text" accessibility setting on, German, scale 2.0 — the row stays horizontal and a word breaks. Everything else about the measurement is right: the reviewer checked the segment box width, the `labelLarge` style, the label-only `TextButton.scaledPadding` and the re-measure on a scale or locale change against the Flutter 3.44.2 sources on this machine. Fix: merge the bold weight under `MediaQuery.boldTextOf(context)` and pass the locale. Fix session: B7. →
- **C94** (L, CONFIRMED; B5) `lib/pages/calendar_settings_page.dart:1306-1311` — *Reset to defaults* sets the holiday profile to `HolidayProfile.generic`, and `PublicHolidayService.setProfile` is "No-op when [next] equals the current profile" (`public_holiday_service.dart:101`), so only a real switch drops the previous profile's suppression rows. Input: profile already Generic, remove three holidays from the grid, Reset to defaults — the Removed holidays row still lists all three; on a non-Generic install the same reset wipes them as a side effect. The one row on the page whose state survives the reset, and inconsistently. Fix: clear this profile's suppressions explicitly in `_resetToDefaults`, or say in the dialog that removals are not part of it. Fix session: B7. →
- **C95** (L, CONFIRMED; B5) `lib/widgets/color_palette_sheet.dart:95-108` — the cap is checked **before** the picker opens, so when the palette fills from another surface while the picker is up, `add` refuses for the cap and the sheet explains it as `colorAlreadyInPalette`. `ColorSwatchPicker._addFromPicker` gets the order right: `contains` first, the remaining refusal attributed to the cap (`color_swatch_picker.dart:177-182`). Input: open Add color from the palette sheet, add the 24th colour from a picker on another surface, then pick a new colour — the wrong reason. Fix: re-check `CalendarPalette.custom.length >= SettingsKeys.maxCustomCalendarColors` after the picker returns and choose the message from that. Fix session: B7. →
- **C96** (L, CONFIRMED; B5) `lib/pages/calendar_settings_page.dart:120-140` — `_loadSettings` is nine sequential single-value awaits plus three `getInstance()`s before the page leaves its spinner, each its own round trip to the drift isolate, while `getCalendarPageSettings()` (`settings_service.dart:1916`) already returns eight of the nine in one statement (only `hapticFeedback`, `eventDescriptionLimit` and `collapsedSections` fall outside it). `references/subsystems.md:85` scopes the "one statement" rule to `CalendarPage._loadSettings`, so this is latency and drift risk rather than a §4 breach. Fix: `getCalendarPageSettings()` plus one `getValuesFor` for the three remaining keys. Fix session: B7. →
- **C97** (L, CONFIRMED; B5) `lib/services/backup_service.dart:226-274` — the settings allow-list carries `markdown_custom_colors`, `calendarCustomColors`, `colorPickerMode`, `labelStyle` and the two editor keys, and nothing calendar-shaped, so the **fasting schedule** does not survive a restore to a new install although it is authored content in the same sense as the palette: weekdays, kept months and up to `maxExceptionDates` dates the user entered by hand. The palette itself round-trips correctly (`backup_service_calendar_round_trip_test.dart` green). Pre-existing and outside B5's diff; filed because the block's question 2 asks what survives a restore, and the owner may strike it as a scope question. Fix: add `calendarFastingSchedule`, `calendarFastingTraditions`, `calendarFastingAppearance` and `calendarFastingOrthodoxGreatFasts` to `_exportSettings`' list — the import loop already writes every key it finds, so an older backup simply leaves the defaults. Decision 2026-10-28: yes on the backup content — the four keys enter the allow-list (format 7 unchanged: an additive settings map, the import writes every key it finds, `backup_service.dart:443-448`; `FastingSchedule.encode()` is a string, `settings_service.dart:1546-1550`), with a round-trip test case. Fix session: B7. →
- **C98** (L, CONFIRMED; B5) `lib/utils/ics_serializer.dart:90` — `'CATEGORIES:${_escape(event.categoryId)}'` exports the raw id, and a custom category's id is a `const Uuid().v4()` (`category_service.dart:261`); only the built-ins keep readable legacy enum names. Input: export any event in a user-created category — the receiving calendar shows `CATEGORIES:3f1a…`. Every other surface names a category through `CalendarCategories.labelOf`. Fix: emit `CalendarCategories.resolve(event.categoryId).name` (the stored name; the serializer has no `l10n`). Fix session: B7. →
- **C99** (L, CONFIRMED; B5) `lib/utils/ics_serializer.dart:88-89` — the serializer writes `event.description` directly and so drops every per-occurrence description, bypassing the one entry point for them: `OccurrenceDescriptions.descriptionFor`'s own `///` (`occurrence_descriptions.dart:93`) says it is "**the** entry point for 'what description does this event show on this day' — every surface goes through it". Input: export an event with `perOccurrenceDescriptions` and per-day text but no base description — no `DESCRIPTION` line at all, and the class `///` documents the skip, retroactive and alarm decisions but not this one. Fix: either export `descriptionFor(event, first)` for the anchor at minimum, or document the omission in the class `///` (RFC 5545 would want one `RECURRENCE-ID` VEVENT per override). Fix session: B7. →
- **C100** (L, PLAUSIBLE; B5) `lib/utils/ics_serializer.dart:284` — the `EXDATE` scan is bounded at `expansionHorizonDays` (730) by `_expansionEnd`, while `_ruleToRrule` emits an unbounded `RRULE` when `endDate == null`, so a cancelled occurrence past the horizon is not excluded from an endless rule. Input: a daily event with no end date and a skipped day three years out; the importing calendar fires on a day the user cancelled. The class `///` documents that *expansions* are bounded, not that exclusions against an infinite rule are. Fix: when `endDate == null` and skips exist, scan the skip set itself (`EventSkips` keys for the event) rather than walking the horizon. Fix session: B7. →
- **C101** (L, CONFIRMED; B5) `lib/pages/calendar_categories_page.dart:222` and `:285` — the page persists a reorder while telling the user reorder is locked: with a query live it renders `ReorderLockedHint` (`clearSearchToReorder`, `settings_reorder.dart:66`) and passes `dragIndex: null` so the handles go dead, but the row's ⋮ **Move to top** and the app bar's **Sort A–Z** stay enabled and both call `_persistOrder`, which rewrites the whole `0..N-1` order. Input: type a query, open a row's ⋮, tap Move to top — the order is persisted invisibly, because the filtered list is rendered by `rankCategories` and nothing moves on screen. The scaling roadmap's invariant 5 reads "Reorder and filtering are mutually exclusive in the UI, always". Fix: drop Move to top from the row menu and disable Sort A–Z while `_isFiltering`. Fix session: B7. →
- **C102** (L, CONFIRMED; B5) `lib/pages/calendar_categories_page.dart:136-146` — a failed hide or delete on the categories page is completely silent. `_guarded`'s `///` says "Reconciling on failure is the feedback: an optimistic order or a flipped visibility icon visibly springs back" — but the eye icon is **not** optimistic (`_CategoryRow` renders `category.isHidden` straight off the service's list, `:531`), so a failed `setHidden` springs back to nothing; and `_delete` returns on `!deleted` (`:189`) with no message. Input: make the write throw (a closed database after a multi-database switch) and tap Hide, or confirm Delete — the page is indistinguishable from a no-op and only `debugPrint` records it. Fix: an error snackbar in `_guarded`'s failure branch. Fix session: B7. →
- **C103** (L, CONFIRMED; B5) `lib/pages/calendar_categories_page.dart:148-158` — `_create` and `_edit` skip the refresh when the sheet returns `null` (`if (created == null || !mounted) return;`), and the digests roadmap's §11.1 records that "the category editor's drag-close returns `null` after a failed alert write (the bottom sheet's own drag pops past the `PopScope`)". Input: create a category whose alert write then fails and dismiss the sheet by dragging it down — the written row is listed only after the page is reopened. Fix on the page's side: call `_refresh()` unconditionally after `CategoryEditorSheet.show` returns; it costs one `setState` and is immune to whatever the sheet answers (the sheet-side fix §11.1 names is in `category_editor_sheet.dart`, which B4b owns). Fix session: B7. →
- **C104** (L, PLAUSIBLE; B5) `lib/pages/calendar_categories_page.dart:82-99` — `_load()` has no `try`/`catch` and `_isLoading` is cleared only on the success path, so a throwing `getInstance()` leaves the page on a `CircularProgressIndicator` for good and the error escapes as an unhandled async error (`countByCategory()` swallows internally, `calendar_event_service.dart:106-111`, so the two `getInstance()`s are the throwing calls). The hub by contrast routes each of its four reads through an `…OrEmpty` or a `catch` (`alerts_page.dart:181-224`). Fix: wrap `_load`'s body in a `try`/`catch` that clears `_isLoading` and shows the empty state. Fix session: B7. →
- **C105** (L, CONFIRMED; B5) `lib/pages/alerts_page.dart:309` — a failed `ToggleEventDigest` leaves the hub's switch at the user's value for good, so the hub asserts an armed digest that nothing wrote. `_pendingDigestEnabled` is cleared only by `_load()` (`:197-198`), which runs on a bloc emit or an `AlertScheduler.registryRevision` bump, and `_writeDigest` emits nothing on the failure path (`calendar_bloc.dart:1268-1273`: `catch (e) { debugPrint(…); return; }`), so there is no emit, no reconcile and no revision bump. Input: flip a digest's switch while the write fails — a closed database after a switch, a tombstoned row — and nothing on the page ever corrects the row. §11.1 of the digests roadmap keeps exactly this for the *alert* rows ("a failed write leaves a switch at the user's value, the alert rows' precedent, kept"); the **digest** twin is new, and readiness D11's honesty clause is a reason to re-decide both. Fix: bump `occurrenceRevision` on `_writeDigest`'s and `_onToggleEventAlert`'s failure paths so the next `_load()` drops the pending value. Fix session: B7. →
- **C106** (L, PLAUSIBLE; B5) `lib/pages/alerts_page.dart:246-250` — the hub's inherited-row switch dies silently when the event is not in `state.allEvents`: the read-at-press-time guard is correct, and is the right answer to the stale-overwrite risk, but it has no else-branch, so `if (current == null) return;` snaps the switch back with no message. Input: a `pending` registration whose event was deleted on another device and pulled, before the next reconcile drops the registration — the row still renders from `hubEntries()`. Fix: on `current == null`, `_reload()` and raise an error snackbar. Fix session: B7. →
- **C107** (L, PLAUSIBLE; B5) `lib/pages/alerts_page.dart:296` — the hub's Undo after "cancel alarm" dispatches `CreateCalendarEvent(event: entry.event, …)` with the last load's copy, eight lines below a `_toggle` that deliberately re-reads the event from the bloc at press time for exactly this reason. Input: long-press a remove-after alarm row, confirm, and have the event edited elsewhere (a sync pull) between the hub's last load and the Undo tap — Undo resurrects the pre-edit event and overwrites the newer version with a fresh CRDT stamp. Fix: read the event from `bloc.state.allEvents` at the confirm and fall back to `entry.event` only when it is absent. Fix session: B7. →
- **C108** (L, CONFIRMED; B5) `lib/pages/alerts_page.dart:394-395` — the hub's `BlocConsumer` has no `listenWhen`, so every bloc emit (the panel's occurrence-description ticks included) re-runs `Future.wait` over `hubEntries()` (a `pending()` DAO read plus four `getInstance()`s), `recentEntries`, `digestEntries` and a settings read. Generation-guarded, so correct — just wasteful for as long as the hub is on screen. Fix: a `listenWhen` on `occurrenceRevision` and `membershipRevision` plus the loaded-state transition. Fix session: B7. →
- **C109** (L, CONFIRMED; B5) `test/utils/` — nothing pins the serializer's core output. `grep -rn "IcsSerializer" test/` returns exactly two files, `ics_serializer_alarm_test.dart` (VALARM, triggers, category alerts) and `ics_serializer_skip_test.dart` (EXDATE and RDATE against skips); no case covers `RRULE` per frequency, interval, BYDAY or UNTIL, the all-day `DTSTART;VALUE=DATE` with `DTEND` one day after, `_escape`, `_fold`, `CATEGORIES` or `PRIORITY` — which is how C84 survived. Fix: a `test/utils/ics_serializer_test.dart` with one expectation per `RecurrenceRule` subtype plus an assertion that every physical line of a de or ro fixture is 75 UTF-8 octets or fewer (it fails today — that is C84's named failing test). Fix session: B7. →
- **C110** (L, CONFIRMED; B5) three paths in B5's first half have no suite: (a) `test/widgets/calendar_appearance_page_test.dart` has no large-text case at all (its groups are the pinned preview, reset, and the page it left behind) while `calendar_settings_large_text_test.dart` pins the settings page at 2.0 and German — the gap that let C92 through; (b) `test/services/calendar_palette_service_test.dart:277` covers "two racing first callers share one service" and nothing for a `reset()` landing **inside** an in-flight `getInstance()`, which is C83's path; (c) nothing pins the preview against the grid for `missedDisplay` (C90) or the Colors row's count against a palette change made elsewhere on the same page (C91). Fix: one case each, named in C83's, C90's, C91's and C92's fixes. Fix session: B7. →
- **C111** (—, CONFIRMED; B5) `lib/controllers/calendar_export_controller.dart:24` — `isPending` has no reader in `lib/`: `grep -rn "isPending" lib/` returns only the declaration, and the only readers are `test/controllers/calendar_export_controller_test.dart:110-170`, so a public getter is kept alive by its own test. Fix: drop the getter and assert on the snackbars instead, or keep it deliberately with a `///` saying it is a test seam — the owner's call. Struck 2026-10-28: a test seam is not a defect; one `///` when the file is next opened. Fix session: none. →

---

## 4. Must not change

- The `calendar-events` skill's "Hardest constraints" section, as
  written there.
- Persisted semantics: soft deletes, the CRDT fields, the composite day
  keys (`eventId|dayEpochMs`), the assume-absent presence default (v37),
  built-ins hidden never deleted, backup compatibility; the sync
  bindings' column sets — a column added to a synced table needs its
  binding and a migration (v44, the owner first).
- Settings through `SettingsService` + `SettingsKeys`; every string in
  three ARBs; the UI language (a correctness review restyles nothing; a
  fix inside a sheet keeps its anatomy and metrics).
- `packages/alarm/` untouched; the alert surfaces out of scope (D1 A).
- The three saved suites and the goldens unchanged unless an id says a
  screen changes.

---

## 5. Decisions (D1–D5; the default is marked)

**Taken as the default on 2026-10-28 by B1 and kept by B2, B3a, B3b, B4a, B4b and
B5 — every review session of night 3 — the owner asleep: D1 A and D2 A.** The alert surfaces stayed out, which is what left
B1's question 7 half open (§3.1) — `DigestPlanner`'s planned and delivered
states live in `alert_scheduler.dart` — and what left B2's one alert
question unasked (the Skip notice's `ToggleEventAlert` on an inherited
alert, `alert_skip_action.dart:50`). **B4b hit the same wall from the other
side** and named it third: what a sync reload does to digest entries already
armed is `digestEntries` / `_assignOsIds` / `digestArmSignature` in that same
file, as is what `reconcileAllQuietly` plans for an event freshly stamped from
a template. Three sessions now point at `alert_scheduler.dart`, so **flipping
D1 to C** (a B5b session on the alert surfaces) looks cheaper than routing four
loose questions into B5 — the owner's call before night 4. **B5 then hit it from
both sides and made the count six** (half 1: the four `reconcileAllQuietly` calls
on the settings page and what the reset's alert defaults do to standing digests;
half 2: `hubEntries()` being registry-truth while `digestEntries()` is planned
fresh, which is the one place the hub answers readiness D11's honesty question
two ways), so B5 routed nothing into itself and the D1 → C argument is now the
record's, not one session's. Under D2 A, B2
reported no visual finding: its question 6 on the cell styles and the edge
stripe was read for correctness only, and B3a's question 3 (the presence
button and the hidden missed display in every state) was read the same
way. B3b read the two sheets in its list for behaviour only on the same
letter, and filed C39's 6 dp block as the functional half of a geometry
defect rather than as a conformity finding. B4a read questions 3 and 4 for
behaviour only on the same letter and filed one finding at D2 A's boundary —
C52, a stale header hairline, kept because what it diverges from is
`FormHeaderHairline`'s own written contract rather than the UI language; the
owner may strike it. B4a also left the editor's **alert rows** to B4b under
D1 A, which is where C46 (an alert row the user never saw, tombstoned by the
editor's whole-set save) may be merged — it is filed under B4a because it is
the save path, and B7 fixes it either way. **B4b read them and found C46's
category twin, C58** (`replaceForCategory` tombstoning a category-alert row the
editor never saw): the two want **one** seam in B7, not two patches. B4b filed
no conformity finding at all, and marks three of its ids as decisions rather
than defects — C62 (the subsystems wording versus the test pinning `_demoted`),
C64 (whether the Quick Settings path runs the permission check), C76 (whether an
edit may resurrect a tombstone, where the category DAO refuses and digests and
saved views upsert) — any of which the owner may strike. It also ran as **two**
reviewers over disjoint halves rather than the one the block names, on B4a's
closing advice; §3.1 carries the cost and says B5 should do the same.

**2026-10-28, before night 4 — the owner's letters** (the `fable-max`
decision sheet; the owner flips any of them before launching): **D1 → C**,
B5b runs first on night 4 as two reviewer halves (≈ 2.8 units) and its ids
go to B7; D2 stays A; **C83 lifted to H** (the restored palette row
rewritten whole is persisted data lost); **C111 struck** (a test seam, not
a defect; one `///` when the file is next opened); **C76 settled** — the
upsert stands under per-row LWW (phase record §3.4 (4)), B7 adds the
`///` and a pinning test; **C97 yes** on the backup content — the four
fasting keys enter `_exportSettings`' allow-list, format 7 unchanged; C52,
C62 and C64 kept for B7 (C62: `_demoted` only when the sheet opened on an
alarm, the test re-pinned to the written contract). The B3b corners: the
detail sheet's alert and presence rows go to B5b half 2;
`MonthYearPickerSheet` to a later review.

- **D1 — Scope.** A (the default night 3 ran on): §1's correctness and
  regression scope. B: the owner's own list (written here before night 3;
  the sessions read it first). **C (taken 2026-10-28 for night 4):** A plus
  the alert surfaces (one more reviewer session, B5b: `alarm_page.dart`, `android_alert_gateway.dart`,
  `alert_scheduler.dart`, `alert_gateway.dart`, `lib/controllers/alert_ring_controller.dart`
  against `docs/alert-surfaces-redesign-roadmap.md`).
- **D2 — The look.** **A (default):** none. B: one `design-reviewer` per
  surface group after B2, B3a, B4a and B5 (four sessions, about +3 units),
  findings as ids for B6/B7 when they are defects, else deferred to the
  UI-language roadmap.
- **D3 — Nights.** **A (default):** night 3 the reviews, the owner reads
  §3, night 4 the fixes. B: one chain.
- **D4 — What the fix sessions build.** As the sync review's D4 (A: H, M
  and co-located L).
- **D5 — Commits.** As the sync review's D2 (A: `-Commit` on the fix
  night).

---

## 6. Budget

Units as the sync review's §5.

| Session | Lead | Agents | Units |
| --- | --- | --- | --- |
| B1, B2, B3a, B3b, B4a | Opus | one reviewer each | 5 × 1.4 = 7 |
| B4b, B5 | Opus | **two** reviewers each, split halves (§3.1) | 2 × 2.8 = 5.6 |
| **Night 3** | | | **≈ 12.8** as run (D2 B: ≈ 15.8) |
| B6, B7 | Opus | implementer + medium reviewer each | 2 × 2.5 = 5 (B6 with two implementers: 6.5) |
| B8 | Sonnet | qa-runner, docs-writer | 0.5 |
| **Night 4** | | | **≈ 5.5–7** |
| **Block B** | | | **≈ 17.5** |

**The minimum calendar path** (moot now that night 3 ran whole): B1, B2, B3a
and one fix session (≈ 7 units); B3b, B4a, B4b and B5 would have waited for
the next week.
