---
name: anta-context
description: "Use when working in the ANTA Flutter app (Dart package `anta`). Loads product purpose, architecture, persistence rules, l10n requirements, validation commands, and UX direction for this offline-first personal tracker built on Flutter, BLoC, Drift SQLite, table_calendar, and re_editor. USE FOR: implementing or changing folders, notes, markdown editor, markdown shortcuts, the money ledger, counters (global and per-note), calendar/events, backup/restore, multi-database management, settings, onboarding, search, or anything touching tracking workflows. DO NOT USE FOR: unrelated Flutter projects or generic Dart questions."
---

# ANTA Context Skill

Load this whenever a task touches the `frontend/anta/` Flutter workspace. It sets product framing, architecture rules, and validation steps so changes stay consistent with the existing app. The on-disk `gym_notes` database directory is a separate, load-bearing runtime path — never rename it.

## 1. Load The Canonical Context

Read [COPILOT_CONTEXT.md](../../../COPILOT_CONTEXT.md) before planning or editing. It is the source of truth for:

- Product purpose and user workflows (notes, money ledger, calendar, counters).
- Non-negotiable rules (localization, generated files, build_runner, no unsolicited tests/comments).
- Stack, architecture flow, main feature areas, persistence rules.
- Localization, UI/UX direction, error handling, validation commands.
- Defaults for adding new tracking features.

Do not restate that file back to the user; just follow it.

## 2. Quick Decision Checklist

Before writing code, confirm:

1. Does the change require new persisted data?
   - If yes, decide between: note markdown content, a counter, a setting, or a new Drift table/migration.
   - New tables/columns require a Drift migration and a `dart run build_runner build --delete-conflicting-outputs` run. Never reset storage.
2. Does the change add or rename user-visible text?
   - If yes, update `lib/l10n/app_en.arb`, `app_de.arb`, and `app_ro.arb`, then run `flutter gen-l10n`.
3. Does the change touch BLoCs, services, repositories, or DAOs?
   - Keep the flow `Page → BLoC → Service → Repository → DAO → Drift`.
   - Match the local style for sealed/Equatable states, events, and `copyWith`.
   - Invalidate caches after creates, updates, deletes, moves, and reorder ops.
4. Does the change affect the editor, auto-save, or note position?
   - Preserve auto-save reliability (debounce, interval, retry, lifecycle flush).
   - Keep cursor and preview position persistence behavior intact.
5. Does the change affect counters?
   - Respect `scope` (`global` vs `perNote`), `isPinned`, ordering, and `noteId == ''` for global values in `counter_values`.
   - Counter shortcuts use `CustomMarkdownShortcut.counters` (`List<CounterBinding>`, max 2) with `{c1}` / `{c2}` tokens in `beforeText` / `afterText` / repeat wrapper text. Each binding has its own `CounterOp` (`increment` / `decrement`). Tokens are expanded by `ShortcutApplier` via the `CounterMutator` callback, which routes through `CounterBloc` and respects scope. Each token occurrence mutates once per repeat iteration. Keep the legacy `counterId` field populated when `insertType == 'counter'` so existing single-counter shortcuts continue to work; rely on `shortcut.effectiveCounters` to read bindings uniformly in new code.
6. Does the change affect backup/restore?
   - Add new persisted fields to backup export/import without breaking older backups.
7. Does the change touch import/export of notes or folders?
   - Go through `ImportExportBloc` from the UI; never call `ImportExportService` or `SharePlus` directly from a page/widget.
   - Preserve `createdAt`/`updatedAt` and folder sort preferences across round-trips by routing through the `importX` methods (`FolderDao.importFolder`, `NoteDao.importNote`, plus the matching repository/service wrappers). Use `createX` only for genuine user-initiated creates.
   - Bumping the archive schema requires bumping `ImportExportService.archiveVersion` *and* updating `_assertSupportedManifest` to accept the previous version.
   - Any export entry point must use `shareExport` (auto-cleans the temp file) and rely on the existing startup `sweepStaleExports` call in `main.dart`.
8. Does the change touch the markdown preview?
   - Keep the layering: `Page -> MarkdownPreviewBloc -> MarkdownRenderService -> LineBasedMarkdownBuilder` and `MarkdownPreviewBlocView -> SourceMappedMarkdownView`.
   - Never put `InlineSpan`s or builders in bloc state; bump `renderHandle` and let the widget pull spans from `bloc.renderService` on demand.
   - Theme dispatch (`PreviewThemeChanged`) belongs in `MarkdownPreviewBlocView` lifecycle hooks, never in `build()`.
   - Forward scroll progress directly to `bloc.scrollController.updateProgress(...)`; do not route per-frame scroll signals through the event queue.
   - Wire link taps via `MarkdownPreviewBlocView.onTapLink`. The page-level handler must validate URL schemes (allowed: `http`, `https`, `mailto`, `tel`) before calling `launchUrl`, and surface failures via `CustomSnackbar.showError` with the `linkOpenFailed` / `linkSchemeNotAllowed` ARB keys.
   - **Content sync pattern**: call `bloc.bindContentProvider(() => controller.text)` once in `initState`. On every keystroke call `bloc.markContentDirty()` (free). Dispatch `PreviewContentRefreshRequested` (debounced) for background refresh of the offstage preview; use `PreviewContentChanged` only for eager pushes (toggle, checkbox, locale change, load). Never dispatch `PreviewContentChanged` inside `build()`.
   - **Search sync**: `_pushPreviewContent` and `_scheduleLivePreviewRefresh` call `_searchController.updateContent(content)` when searching. Never call `updateContent` from `build()`.
   - **Preview view key**: the page owns `final GlobalKey<SourceMappedMarkdownViewState> _previewViewKey`. Bind it with `bloc.scrollController.bindView(_previewViewKey)` in `initState` and pass `viewKey: _previewViewKey` to `MarkdownPreviewBlocView`. Read `_previewViewKey.currentState?.currentLineIndex` for preview→editor scroll mapping on toggle.
   - **Toolbar**: use `_buildMarkdownBar({required bool enabled})` helper for both loading and loaded paths. Never duplicate the `MarkdownBar(...)` instantiation.
   - **re_editor package**: preserve the 2-slot `asString` cache, bounded LRU paragraph cache, binary-search paragraph/chunk lookups, 50 ms highlight debounce, and `cloneShallowDirty()` contract. Any new mutation path on `CodeLines` must call `cloneShallowDirty()`.
