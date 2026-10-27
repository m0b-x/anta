# Calendar — the review (2026-10-26)

**Status: PLANNED 2026-10-26 (Fable 5.1), as the owner's "resources for a
calendar review": ten sessions B1–B8 on the same runner as the sync
review, run after it (sync review D6 A). The scope is §1's default until
the owner states one (§5 D1); nothing has run yet.** The calendar is
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
tool\review\overnight.ps1 -Sessions B6,B7,B8 -Commit             # night 4: the fixes, the gate
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

**Inputs.** The B7 ids (B4a, B4b, B5). **Brief** as B6, with `calendar-ui`
and `ui-language` beside `calendar-events` (a sheet fix keeps the sheet's
anatomy: the row primitives, the metrics, the semantics ids); `l10n` for
any string, three ARBs together. **Then** the reviewer, the unit gate,
the commit. **Writes.** As B6.

### B8 — The gate, the device pass, the docs (Sonnet lead; `qa-runner`, `docs-writer`)

**Steps.** (1) `dart analyze lib test test_driver`; `flutter test` whole;
`flutter gen-l10n` + `untranslated.txt` empty if an ARB changed; the
goldens: byte-equal except the ones a ledger id re-rendered on purpose
(named in the session log). (2) One `qa-runner`: `qa fleet install
--build`, `qa pass calendar -d emulator-5556` and `qa pass alerts -d
emulator-5556`, each a foreground call with a ten-minute tool timeout —
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

- (nothing has run)

### 3.2 Findings

Shape as the sync review's §0.6, ids `C1`, `C2`, …; fix session B6 or B7
by file.

- (none yet)

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

- **D1 — Scope.** **A (default):** §1's correctness and regression scope.
  B: the owner's own list (written here before night 3; the sessions
  read it first). C: A plus the alert surfaces (one more reviewer
  session, B5b: `alarm_page.dart`, `android_alert_gateway.dart`,
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
| B1, B2, B3a, B3b, B4a, B4b, B5 | Opus | one reviewer each | 7 × 1.4 = 9.8 |
| **Night 3** | | | **≈ 10** (D2 B: ≈ 13) |
| B6, B7 | Opus | implementer + medium reviewer each | 2 × 2.5 = 5 (B6 with two implementers: 6.5) |
| B8 | Sonnet | qa-runner, docs-writer | 0.5 |
| **Night 4** | | | **≈ 5.5–7** |
| **Block B** | | | **≈ 16** |

**The minimum calendar path:** B1, B2, B3a and one fix session (≈ 7
units); B3b, B4a, B4b and B5 wait for the next week.
