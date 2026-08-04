---
name: calendar-events
description: Rules and file map for the calendar/events subsystem in Gym Notes - custom events, data-driven categories, recurrence rules, public holidays, event editor sheet, day bars/summary, event-note links. USE FOR - any change touching lib/pages/calendar_page.dart, calendar_settings_page.dart, calendar_categories_page.dart, lib/bloc/calendar/, CalendarEventService, CategoryService, PublicHolidayService, RecurrenceRule, event_editor_sheet.dart, or the calendar_events / calendar_categories / public_holidays tables. Load together with gym-notes-context.
---

# Calendar & Events

Read [docs/calendar-events-feature.md](../../../docs/calendar-events-feature.md) — the deep, implementation-aware reference for this subsystem (domain model, recurrence semantics, persistence, editor layout). This skill lists the hard rules and the change-set recipes; the doc has the details.

Schema lineage: v10 calendar tables → v11 `end_date` + time-of-day → v12 `description` → v13 holiday profiles → v14 `note_id` event↔note link → v15 data-driven `calendar_categories` → v16 `color_value`/`tint_icon`/`priority` → v17 `suppressed` holidays → v18 **priority scale inverted** (data-only `p -> 6 - p`; backup version bumped to 7, older backups flip priorities on import). The recurrence **interval** rides inside `rule_payload` JSON with no migration — keep it that way (write only when `> 1`, decode with clamped fallback to `1`; never add an `interval` column).

## Hard rules