9. Does the change affect the calendar/events feature?
   - Preserve the current drawer route: `AppDrawer` closes the drawer, then calls `AppNavigator.toCalendar(context)`, and `toCalendar` must remain a normal `push` so the previous page stays on the navigation stack.
   - Calendar-specific options (max day bars, holiday set/profile, and any future calendar toggles) live on the dedicated **`CalendarSettingsPage`** reached from the gear icon in the calendar's own app bar (`AppNavigator.toCalendarSettings`), **not** on the controls settings page. Do not re-add calendar options to `ControlsSettingsPage`.
   - Custom calendar events are persisted via `CalendarEventService` → `CalendarEventDao` → `calendar_events` Drift table (schema v15: v10 introduced the table, v11 added `end_date` + time-of-day columns, v12 added `description`, v13 reworked `public_holidays`, v14 added the optional `note_id` event↔note link, v15 added the data-driven `calendar_categories` table). The recurrence **interval** ("every N …") shipped with no migration — it is encoded inside the existing `rule_payload` JSON. `CalendarBloc` is constructed via DI with the service and reloads its cache on `LoadCalendarEvents`. Public holidays live in the `public_holidays` table seeded by `PublicHolidayService` with add-if-not-exists semantics over a six-year forward window, scoped to the current `HolidayProfile` (`generic`, `romania`, `unitedStates`, `unitedKingdom`, `germany`, `europe`, `none`).
   - **Event categories are data-driven (v15), not an enum.** `CalendarEvent.categoryId` is a `String`; categories live in the `calendar_categories` table behind `CategoryService` → `CalendarCategoryDao`, with the synchronous `CalendarCategories` facade (constants/calendar_categories.dart) mirroring the `PublicHolidays` cache pattern (O(1) `byId`/`resolve`/`all`/`labelOf`/`iconFor`). Built-ins are seeded insert-if-missing with **stable ids equal to the historical `CalendarEventCategory` enum names** (`'gym'`, …) which match the strings already in `calendar_events.category`, so existing events link with **no data migration**. The `CalendarEventCategory` enum survives only as the built-in seed catalog + the source of localized built-in labels. Unknown ids resolve to a fallback (`other`) so deleting a category never corrupts its events; `CategoryService.deleteCategory` also reassigns those events to `other` in a transaction. Built-ins cannot be deleted. Users create/edit categories via `CategoryEditorSheet` (name + icon + color swatches) reached from `CalendarCategoriesPage` (`AppNavigator.toCalendarCategories`, linked from `CalendarSettingsPage`) or inline from `CategoryPickerSheet`'s "Create category" entry. The calendar filter is a **hidden-id set** (`CalendarPageLoaded.hiddenCategoryIds: Set<String>`, empty = show all) via `ChangeHiddenCategories`, so new categories are visible by default.
   - `TableCalendar.eventLoader` must stay a pure O(1) lookup through `CalendarBloc.eventsForDay`; do not dispatch events, call services, or perform recurrence expansion from `eventLoader`. `eventsForDay` is **memoized** in a bounded per-day cache (`_dayCache`, cap 512) that is invalidated **only** by the handlers which change its inputs (`LoadCalendarEvents`, `CreateCalendarEvent`, `UpdateCalendarEvent`, `DeleteCalendarEvent`, `ChangeHiddenCategories`). If you add a handler that mutates events or the category filter, call `_invalidateDayCache()`; never invalidate from day/focus/format handlers.
   - Persisted events require a Drift table/migration, DAO, repository, service, backup export/import, and `dart run build_runner build --delete-conflicting-outputs` before analysis.
   - User-visible calendar strings must be added to all three ARB files and regenerated with `flutter gen-l10n`.
10. Does the change add a new DB-backed singleton service (or convert an existing one)?
    - Follow the `DatabaseLifecycle` contract — see the **Database Lifecycle** section below. Every singleton holding a `late AppDatabase _db` (or any cached state derived from the DB) MUST expose a static `reset()` and register it with `DatabaseLifecycle.registerResetHandler(reset)` inside its `getInstance()` first-time-init block. Skipping this leaves the singleton bound to a closed database after a multi-database switch.
11. Does the change touch app-launch navigation / last-location restore?
    - On cold launch the app reopens the last-visited folder (and note) via `AppNavigator.restoreLastLocation()`, fired once from `main.dart` `_checkOnboarding` (guarded by `_didRestoreLocation`, and skipped while onboarding shows). `AppNavigator.toFolder` / `toNoteEditor` / `toNoteEditorInstant` record the location through `SettingsService.saveLastFolder` / `saveLastNote` (keys `last_folder_id`, `last_folder_title`, `last_note_id`). Restore validates existence (`FolderStorageService.getFolderById`, `NoteRepository.getNotesByIds`) and clears stale entries; it pushes onto the **root navigator** so Back still returns home. Keep the existence checks — never navigate to a deleted folder/note.

## 3. Style Rules To Enforce

- No code comments unless explicitly requested.
- No new tests unless explicitly requested.
- No new markdown documentation files unless explicitly requested.
- Use `AppLocalizations.of(context)!.keyName` for every user-visible string.
- Use existing constants from `lib/constants/` (spacing, text styles, icon sizes, settings keys, JSON keys, app constants) instead of magic values.
- Prefer compact, touch-friendly Material 3 UI with stable layouts.

## Calendar Feature Notes

