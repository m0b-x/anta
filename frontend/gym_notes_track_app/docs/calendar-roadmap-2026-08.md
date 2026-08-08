# Calendar Roadmap — August 2026

**Status: shipped 2026-08-06 (schema v19).** All four batches landed in one
pass. This document is kept as the decision record — the *authoritative*
description of the shipped behaviour lives in
[calendar-events-feature.md](calendar-events-feature.md) §3.3, §6.2, §6.5, §6.6
and in the `calendar-events` skill. Read those first; read this for the
reasoning behind the choices.

One decision reversed during implementation: the plan proposed implementing
retroactive recurrence by back-projecting the anchor date. That is unsafe —
rebuilding a day-31 or Feb-29 anchor in a shorter month rolls the `DateTime`
over and corrupts the phase. Shipped instead as a `retroactive` parameter on
`occursOn` with the pre-start guard lifted, which is exact for every rule.

Forward plan for four calendar changes agreed on 2026-08-06. Read alongside
[calendar-events-feature.md](calendar-events-feature.md) (the
implementation-aware reference) and the `calendar-events` skill, which owns the
hard rules this plan must not break.

Scope, in the user's words:

1. A calendar surface for picking dates, instead of the Material date dialog.
2. A recurring event field for "every year" vs "from now on".
3. The event description, truncated, in the bottom day panel.
4. Descriptions rendered through the app's markdown engine, stored raw.

Plus one addition accepted during planning: a read-only event detail sheet.

## Decisions locked during planning

| Question | Decision |
| --- | --- |
| What "every year vs from now on" means | **Retroactive vs forward-only.** "Every year" makes the rule also fire *before* the anchor date; "from now on" is today's behaviour. |
| Which "lower bar" | **`DaySummaryPanel` rows** under the grid (the agenda inherits it through the shared provider). Labelled day-cell markers in the grid are explicitly out of scope. |
| How much markdown in descriptions | **Inline-fidelity in rows, full in the editor/detail sheet.** Money ledger stays **disabled** in descriptions. |
| Date-picker scope | All four picker call sites; existing events shown as markers while picking; API shaped so it can later serve skip-dates; read-only detail sheet added. |

---

## Batch A — recurrence scope (`retroactive`)

### A.1 Semantics

Today every rule opens with `if (day.isBefore(start)) return false;`, so a
recurring event is structurally forward-only. The new per-event flag relaxes
that guard.

**Implementation: relax the guard, do not back-project the anchor.** The
obvious alternative — hand the rule a start date shifted backwards by whole
periods — is a trap: `MonthlyRecurrence` compares `day.day != start.day`, so a
day-31 anchor projected into a 30-day month rolls over and silently corrupts
the phase, and a Feb-29 anchor rolls into Mar 1 in non-leap years. Relaxing the
guard has no such failure mode, because every rule's phase test is already
correct for negative differences:

| Rule | Phase test with `day < start` | Why it holds |
| --- | --- | --- |
| `DailyRecurrence` | `day.difference(start).inDays % interval` | Dart `%` is Euclidean — a negative dividend still yields the correct non-negative residue. |
| `WeeklyRecurrence` | `(_weekIndex(day) - _weekIndex(start)) % interval` | `_weekIndex` already floors toward −∞ *by design* for pre-epoch dates. |
| `MonthlyRecurrence` | `day.day == start.day` + `months % interval` | Month delta is signed; Euclidean `%` again. Short months stay skipped. |
| `YearlyRecurrence` | `month`/`day` equality + `(day.year - start.year) % interval` | No `DateTime` is constructed, so Feb 29 keeps matching only real leap days. |
| workdays / weekends / holidays-only | guard only | Holidays before the anchor resolve through the existing seed window. |

Signature change on the sealed hierarchy:

```dart
bool occursOn(DateTime day, DateTime start, {bool retroactive = false});
```

Each subclass replaces its guard with `if (!retroactive && day.isBefore(start))`.
`OneTimeRecurrence` and `SpecificDatesRecurrence` ignore the parameter (their
membership is exact), and the editor hides the field for them.

`CalendarEvent.occursOn` stays the single wrapper that also enforces `endDate` —
`endDate` semantics are unchanged and still clamp the forward side.

### A.2 Persistence — schema v19

Recipe from the `calendar-events` skill, in order:

1. `calendar_events` gains `retroactive INTEGER NOT NULL DEFAULT 0`; migration
   is idempotent behind a `PRAGMA table_info` guard, inside the upgrade
   transaction.