- `TableCalendar.eventLoader` stays a pure O(1) lookup through `CalendarBloc.eventsForDay` (memoized per-day cache, cap 512). Never dispatch events, call services, or expand recurrences inside the loader. If you add a bloc handler that mutates events or the category filter, call `_invalidateDayCache()`; never invalidate from day/focus/format handlers.
- The `CalendarRecurrence` enum and `event.recurrence` field are gone — always use `event.rule` (sealed `RecurrenceRule`).
- `event.allDay` is derived (`time == null`); check `event.time != null` to render time rows — the persisted `all_day` column is a write-only mirror.
- Categories are **data-driven (v15), not an enum**: `CalendarEvent.categoryId` is a `String`. Resolve icon via `CalendarCategories.iconFor(event)` (per-event override wins, else category icon) and tint via `CalendarCategories.resolve(event.categoryId).color`. Unknown ids fall back to `other` — never throw. Built-ins keep stable ids equal to the old enum names (`'gym'`, …) and cannot be deleted; `CategoryService.deleteCategory` reassigns events to `other` in a transaction.
- The calendar filter is a hidden-id set (`CalendarPageLoaded.hiddenCategoryIds`, empty = show all) via `ChangeHiddenCategories` — new categories are visible by default.
- Never mutate `public_holidays` outside `PublicHolidayService` — the static `PublicHolidays._cache` is only rebuilt by `_load()`; direct DAO writes desync the sync facade.
- Date normalization anywhere in calendar code: `DateTime.utc(y, m, d)` to match `CalendarEvent.occursOn`. All occurrence math is O(1) modular arithmetic on date-only UTC — no per-day allocation, no DST-sensitive math.
- Resolve a linked note (`event.noteId`) via `NoteRepository.getNotesByIds([id])`, **not** `getNoteById` — the former filters soft deletes so you show `eventLinkedNoteMissing` instead of a ghost note.
- Navigation: `AppNavigator.toCalendar` stays a normal `push` (previous page remains on the stack). Calendar options live on `CalendarSettingsPage` (gear in the calendar app bar), never on `ControlsSettingsPage`.
- No generic `AppLocalizations.byKey` — pick localized strings via sealed `switch` on the enum/rule type.
- **Priorities read P1..P5 — 1 is highest** (since v18). Display (icon + label) comes only from `EventPriorities` (`lib/constants/event_priorities.dart`); ranking sites map `event.priority - kMinEventPriority` into the 0-is-top bar/summary band and sort ascending via `EventAgenda.compareWithinDay` — the **single same-day comparator** (the day panel's `EventSummaryProvider` emits through it; `DaySummaryResolver.resolve` is a stable sort so that order survives). Never reintroduce a numeric +/- stepper for priority.
- The bottom panel (`CalendarBottomPanel`) owns panel mode + agenda filters **below the page** so agenda keystrokes never rebuild the grid; keep new panel-local state there, not on `CalendarPage`. Agenda scans live in `EventAgenda` (pure, range clamped to 366 days) — never inside `eventLoader`, never in the bloc. Agenda filter persistence: `UpcomingAgendaFilters` ↔ `SettingsService` (empty priority set = "all"; query debounced + flushed on dispose; elapsed custom ranges dropped on load).
- Agenda text search folds through the note search's `normalizeForSearch` (case + diacritics) — never `toLowerCase().contains`.
- `.ics` export goes `IcsSerializer` → `ImportExportService.exportCalendar` → `ExportCalendarRequested`; do not add an `ics` `ExportFormat` variant (it would appear in note-format pickers).

## Event editor sheet (`lib/widgets/event_editor_sheet.dart`)

- `FractionallySizedBox(heightFactor: 0.92)`; **inline header row** `close | centered title | FilledButton(Save)` — never a bottom action bar with dividers. Delete (when editing) lives at the bottom of the scrollable body.
- Category selection is a `_PickerTile` → `CategoryPickerSheet` (returns the category **id**), never a chip Wrap. Recurrence frequency stays as `ChoiceChip`s.
- Preserve: `_initRecurrenceFrom` sealed rehydration; `_buildRule()` wraps weekday sets in `Set.unmodifiable`; `_canSave` = title non-empty AND (not weekly OR weekdays non-empty); `_pickDate` re-anchors weekdays only when the previous selection was the implicit default; `!mounted` early-returns after awaits; on edit use `copyWith(... clearIconKey: _iconKey == null)`.
- Interval stepper (`_IntervalStepper`) appears only for daily/weekly/monthly/yearly, clamped 1–99. Picking the birthday built-in on a still-one-time event pre-fills yearly recurrence (never overrides a user-configured rule).

## Recurrence semantics (keep consistent)

One-time = start only. Daily/weekly/monthly/yearly carry `interval` (weekly uses a fixed Monday-aligned week grid, `_weekEpoch = 2000-01-03`); short months and non-leap Feb 29 are silently skipped. Workdays = Mon–Fri AND not a public holiday (semantic — do not relax). Weekends = Sat–Sun. Holidays-only = `PublicHolidays.isHoliday(day)`. Every rule guards `day.isBefore(start)` first; `endDate` is enforced at the model layer in `occursOn`.

## Change-set recipes

- **New persisted event field**: Drift table + migration (idempotent, `PRAGMA table_info` guard) → DAO → `CalendarEventService` mapping → model `copyWith` (+ `clearX` flag if nullable) → editor UI → backup export/import → `dart run build_runner build --delete-conflicting-outputs` → ARB keys ×3 + `flutter gen-l10n`.
- **New holiday profile**: `HolidayProfile` enum value → `profileNameOf` switch → `holidayProfile<Name>` ARB trio → `_<name>Seeds(year)` builder dispatched from `_buildSeeds`; new holidays also need a `PublicHoliday` enum value + `nameOf` branch + `publicHoliday<Name>` ARB trio. The settings dropdown auto-enumerates. No schema change.
- **New calendar setting**: `CalendarSettingsPage` (mirror `_buildSectionCard` / `_buildSliderTile` helpers) + `SettingsService` getter/setter + `SettingsKeys` key + reset-to-defaults. Count sliders show bare numbers; only time-based sliders get an `s` suffix.

## Appearance system (customizable calendar UI)

- `CalendarAppearance` (`lib/models/calendar_appearance.dart`) bundles every look & feel option: `CalendarTodayStyle` (tonal/ring/filled), `CalendarMarkerStyle` (bars/dots), `CalendarWeekStart` (monday/saturday/sunday), optional accent ARGB (`null` = theme primary via `accentOr`), `highlightWeekends`, `showWeekNumbers`, `maxDayBars`. Loaded via `SettingsService.getCalendarAppearance()`; enums parse with forward-compatible fallbacks (`fromName`).
- Day cells are rendered by `CalendarDayCell` (`lib/widgets/calendar_day_cell.dart`): the day number lives in a fixed 34px chip anchored to the **top** of the cell; markers own the bottom strip. The page computes `rowHeight` from `CalendarDayCell.chipZoneHeight + CalendarDayBars.stripHeight(maxBars, style)` so highlights and markers can never overlap — never revert to table_calendar's default whole-cell decorations.
- `CalendarDayBars` renders both marker styles; new marker styles must extend it and `stripHeight`. Week-start labels come from `intl` weekday names anchored on 2024-01-01 (Monday) + `toBeginningOfSentenceCase` — no ARB weekday matrix.
- The settings page hosts a live `_AppearancePreview` built from the same `CalendarDayCell`/`CalendarDayBars` widgets the grid uses — keep it that way so the preview can't drift from reality.

## Panel / agenda / timeline file map

- [lib/widgets/calendar_bottom_panel.dart](../../../lib/widgets/calendar_bottom_panel.dart) — panel-mode switch + expand toggle; owns `CalendarPanelMode` + `UpcomingAgendaFilters` state and persistence.
- [lib/models/calendar_panel_mode.dart](../../../lib/models/calendar_panel_mode.dart), [lib/models/upcoming_agenda_filters.dart](../../../lib/models/upcoming_agenda_filters.dart) — persisted panel state (forward-compatible parsing; CSV/date-range codecs degrade to defaults on junk).
- [lib/utils/event_agenda.dart](../../../lib/utils/event_agenda.dart) — pure occurrence/holiday range scans + `compareWithinDay`.
- [lib/widgets/upcoming_agenda_view.dart](../../../lib/widgets/upcoming_agenda_view.dart) — controlled agenda (search field, period/priority/holiday chips).
- [lib/widgets/agenda_list_view.dart](../../../lib/widgets/agenda_list_view.dart) — grouped rows (memoized; holiday interleave; entries via `EventSummaryProvider`).
- [lib/widgets/day_timeline_view.dart](../../../lib/widgets/day_timeline_view.dart) + [lib/utils/day_timeline_layout.dart](../../../lib/utils/day_timeline_layout.dart) — hour grid; the only surface using `EventTime.durationMinutes`.
- [lib/utils/ics_serializer.dart](../../../lib/utils/ics_serializer.dart) — RFC 5545 export (see hard rules).
- [lib/constants/event_priorities.dart](../../../lib/constants/event_priorities.dart) — the one home for priority icons/labels.

Backup: `BackupService` round-trips `calendar_categories`, `calendar_events`, `public_holidays` (backup version **7**: priorities stored 1-is-highest, older versions flipped on import; categories import **before** events). Old backups must keep importing.