`table_calendar: ^3.2.0` is installed and `main.dart` initializes locale date formatting with `initializeDateFormatting()`. The calendar is reachable from the drawer as the **first entry** (it is a feature, not a setting, so it sits above the settings list and is separated from it by a `Divider`). `AppDrawer` closes the drawer first, then calls `AppNavigator.toCalendar(context)`, which **must remain a normal `push`** so the previous page stays on the stack. Calendar-specific settings live on their own page, opened from a settings gear in the calendar app bar (`AppNavigator.toCalendarSettings`).

### Status (persisted as of schema v15)

Custom events, user-creatable categories, and public holidays survive hot restart and are included in backup/restore. `CalendarBloc` depends on `CalendarEventService` (singleton, in-memory cache backed by the `calendar_events` table). Public holidays are seeded into the `public_holidays` table by `PublicHolidayService` on every startup using insert-if-not-exists scoped to the active `HolidayProfile`, then mirrored into the static cache consumed by `PublicHolidays.isHoliday` / `PublicHolidays.holidayOn`. `BackupService` round-trips `calendar_categories`, `calendar_events`, and `public_holidays` (backup `version: 4`; categories import **before** events so category ids resolve). Old backups (v3 and earlier) still import — missing `calendarCategories` just leaves the seeded built-ins in place.

Slider label convention: the controls-settings `_buildSliderTile` takes an optional `labelBuilder` so only genuinely time-based sliders (auto-save interval) show a `s` suffix; count sliders (preview lines-per-chunk, calendar max day bars) show the bare number. Never hardcode a unit suffix on a generic slider helper.

Migration timeline:
- **v10**: `calendar_events` + `public_holidays` introduced.
- **v11**: `calendar_events.end_date` (nullable inclusive upper bound for recurrences) plus `start_minute` / `duration_minutes` columns for timed events.
- **v12**: `calendar_events.description` (nullable free-form body).
- **v13**: `public_holidays` rebuilt with composite PK `(date, name_key)` and a `profile` column (`generic` | `romania` | `custom`). Migration is an idempotent SQLite table-rebuild guarded by `PRAGMA table_info('public_holidays')`.
- **v14**: `calendar_events.note_id` (nullable link to `notes.id`). Idempotent `ALTER TABLE … ADD COLUMN` guarded by `PRAGMA table_info('calendar_events')`. `NULL` = no linked note.
- **v15**: `calendar_categories` table (id PK, name, color_value, icon_key, sort_order, is_built_in, created_at, updated_at) for data-driven, user-creatable categories. Created via idempotent `CREATE TABLE IF NOT EXISTS`; built-ins are seeded by `CategoryService` (not the migration) with stable ids == the old enum names, so `calendar_events.category` needs no rewrite.
- **(no migration)**: recurrence `interval` lives inside `rule_payload` JSON; only written when `> 1`, decoded with a safe fallback to `1`.

### Files and their roles