2. `DatabaseSchema.currentVersion` 18 → 19.
3. `CalendarEventDao` column + `CalendarEventService` row↔model mapping
   ([calendar_event_service.dart](../lib/services/calendar_event_service.dart), both
   directions).
4. `CalendarEvent` field + `copyWith` (non-nullable bool, so no `clearX` flag).
5. `BackupService` export/import. **No backup version bump** — the field is
   additive and old backups import as `false`, which is exactly today's
   behaviour.
6. `dart run build_runner build --delete-conflicting-outputs`.

### A.3 UI

In [event_editor_sheet.dart](../lib/widgets/event_editor_sheet.dart), inside the
recurring section only (next to the interval stepper and "Ends on" tile): a
`ChoiceChip` pair, matching how recurrence frequency is already picked.

Labels are resolved by a sealed `switch` on `_RecurrenceKind` — no generic
key lookup (hard rule):

- yearly → "Every year" / "From this date on"
- everything else → "Always" / "From this date on"

A subtitle explains the consequence ("also shows on days before the start
date"). `RecurrenceFormatter` gains the same distinction so day-panel and
agenda subtitles read correctly.

### A.4 Ripples

- **`.ics` export** ([ics_serializer.dart](../lib/utils/ics_serializer.dart)):
  RFC 5545 has no concept of occurrences before `DTSTART`. Export keeps
  clamping at the event's start date; record it in the known-limitations table.
- **Agenda** (`EventAgenda`): scans forward from today, clamped to 366 days —
  unaffected.
- **`eventLoader` / day cache**: unaffected. `occursOn` is already called
  per-day through the memoized cache; no new invalidation sites.
- **`MoneyDaySummaryProvider`**: attributes on `startDate` only — unaffected.

---

## Batch B — `CalendarDatePickerSheet`

New `lib/widgets/calendar_date_picker_sheet.dart`. A `TableCalendar` in a modal
sheet, two modes:

- `single` → `Future<DateTime?>`
- `multi` → `Future<Set<DateTime>?>`; tapping a day toggles it, selected days
  render filled, header shows the count with a clear action

Replaces all four `showDatePicker` call sites: `_pickDate`, `_pickEndDate`,
`_pickAdditionalDate`, `_editOneTimeDate`. The multi mode collapses "build a
6-date availability" from six dialog round-trips into one pass.

Rules to honour:

- Appearance comes from `SettingsService.getCalendarAppearance()` and renders
  through `CalendarDayCell` / `CalendarDayBars`, so week start, accent and
  today-style match the real calendar. Never re-implement cell decoration.
- Existing events show as markers while picking, sourced from
  `CalendarBloc.eventsForDay` — the memoized O(1) lookup. **No service calls,
  no recurrence expansion inside the builder** (hard rule).
- Sheet conventions: `useSafeArea: true`, bottom clearance = `max(viewInsets,
  viewPadding)`, `!mounted` early-returns after every await.
- Date normalization is `DateTime.utc(y, m, d)` everywhere.
- `firstDate`/`lastDate` clamping preserved per call site (the end-date picker
  still floors at the start date).
- `_setOneTimeDates` remains the single funnel that re-derives the anchor
  (earliest date) and the extras list; the sheet returns a set and hands it
  over untouched.
- `_pickDate`'s two existing rules survive: weekday re-anchoring only when the
  previous selection was the implicit default, and dropping an end date that
  now precedes the start.

**Forward-compat for skip-dates.** The multi mode takes a `selection`
`Set<DateTime>` plus a semantic label and returns the edited set — it knows
nothing about *why* the dates matter. That is what lets the same sheet later
drive "skip this occurrence" (the top entry in the docs' known-limitations
table) against an `event_exceptions` table, with no UI rewrite.

---

## Batch C — description in the day panel

### C.1 Plumbing

- `DaySummaryEntry` gains `String? description` (add to `props`).
- `EventSummaryProvider` fills it from `event.description`; the existing
  subtitle (`recurrence · time`) is untouched and stays line one.
- `DaySummaryPanel`'s `ListTile` subtitle becomes a two-line column: the
  existing subtitle, then the description at `maxLines: 2,
  overflow: TextOverflow.ellipsis`.
- `AgendaListView` renders through the same provider and inherits this by
  construction — that shared-provider property is deliberate and must not be
  broken to give the two surfaces different text.
- Rows that carry a description get a small indicator icon, so a clipped line
  is not the only signal there is more to read.

### C.2 Markdown rendering in rows

Descriptions are already stored raw and stay that way — nothing rendered is
persisted, no derived column, no cached spans in the database.

Rows render **inline fidelity**: bold, italic, inline code, colours
(`{name:text}`), highlights (`==text==`), tags, links-as-text. Block chrome is
flattened rather than stripped by a second parser — **never fork a grammar**:

- `LineMarkdownStyle` gains `bool flattenHeadings` (default `false`);
  `_buildHeading` picks `1.0` instead of the `MarkdownConstants.h*Scale` when
  set. One field, one line, zero grammar involvement — a `# Leg day` row stays
  bold at body size instead of blowing the card open.
- Rendering goes through the builder's existing public `buildLine`, on a
  builder prepared with the description text. Descriptions are ≤ a few hundred
  characters, so `prepare` is trivial.
- **All tap callbacks are null in row context** (`onLinkTap`, `onTagTap`,
  `onMoneyTap`, `onCheckboxTap`). Verify during implementation that this means
  no `TapGestureRecognizer` is allocated — that is what makes the resulting
  spans inert and safe to cache and drop without a `dispose` dance.
- Memoize with a small LRU keyed by `(text, fontSize, brightness,
  palette.source)`. `MarkdownColorPalette` is value-equal on its persisted
  `source`, which is what makes it a legal cache key.
- `moneyConfig: MoneyDisplayConfig.disabled`. The ledger is per **note** — a
  `$+ 50` line in an event description would render a balance derived from
  nothing. `$` lines stay literal text in descriptions.

### C.3 Editor sheet

The description `TextField` gets an edit/preview toggle (icon in the field's
label row). Preview renders through `SimpleMarkdownPreview` with the user's
`MarkdownColorPalette` and `MoneyDisplayConfig.disabled`.

`maxLength` rises from 500 to 2000 — 500 is cramped once the field is a real
markdown surface. The counter stays (it is the only signal of the cap).

Explicitly **not** doing: a live Obsidian-style `re_editor` instance inside the
sheet. A second editor with its own span-builder wiring, focus handling and
keyboard interplay is disproportionate for a description field.

---

## Batch D — read-only event detail sheet

New `lib/widgets/event_detail_sheet.dart`. Tapping a day-panel row currently
drops straight into the edit form; with descriptions becoming real content, the
tap should first *show* the event.

Contents: title, category chip, icon, priority, recurrence + time in full
prose, **fully rendered description** (`SimpleMarkdownPreview`, money disabled,
scheme-validated link taps as in the preview pipeline), linked note tile
(resolved via `NoteRepository.getNotesByIds([id])`, never `getNoteById`, so a
soft-deleted note shows `eventLinkedNoteMissing`), and the next N occurrences.
Edit and Delete live behind buttons.

`DaySummaryPanel.onEventTap` routes here; the agenda keeps its current
edit-on-tap behaviour unless it reads better to unify (decide when the sheet
exists).

---

## Localization

New ARB keys, added to `app_en.arb` / `app_de.arb` / `app_ro.arb` **together**,
then `flutter gen-l10n` and a check of `untranslated.txt`:

- recurrence scope: label, `everyYear`, `always`, `fromThisDateOn`, hint
- date picker: title (single), title (multi), selected-count (ICU plural),
  clear, done
- description: preview/edit toggle tooltips, has-description semantic label
- detail sheet: title, next-occurrences header, empty-description text, edit,
  delete

---

## Suggested order

A → C → B → D. Batch A is the only one with a migration, so it should land and
settle first; C is self-contained and immediately visible; B is the largest new
widget; D depends on C's rendering path.

## Validation

- `dart run build_runner build --delete-conflicting-outputs` after A.1–A.2
- `flutter gen-l10n` after every ARB touch
- `dart analyze lib` on every batch
- `flutter test test/utils/markdown_money_syntax_test.dart` after C (the
  flattened-heading knob touches `LineMarkdownStyle`, which the money renderer
  reads)
- Manual: `.\install_to_device.bat arm64`

**Recommended but not scheduled:** the recurrence engine still has no automated
coverage (already flagged in the feature doc's known-limitations table), and
Batch A changes its central guard. Interval phase across the anchor, Feb-29
anchors, and day-31 months are the high-value cases.

## Docs to update when this lands

- [calendar-events-feature.md](calendar-events-feature.md): §3 recurrence
  semantics, §3.2 (the `endDate` argument now has a sibling), §5.1 schema,
  §6.3 editor, §11 known limitations (`.ics` clamp; skip-dates now cheaper)
- `COPILOT_CONTEXT.md` calendar section
- `.claude/skills/calendar-events/SKILL.md` hard rules — the
  "every rule guards `day.isBefore(start)` first" line becomes conditional