- [lib/pages/calendar_page.dart](lib/pages/calendar_page.dart) — host page. Owns `TableCalendar` + day-bars + day-summary panel. Format toggle (month / two-week / week) with localized labels. FAB opens the event editor for the selected day. Long-press on a summary entry edits the event. App bar has a category filter action and a settings gear; the gear pushes `CalendarSettingsPage`, then on return reloads `_maxDayBars` from settings and dispatches `LoadCalendarEvents` so changed holiday profiles / bar density re-render.
- [lib/pages/calendar_settings_page.dart](lib/pages/calendar_settings_page.dart) — dedicated calendar settings page (`SettingsAppBar(showMenuButton: false)` since it's reached from the calendar, not the drawer). Hosts the **max day bars** slider (`SettingsService.getCalendarMaxDayBars` / `setCalendarMaxDayBars`, key `SettingsKeys.calendarMaxDayBars`, default `defaultCalendarMaxDayBars = 3`, range 1–6) and the **holiday set** dropdown (`HolidayProfile` via `PublicHolidayService.setProfile`, optimistic + resync-on-failure). Reset-to-defaults resets both. Add any new calendar option here, mirroring the `_buildSectionCard` / `_buildSliderTile` helpers.
- [lib/bloc/calendar/calendar_bloc.dart](lib/bloc/calendar/calendar_bloc.dart) + [lib/bloc/calendar/calendar_event.dart](lib/bloc/calendar/calendar_event.dart) — app-level `CalendarBloc` registered in the root `MultiBlocProvider`. Sealed events (`CalendarPageEvent`): `LoadCalendarEvents`, `SelectCalendarDay`, `ChangeFocusedDay`, `ChangeCalendarFormat`, `ChangeHiddenCategories`, `CreateCalendarEvent`, `UpdateCalendarEvent`, `DeleteCalendarEvent`. `LoadCalendarEvents` is the reload/refresh event. Sealed states (`CalendarPageState`: Initial/Loading/Loaded/Error) with `Equatable`. Public API: `bloc.eventsForDay(day)` — amortized O(1) lookup used by `TableCalendar.eventLoader` and the day-summary panel (no event dispatch, no service calls, no recurrence expansion from `eventLoader`). It memoizes per-day recurrence expansion in a bounded cache invalidated only when events or the category filter change; the previously duplicated `CalendarPageLoaded.selectedEvents` getter was removed so there is one cached expansion path.
- [lib/models/calendar_event.dart](lib/models/calendar_event.dart) — value object: `id, title, description?, categoryId (String — id of a CalendarCategory), startDate, endDate?, time (EventTime?), rule (RecurrenceRule), noteId (String?), iconKey (String?)`. `allDay` is **derived** as `time == null` — the persisted `all_day` column is written from this on save and ignored on read. `noteId` is an optional link to a workout note (`notes.id`); only the id is stored and the folder is resolved at navigation time. `copyWith` accepts `clearIconKey`, `clearTime`, `clearDescription`, `clearEndDate`, `clearNoteId` (all `bool`) for explicit nulling. `occursOn(day)` normalizes both dates to UTC date-only and delegates to `rule.occursOn`, also enforcing the optional `endDate` upper bound on the rule.
- [lib/models/event_time.dart](lib/models/event_time.dart) (lives inside `calendar_event.dart`) — `EventTime { startMinute (0..1439), durationMinutes? (>0) }`. `endMinute` may exceed `1440` to model events that cross midnight; presentation/clipping is the caller's responsibility.
- [lib/models/recurrence_rule.dart](lib/models/recurrence_rule.dart) — sealed `RecurrenceRule extends Equatable` with `bool occursOn(DateTime day, DateTime start)`. The four periodic rules carry an `interval` field (default `1`, asserted `>= 1`); `interval == 1` short-circuits to the original behaviour. Subclasses (all `final class`):
  - `OneTimeRecurrence` — single occurrence on `start`.
  - `DailyRecurrence({int interval})` — every `interval` days on/after `start` (`(day - start).inDays % interval == 0`).
  - `WeeklyRecurrence({Set<int> weekdays, int interval})` — 1=Mon..7=Sun. Defensive: empty set → false. With `interval > 1`, only matching weeks fire, counted on a **fixed Monday-aligned grid** (`_weekEpoch = 2000-01-03`) so A/B splits stay phase-stable regardless of the anchor's weekday. `props` includes `weekdays` + `interval`.
  - `MonthlyRecurrence({int interval})` — `day.day == start.day` and whole-month delta `% interval == 0`; naturally skips months that lack the start day.
  - `YearlyRecurrence({int interval})` — same month+day and `(day.year - start.year) % interval == 0`; naturally skips Feb 29 in non-leap years.
  - `WorkdaysRecurrence` — Mon–Fri AND `!PublicHolidays.isHoliday(day)`.
  - `WeekendsRecurrence` — Sat–Sun.
  - `PublicHolidaysOnlyRecurrence` — `PublicHolidays.isHoliday(day)` only.
  - Every rule guards `if (day.isBefore(start)) return false` first. The fixed cadences (workdays/weekends/holidays) have no interval.
- [lib/services/event_time_formatter.dart](lib/services/event_time_formatter.dart) — pure helper. `EventTimeFormatter.formatRange(time, l10n, localeName)` produces a localized `HH:mm – HH:mm` (or `HH:mm`) string; respects 24h/12h locale conventions via `intl`. Use everywhere a timed event is rendered (day summary, editor preview, week view).
- [lib/services/recurrence_formatter.dart](lib/services/recurrence_formatter.dart) — pure helper. `format(rule, l10n, localeName)` does a sealed switch and returns a localized, **interval-aware** string (e.g. `Weekly · Mon, Wed, Fri`, `Every 2 weeks · Mon, Thu`, `Public holidays only`) via the ICU-plural `recurrenceEvery*` keys. `weekdayShort(weekday, localeName)` uses 2024-01-01 (Monday) as the anchor + `DateFormat.E(localeName)`; never add a 7×3 ARB matrix for weekday names. `formatWeekdays(Set<int>, localeName)` sorts then comma-joins.
- [lib/constants/calendar_colors.dart](lib/constants/calendar_colors.dart) — only the **contextual** (non-event) colors `CalendarColors.weekend` / `CalendarColors.publicHoliday`. Per-category tints are data-driven (`CalendarCategory.color`, seeded in `CalendarCategories.builtInSeeds`); the old per-category constants + `forCategory` switch were removed when categories became data-driven.
- [lib/constants/calendar_icons.dart](lib/constants/calendar_icons.dart) — **~60 icons** grouped into 10 `IconGroupId`s: `strength, cardio, sports, recovery, body, measurement, achievements, travel, time, generic`. API:
  - `CalendarIcons.forKey(String?) → IconData?` — key → icon lookup (the only resolver; categories and events store an `iconKey`). Built-in category default icons live in `CalendarCategories.builtInSeeds`; read paths use `CalendarCategories.iconFor(event)` (explicit per-event override wins, else the event's category icon). The `forCategory` enum switch was removed with the data-driven refactor.
  - `CalendarIcons.groups → List<IconGroup>` — ordered list of `IconGroup(IconGroupId id, List<String> iconKeys)`. Localize group labels via the `iconGroup*` ARB keys (`iconGroupStrength`, `iconGroupCardio`, …) — pick label with a sealed `switch` on `IconGroupId` in the picker, never via a generic `byKey` lookup (none exists).
- [lib/constants/public_holidays.dart](lib/constants/public_holidays.dart) — sync facade. `PublicHolidays.isHoliday(DateTime)` and `PublicHolidays.holidayOn(DateTime) → PublicHolidayInfo?` consult an in-memory cache populated by `PublicHolidayService.getInstance()` at startup. Use `PublicHolidays.labelOf(info, l10n)` for display (handles built-in enum entries and user-added custom labels). The `PublicHoliday` enum spans 33 values: 15 generic-Christian feasts (incl. movable Good Friday, Easter Sunday/Monday, Ascension, Pentecost, Whit Monday), 4 Romania-specific entries (`unificationDay`, `childrensDay`, `stAndrewDay`, `nationalDayRomania`), 9 US federal days (`martinLutherKingDay`, `presidentsDay`, `memorialDay`, `juneteenth`, `independenceDay`, `laborDayUnitedStates`, `columbusDay`, `veteransDay`, `thanksgiving`), 3 UK bank holidays (`earlyMayBankHoliday`, `springBankHoliday`, `summerBankHoliday`), `germanUnityDay`, and `europeDay`. The companion `HolidayProfile` enum (`generic`, `romania`, `unitedStates`, `unitedKingdom`, `germany`, `europe`, `none`) selects which subset gets seeded; helpers `profileNameOf(profile, l10n)` and `profileFromName(String?)` handle l10n + forward-compat parsing (unknown values fall back to `generic`). The `kCustomPublicHolidayKey` (`'custom'`) is the `name_key` sentinel for user-added rows; `kCustomHolidayProfileKey` (also `'custom'`) is the `profile` sentinel — they are separate concepts that happen to share a string. Fallback static map covers the fixed-date subset when the cache is empty (tests, pre-init).
- [lib/widgets/calendar_day_bars.dart](lib/widgets/calendar_day_bars.dart) — colored bar strip rendered via `TableCalendar.calendarBuilders.markerBuilder`. Reads from `DayBarsResolver` (provider/resolver pattern in `lib/services/day_bars_resolver.dart`). Lookup must be O(1) per day; never iterate events inside the marker builder.
- [lib/services/day_summary_resolver.dart](lib/services/day_summary_resolver.dart) — composes the bottom panel for the selected day. Providers implement `DaySummaryProvider`. `EventSummaryProvider` is the calendar-event implementation:
  - `icon: CalendarCategories.iconFor(event)` — picks up explicit per-event icon overrides, else the category icon.
  - `_subtitleFor(event)` returns `RecurrenceFormatter.format(...)` (when not `OneTimeRecurrence`) joined with `l10n.eventAllDay` via `·`.
  - Do **not** reintroduce the old `_recurrenceLabel(CalendarRecurrence enum)` helper — the enum is gone.
- [lib/widgets/event_editor_sheet.dart](lib/widgets/event_editor_sheet.dart) — the create/edit modal sheet. See structure below.
- [lib/widgets/icon_picker_sheet.dart](lib/widgets/icon_picker_sheet.dart) — own bottom sheet with `FractionallySizedBox(heightFactor: 0.85)`, `ListView.builder` over `CalendarIcons.groups`, each section is a localized header + `Wrap` of 48×48 circular tiles. Selected state: `tint.withValues(alpha: 0.18)` background + 2px tint border + tint foreground. Call site passes a `tint` (use `CalendarCategories.resolve(categoryId).color`).
- [lib/widgets/category_picker_sheet.dart](lib/widgets/category_picker_sheet.dart) — own bottom sheet for picking a category. `FractionallySizedBox(heightFactor: 0.7)`, `ListView.builder` over `CalendarCategories.all` (data-driven), each row is a `ListTile` with the category's tinted circular icon, localized/verbatim label, trailing check mark for the current selection. Returns the selected category **id** (`String`). Includes an inline "Create category" entry that opens `CategoryEditorSheet` and returns the new id.
- [lib/widgets/category_editor_sheet.dart](lib/widgets/category_editor_sheet.dart) — create/edit a category (name field, icon via `IconPickerSheet`, color via a swatch `Wrap`). Persists through `CategoryService`; built-ins keep their localized name (field read-only) but stay color/icon editable. Returns the saved `CalendarCategory`.
- [lib/pages/calendar_categories_page.dart](lib/pages/calendar_categories_page.dart) — category management list (create via FAB, edit on tap, delete custom rows). Service-direct (`CategoryService`), like the holiday settings.

### Event editor sheet layout (canonical)

The editor is a `FractionallySizedBox(heightFactor: 0.92)` bottom sheet built as a single `Column`:

1. **Inline header row** (NOT a centered title + Divider): `IconButton(close) | Expanded centered title | FilledButton(Save)`. The Save button lives in the header so the action surface visually belongs to the sheet — do **not** reintroduce bottom action-bar dividers; they made the actions look detached from the form.
2. `Expanded(SingleChildScrollView)` body containing, in order:
   - Title `TextField` (autofocus when creating, `maxLength: 120`).
   - `_SectionLabel(eventType)` + `_PickerTile` opening `CategoryPickerSheet`. **Category is a picker tile, not a chip Wrap** — it is a one-of-N selection so it belongs in a dialog.
   - `_SectionLabel(iconLabel)` + `_PickerTile` opening `IconPickerSheet`. Trailing is `chevron_right` when no override is set, or a reset `IconButton` when there is one.
   - `_SectionLabel(eventDate)` + `_PickerTile` opening `showDatePicker` (±20 years). Subtitle says "Starts on this date" when recurring.
   - `_SectionLabel(repeatMode)` + centered `SegmentedButton<_RepeatMode>` with `oneTime` / `recurring` options (`looks_one_rounded` / `repeat_rounded` icons).
   - If recurring: `_SectionLabel(frequency)` + `Wrap` of 7 `ChoiceChip`s over `_RecurrenceKind.values` (daily, weekly, monthly, yearly, workdays, weekends, holidays).
   - If recurring AND the kind supports an interval (daily/weekly/monthly/yearly): a `_IntervalStepper` (− / N / +) with a localized unit label (`recurrenceUnit*`), clamped to `1.._maxInterval` (99). `_kindSupportsInterval` / `_intervalUnitLabel` gate it; fixed cadences (workdays/weekends/holidays) hide it.
   - If recurring AND weekly: `_SectionLabel(weekdays)` + `Wrap` of 7 `FilterChip`s using `RecurrenceFormatter.weekdayShort(w, localeName)`. If the set becomes empty, show `weeklyDaysHint` in `error` color and `_canSave` disables Save.
   - Optional **time-of-day** section: an "All-day" switch; when off, start/end time `_PickerTile`s backed by `EventTime` (end may cross midnight).
   - Optional **description** `TextField` (`maxLength: 500`).
   - **Linked-note** `_PickerTile`: opens `NotePickerDialog` to attach a workout note; trailing reset clears it. The current title is resolved via `NoteRepository.getNotesByIds([id])` so soft-deleted notes resolve to empty (never a ghost title).
   - If editing: trailing `TextButton.icon(delete)` in error color **inside the scrollable body** (not in a bottom action bar). Tapping shows an `AlertDialog` using `deleteEventConfirm(title)`.

Private widgets in the editor file:
- `_SectionLabel` — labelLarge / onSurfaceVariant / padding `EdgeInsets.fromLTRB(0, 16, 0, 8)`.
- `_PickerTile` — `Card(margin: zero) + ListTile(leading, title, subtitle?, trailing ?? chevron_right, onTap)`.

Private enums:
- `enum _RepeatMode { oneTime, recurring }`
- `enum _RecurrenceKind { daily, weekly, monthly, yearly, workdays, weekends, holidays }`

State + behavior rules to preserve:
- `_initRecurrenceFrom(RecurrenceRule)` does a sealed switch to rehydrate `_mode`, `_kind`, `_weekdays` from an existing event.
- `_buildRule()` constructs the concrete `RecurrenceRule` at save time. Always wrap the weekday set with `Set.unmodifiable(...)`.
- `_canSave` = title non-empty AND (not weekly OR weekdays non-empty).
- `_pickDate` re-anchors `_weekdays` to the new date's weekday **only** when the previous selection was the implicit default (`length == 1 && first == old.weekday`). Explicit multi-day selections are preserved.
- `_pickIcon` / `_pickCategory` early-return on `!mounted` after `await`.
- `_onSave` builds a brand-new `CalendarEvent` on create (with `Uuid().v4()`); on edit, calls `copyWith(... clearIconKey: _iconKey == null)` so explicit-null overrides actually clear.
- `_titleController` is owned by the `StatefulWidget` and disposed in `dispose()`.

### Recurrence semantics (must stay consistent)

- **One time**: only on `start`.
- **Daily**: every `interval` days on/after `start` (default every day).
- **Weekly**: any day whose `weekday` is in the user-selected set; with `interval > 1` only every Nth week (fixed Monday-aligned grid) fires. Empty set → no occurrences (UI prevents saving).
- **Monthly**: same day-of-month, every `interval` months; short months are silently skipped (Jan 31 → no Feb 31 occurrence).
- **Yearly**: same month and day, every `interval` years; Feb 29 events only fire in leap years.
- **Workdays**: Mon–Fri AND not a public holiday. This is *semantic* "working day" — do not relax it to "Mon–Fri inclusive of holidays".
- **Weekends**: Sat–Sun only.
- **Public holidays only**: uses `PublicHolidays.isHoliday(day)`. Does not require the day to match `start` in any other way.
- **Interval** applies only to daily/weekly/monthly/yearly. All occurrence math is O(1) modular arithmetic on date-only UTC values — keep it that way; no per-day allocation, no DST-sensitive `DateTime` math.

### l10n keys owned by this feature

Calendar / event editor / pickers:
`addEvent, editEvent, deleteEvent, deleteEventConfirm, eventTitle, eventType, eventDate, eventAllDay, eventAllDayHint, eventStartTime, eventEndTime, eventEndTimeNone, eventEndTimeHint, eventTimeSection, eventCrossesMidnight, eventDescription, eventDescriptionHint, eventUntilLabel, eventUntilNone, eventUntilHint, save, cancel, delete, recurrence, recurrenceDaily, recurrenceWeekly, recurrenceMonthly, recurrenceYearly, recurrenceWorkdays, recurrenceWeekends, recurrenceHolidaysOnly, repeatMode, repeatOnce, repeatRecurring, frequency, weekdays, weeklyDaysHint, startsOn, iconLabel, iconDefault, iconCustom, pickIcon, pickCategory, resetToDefault`

Recurrence interval (ICU `plural`, `{count}`; Romanian also needs the `few` form):
`recurrenceEveryDays, recurrenceEveryWeeks, recurrenceEveryWeeksOn ({count},{days}), recurrenceEveryMonths, recurrenceEveryYears, recurrenceIntervalLabel, recurrenceIntervalIncrement, recurrenceIntervalDecrement, recurrenceUnitDays, recurrenceUnitWeeks, recurrenceUnitMonths, recurrenceUnitYears`

Linked note (v14):
`eventLinkedNote, eventLinkNoteHint, eventLinkedNoteMissing, eventOpenLinkedNote, eventRemoveNoteLink`

Calendar settings page:
`calendarSettings` (page title + app-bar gear tooltip), `calendarSection`, `calendarMaxDayBars`, `calendarMaxDayBarsDesc ({count})`, `holidayProfileTitle`, plus the shared `resetToDefaults` / `settingsReset` keys.

Category labels (one per built-in `CalendarEventCategory`; custom categories show their stored name verbatim):
`eventCategoryGym, eventCategoryCardio, eventCategoryRest, eventCategoryHoliday, eventCategoryCompetition, eventCategoryMeasurement, eventCategoryMobility, eventCategoryBirthday, eventCategoryOther`

Selecting the **birthday** built-in (`kBirthdayCategoryId`) on a still-one-time event in the editor pre-fills a yearly recurrence (it never overrides a recurrence the user already configured).

Category management (v15):
`calendarCategories, calendarCategoriesDesc, createCategory, editCategory, categoryName, categoryNameHint, categoryColor, categoryDefault, deleteCategory, deleteCategoryConfirm ({name}), categoryDeleted`

Icon group labels (one per `IconGroupId`):
`iconGroupStrength, iconGroupCardio, iconGroupSports, iconGroupRecovery, iconGroupBody, iconGroupMeasurement, iconGroupAchievements, iconGroupTravel, iconGroupTime, iconGroupGeneric`

`recurrenceWeeklyOn` was removed in v14 — the interval-aware `recurrenceEvery*` keys replace it. Keep the `{count}` / `{days}` plural metadata intact across all three ARBs.

### Persistence layout (schema v15)

- `lib/database/tables/calendar_categories_table.dart` — `CalendarCategories` (table `calendar_categories`): `id (PK), name, colorValue (ARGB int), iconKey, sortOrder, isBuiltIn, createdAt, updatedAt`. Built-ins seeded with stable ids == `CalendarEventCategory.name`.
- `lib/database/daos/calendar_category_dao.dart` — `getAll`, `insertIfMissing` (seed), `insertCategory`, `updateCategory` (masks `createdAt`), `deleteById`, `deleteAll`, `nextSortOrder`.
- `lib/services/category_service.dart` — singleton (`DatabaseLifecycle` reset). Seeds built-ins, loads + publishes the `CalendarCategories` cache, owns create/update/delete (+ event reassignment on delete) and backup export/import.
- `lib/constants/calendar_categories.dart` — the synchronous facade (cache + `builtInSeeds` + `labelOf`/`iconFor`/`resolve`/`fallback`). `CalendarEventDao.reassignCategory(from,to)` moves events when a category is deleted.
- `lib/database/tables/calendar_events_table.dart` — `CalendarEvents`: `id (PK), title, description? (v12), category (TEXT — stores the `CalendarCategory` **id**; built-ins use the enum name like `gym`, customs use a UUID; legacy column name kept), startDate (date-only UTC), endDate? (v11, inclusive upper bound for recurring rules), allDay, startMinute? / durationMinutes? (v11; sourced from `EventTime`), noteId? (v14, link to notes.id), iconKey?, ruleKind, rulePayload? (JSON: `weekdays` and/or `interval` when > 1), createdAt, updatedAt`.
- `lib/database/tables/public_holidays_table.dart` — `PublicHolidaysTable` (table name `public_holidays`): composite PK `(date, name_key)` plus `customLabel?` and `profile` (default `'generic'`). Built-in rows carry `nameKey == PublicHoliday.name` and `profile ∈ {generic, romania, unitedStates, unitedKingdom, germany, europe}`; user-added rows use `nameKey == kCustomPublicHolidayKey` (`'custom'`) and `profile == kCustomHolidayProfileKey` (`'custom'`). Switching profiles deletes only rows matching the previous profile — customs are preserved by virtue of carrying their own profile tag.
- `lib/database/daos/calendar_event_dao.dart` — `getAll`, `upsert(CalendarEventsCompanion)`, `deleteById`, `deleteAll`.
- `lib/database/daos/public_holiday_dao.dart` — `getAll`, `insertIfMissing({date, nameKey, profile, customLabel?}) → bool` (uses `InsertMode.insertOrIgnore`), `deleteOn(date)`, `deleteProfile(profile)`, `deleteAll`.
- `lib/services/calendar_event_service.dart` — singleton (`getInstance()` pattern). Owns row↔domain mapping including sealed-`RecurrenceRule` JSON serialization (`{kind, weekdays?, interval?}` — `interval` only written when `> 1`, decoded with a clamped fallback to `1`) and `EventTime` / `endDate` / `noteId` round-trips. Exposes synchronous `events` getter used by `CalendarBloc`.
- `lib/services/public_holiday_service.dart` — singleton. Reads the active `HolidayProfile` from settings on `getInstance()`, then seeds defaults for the current year + 5 forward years. `setProfile(next)` is transactional: `deleteProfile(prev) → write setting → seed(next)` inside `_db.transaction`, then `_load()` after commit so the static cache only republishes a coherent state. Per-profile seed builders (`_genericSeeds`, `_romaniaSeeds`, `_unitedStatesSeeds`, `_unitedKingdomSeeds`, `_germanySeeds`, `_europeSeeds`) are pure static functions; `none` returns `const []`. Movable Christian feasts use Meeus Anonymous Gregorian for Catholic Easter and Meeus Julian + dynamic Julian→Gregorian offset (`_julianToGregorianOffset`, constant 13 across 1900–2099, formula extends symbolically beyond) for Orthodox Easter. US/UK movable days (nth-Monday/Thursday, last-Monday) come from the `_nthWeekdayOfMonth` / `_lastWeekdayOfMonth` helpers. **Verified** against published Orthodox Easter dates 2023–2030.
- DI registration in `lib/core/di/injection.dart`: `CategoryService`, `PublicHolidayService`, and `CalendarEventService` are all awaited in `_registerServices` (categories before events); `CalendarBloc` is a factory taking `service: getIt<CalendarEventService>()`. `main.dart` uses `getIt<CalendarBloc>()..add(const LoadCalendarEvents())`.
- Backup: `BackupService` exports both tables. Public-holiday rows include `profile`; old backups missing the field are imported as `'generic'` (matches the v12→v13 back-fill rule).

When adding a holiday profile, the change set is: new enum value in `HolidayProfile`, new entry in `profileNameOf` switch, new `holidayProfile<Name>` ARB key trio, a new `_<name>Seeds(year)` builder dispatched from `_buildSeeds`; any new holiday it introduces also needs a `PublicHoliday` enum value + `nameOf` branch + `publicHoliday<Name>` ARB trio. The dropdown auto-enumerates `HolidayProfile.values`, so the new item appears automatically. No schema change needed. Existing built-in profiles: `generic` (Western Christian), `romania`, `unitedStates`, `unitedKingdom`, `germany` (federal nationwide only), `europe` (combined pan-European + Europe Day).

## Database Lifecycle (multi-database safety)

The app supports switching between multiple local databases on the database settings page. Every DB-backed singleton (`late AppDatabase _db`, cached rows, derived state) holds references that become stale when the active database changes. `lib/database/database_lifecycle.dart` provides the registry that keeps this correct-by-construction so we no longer rely solely on the "restart required" dialog to mask stale state.

### The contract for any DB-backed singleton

Every service that caches DB-derived state MUST:

1. Expose `static void reset() { _instance = null; ... }` that nulls the singleton and cancels any timers/streams it owns.
2. Call `DatabaseLifecycle.registerResetHandler(reset)` inside the `getInstance()` first-time-init block — **after** the instance is fully constructed and assigned to `_instance` (so a handler firing mid-init can't observe a half-built service).
3. If the service publishes data into a separate static cache (like `PublicHolidayService` does with `PublicHolidays._cache`), `reset()` must also clear that static cache. Otherwise the synchronous facade keeps returning the previous database's data until the new instance republishes.

The canonical pattern:

```dart
static Future<MyService> getInstance() async {
  if (_instance == null) {
    _instance = MyService._();
    _instance!._db = await AppDatabase.getInstance();
    await _instance!._load();
    DatabaseLifecycle.registerResetHandler(reset);
  }
  return _instance!;
}

static void reset() {
  _instance = null;
}
```

Services currently following this contract: `CounterService`, `CalendarEventService`, `CategoryService`, `PublicHolidayService`, `MarkdownBarService`, `SettingsService`, `DevOptionsService`, `BackupService`, `NotePositionService`. New singletons must join this list.

### Where the hook fires

`AppDatabase.getInstance({databaseName})` calls `DatabaseLifecycle.notifyDatabaseSwitching()` immediately before closing the previous `_instance`. `AppDatabase.deleteAllData()` does the same. The registry is self-clearing (handlers fire once per notify, then the list empties) so re-registration on the next `getInstance()` is the only way handlers stay subscribed — there is no `unregister`. The restart-required dialog after a manual DB switch stays in place because BLoC instances held by widgets still need a process restart to rebind; the lifecycle hook makes correctness independent of that dialog.

### Anti-patterns

- Holding a `late AppDatabase _db` in a singleton without a `reset()` + registration. This is a latent crash-after-switch.
- Caching DB data in a top-level `static` variable without a way to clear it from the owning service's `reset()`. Mirror the `PublicHolidays` / `PublicHolidayService` pairing.
- Registering a handler from a constructor that runs more than once per singleton lifetime — it duplicates. Always register from the `getInstance()` `if (_instance == null)` branch.

### Hard rules for calendar work

- `TableCalendar.eventLoader` stays a pure O(1) lookup through `CalendarBloc.eventsForDay` (memoized per day; cache invalidated only when events or the category filter change). No event dispatch, no service calls, no on-the-fly recurrence expansion inside the loader.
- Don't reintroduce the dropped `CalendarRecurrence` enum or `event.recurrence` field — they are gone for good. Always use `event.rule`.
- Don't read `event.allDay` directly to decide whether to render a time row — check `event.time != null`. The boolean is a derived persistence detail.
- Don't add a generic `AppLocalizations.byKey` — pick localized strings via sealed `switch` on `CalendarEventCategory` / `IconGroupId` / rule type / `HolidayProfile`.
- Don't render category icons/colors by hand on read paths — use `CalendarCategories.iconFor(event)` for the icon (explicit per-event override wins, else the category's icon) and `CalendarCategories.resolve(event.categoryId).color` for the tint. An unknown id resolves to the `other` fallback, never throws.
- Don't put the editor's Save/Cancel in a bottom action bar with dividers — they belong in the inline header row. Delete (when editing) lives at the bottom of the scrollable body, not in a footer.
- Category selection is a `_PickerTile` → `CategoryPickerSheet`, never a chip `Wrap`. Recurrence frequency stays as chips (the choice space is small and benefits from at-a-glance comparison).
- When adding a date picker anywhere in calendar code, use `DateTime.utc(y, m, d)` for normalization to match `CalendarEvent.occursOn`.
- When mutating `public_holidays`, never bypass `PublicHolidayService` — the static `PublicHolidays._cache` is rebuilt only by `_load()`, so direct DAO writes will desync the sync facade until the next app start.
- Resolve a linked note (`event.noteId`) via `NoteRepository.getNotesByIds([id])`, **not** `getNoteById` — the former filters `is_deleted`, so a soft-deleted note yields an empty list and you show `eventLinkedNoteMissing` instead of opening a ghost. `getNoteById` is cache-based and does not filter deletes.
- Keep the recurrence `interval` in `rule_payload` JSON (write only when `> 1`, decode with a clamped fallback to `1`). Do not add a dedicated `interval` column — it intentionally needs no migration.

## 4. Validation Commands (PowerShell On Windows)

Run only what the change requires.

```powershell
dart analyze lib
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Helper scripts:

```powershell
.\build_release.bat arm64
.\install_to_device.bat arm64
.\generate_drift.bat
```

Typical mapping:

- UI-only Dart change: `dart analyze lib`.
- ARB / l10n change: `flutter gen-l10n`, then `dart analyze lib`.
- Drift table / DAO / migration change: `dart run build_runner build --delete-conflicting-outputs`, then `dart analyze lib`.

## 5. When To Ask Vs Act

- Act without asking when the request is concrete, scoped, and matches existing patterns.
- Ask only when a change would alter persisted data shape in a non-backward-compatible way, change backup format semantics, or introduce a new architectural pattern (new state-management lib, new persistence layer, new navigation strategy).

## 6. Anti-Patterns To Avoid

- Hand-editing `lib/database/database.g.dart` or generated `app_localizations_*.dart` files.
- Resetting or wiping the local database to "fix" schema drift instead of writing a migration.
- Adding raw `SharedPreferences` keys instead of going through `SettingsService` + `SettingsKeys`.
- Hardcoding user-facing strings in Dart instead of using ARB + `AppLocalizations`.
- Introducing heavy work on the editor's hot path (per-keystroke string copies, synchronous DB writes, expensive rebuilds).
- Adding decorative UI churn that causes layout shifts in the editor, toolbar, counters, or folder/note lists.
- Calling `_searchController.updateContent` or any `ChangeNotifier.notifyListeners`-triggering method inside `build()`.
- Dispatching `PreviewContentChanged` eagerly on every keystroke — use `markContentDirty` + `PreviewContentRefreshRequested` for background/debounced refreshes.
- Creating an anonymous `GlobalKey<SourceMappedMarkdownViewState>()` inline — always hold it as a named page field so preview→editor scroll mapping and `viewKey:` wiring both reference the same instance.
- Duplicating the `MarkdownBar(...)` widget tree; use `_buildMarkdownBar({required bool enabled})`.
- Bypassing `cloneShallowDirty()` when adding new mutation paths to `CodeLines` in the re_editor package.
