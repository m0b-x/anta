---
name: calendar-events
description: The rulebook and file map for ANTA's calendar, events and alerts - the invariants a calendar change must keep and where each piece lives, with on-demand references for each surface's anatomy, the schema lineage and the dated change log. USE FOR - any change to the calendar's pages, bloc, services, models or widgets; to how events are stored, recur, are filtered or drawn; to categories, public holidays or fasting; to presence, skipped days, per-occurrence descriptions or templates; to grid filters, saved filters, the agenda or the overview; to the event editor or any of its sub-sheets; to alerts - scheduling, notifications, the Alerts hub, the alarm page, the quick alarm. Load together with anta-context; add ui-language and calendar-ui for anything visual.
---

# Calendar & Events

## Hardest constraints

- **The eight calendar services are lazy**: `await X.getInstance()`, never `GetIt.I<>`; `CalendarBloc._onLoad` awaits all eight in one wrapped `Future.wait` and **only then emits `CalendarPageLoaded`**; other facade readers live under it or await the owner.
- `TableCalendar.eventLoader` is `CalendarBloc.eventsForDay`: memoized per day, pure O(1). Never dispatch, call a service or expand a recurrence inside it.
- A handler changing events or filters calls `_invalidateDayCache()` in its emit's synchronous turn, after the last await; never a day / focus / format handler. Async handlers re-read `state` after the last await.
- A re-load copies `CalendarPageLoaded` (`selectedDay`, `focusedDay`, `format`, `selectionSource`) and bumps `membershipRevision`.

## Reading map

Read only the `docs/calendar-events-feature.md` section you touch (§1–§13: v14 baseline + alerts; then dated or versioned addenda).

| Topic | Doc section |
| --- | --- |
| Domain model, recurrence engine, holidays, persistence, backup | §2–§7 |
| Event alerts (v40) | §12, plus `docs/event-alerts-roadmap.md`, `docs/event-alerts-os-integration-roadmap.md`; the alarm page and the notifications: `docs/alert-surfaces-redesign-roadmap.md` |
| Panel modes, agenda, timeline, `.ics`, priority scale | Addendum v15–v18 |
| Presence, CRDT, description scope, templates, skips | Addenda v26–v30, v37; `docs/presence-tracking-roadmap.md`, `docs/description-scope-roadmap.md` |
| Day-cell tints, day rail | "day-cell tint layers", v34; `docs/day-rail-markers-roadmap.md` |
| Keyboard-aware grid, agenda cards, sheet bottom clearance | 2026-08-24 / 08-25 |
| Search grammar, agenda search | 2026-08-24 / 08-25 |
| Description editing, `EventDescriptionSheet` | 2026-08-31 |
| Settings page folding, grid filters, saved filters (v35) | 2026-09-01 |
| Colour palette and picker, drill-down modes | 2026-09-02 |
| Add button, panel ground | 2026-09-14 |
| Time pad | 2026-09-24 |
| Event editor redesign, the Dates sheet | 2026-09-25 (+ `docs/event-editor-redesign-roadmap.md`) |
| Overview page, year paging, the card's look | 2026-09-26 |
| The header: view menu, ⋮, switching pages | 2026-09-26 header addendum (+ `docs/calendar-header-roadmap.md`) |
| Fasting schedule | §4.5 is the behaviour of record; `docs/fasting-schedule-roadmap.md` the design record |
| Categories at scale | `docs/category-scaling-roadmap.md` |

Reworks follow `ui-revamp`. **Before changing a surface, read its section in `references/subsystems.md`**.

## Schema lineage (current v40)

Chain: `references/schema-lineage.md`. Rules for every version:

- Recurrence **interval rides in `rule_payload`** (written only when `> 1`, decoded clamped to 1); never an `interval` column.
- Additive columns: `PRAGMA table_info` guards, defaults an old row already meant, **no backfill**; backup stays v7 unless import semantics change.
- A **swapped index is dropped and recreated** (v27 / v37); `IF NOT EXISTS` alone strands upgraders.
- A new index goes in the creator whose tables exist when it runs (`createCalendarDeltaIndexes()` vs `createCalendarIndexes()`).
- `alert_registrations` is **device-local**: no CRDT, hard deletes, never exported or synced.
- Backup: an absent `eventOccurrences` / `eventSkips` / `eventAlerts` beside `calendarEvents` **clears** the table; `calendarFilterPresets` has no strand rule; categories import **before** events.

## Bloc, caches, revisions

- `_syncGenerations` heads **both** `eventsForDay` and `monthNetFor`; holiday revisions are a **generation** (drop the cache, never widen the key).
- `CalendarPageLoading` is **never emitted**; `_didInitialLoad` gates the first load only.
- Never inline the `monthNetFor` scan into `headerTitleBuilder`. `loadContentForNotes`: absent = unreadable, `''` = empty; never `?? ''`.
- Descriptions and presence bump `occurrenceRevision` (agenda never rescans), presence also `presenceRevision`; skips and reloads `membershipRevision`.
- A presence default flip bumps nothing: never value-compare `allEvents`. Handlers build fresh `allEvents` / `filters` (compared by identity).
- Callbacks read `context.read<CalendarBloc>().state` at press time.
- Only `importData()` / `reset()` bump `CalendarEventService.externalRevision`. Sheets never fire the `RouteObserver`.

## Services and facades

- Only `PublicHolidayService` mutates `public_holidays`; only its `_load()` republishes `PublicHolidays`.
- `CategoryService` mutations share one chain whose tail starts **`null`**; `updateCategory` never writes `sort_order` / `is_built_in` / `is_hidden`; `setHidden` writes only the flag.
- `FilterPresetService` has no facade (await it), refuses past 50. The occurrence-descriptions `reset()` clears singleton and facade.
- `FastingCalendar.resetConfiguration()` belongs to `SettingsService.reset`, never a direct `DatabaseLifecycle` registration. Counts per category: `countByCategory()`.

## Settings

- Calendar settings load in **one statement** (`getCalendarPageSettings()`), one pure decoder per setting; keys in `_calendarAppearanceKeys` / `_calendarPageKeys`; never `getAllSettings()`.
- Keep absent-vs-empty in `getFastingSchedule` / `getFastingAppearance`. Enums parse forward-compatibly (`fromName`).
- `CalendarAppearance` and the palette are **passed down from `CalendarPage`**, never re-read in a leaf. Weekday labels from `intl`, never an ARB matrix.
- New setting: `CalendarSettingsPage` row + `SettingsService` getter/setter + `SettingsKeys` + reset-to-defaults; count sliders bare, time with `s`.

## Grid and cells

- Row height only via `CalendarDayCell.rowHeightFor(stripHeight(…))`; never table_calendar's whole-cell decorations; a new marker style extends `CalendarDayBars` **and** `stripHeight`.
- The day number is one line (`FittedBox(scaleDown)`), never wrapped.
- Outside-month days fade **through colours** (`outsideAlpha`); one `Opacity` only on `isSelected || filledToday`.
- Marker contrast is a **ratio** (`_minContrastRatio` 1.6); `computeLuminance()` memoized (64).
- Tints go through `CellTintResolver` under the `DayBarProvider` purity contract: static probes only, one wash per day.
- The left edge is **one lane**: exactly one of cell and rail paints the runner-up; the rail base takes `baseShare` 0.5, never a slot; `dot` untouched.
- `strong` fasting reaches cells only via `cellStyleForUtcDay`, gated on `showFasting`.
- Every `TableCalendar` takes weekday labels from `CalendarDaysOfWeek`.

## Categories and icons

- Categories are data: `String` ids; icon `iconFor(event)`, tint `resolve(id).color`; unknown → `other`; built-ins undeletable; `deleteCategory` reassigns in a transaction.
- **Hiding is archiving**: a surface holding a selection renders `visiblePlus(keep)`; `is_hidden` ≠ `hiddenCategoryIds`.
- `CalendarIcons.groups` is the one source; **icon keys are additive**; letters and digits carry no `fontFamily`; every tile has a `Tooltip`.
- `category_search.dart` ranks every searchable category list; `isExactTerm` outranks every `FuzzyRank` tier.
- `CalendarCategoriesPage`: reorder and filtering mutually exclusive; menu writes in `_guarded`.
- `CategoryPickerSheet` is **the** choosing surface, never autofocused; `pickMulti` **never collapses empty** (callers own their inversion).
- `_pickCategories` re-reads the catalog **after** the picker; every visible row ticked empties the denylist (D22).
- A searchable surface keeps its field open while a query is live.

## Grid filters and presets

- One JSON blob (`SettingsKeys.calendarGridFilters`); event axes apply in `_visibleEvents`, day-dependent ones via `hasOccurrenceAxis`.
- Filters are render-time only: a filtered event still occurs, exports and counts. Layers gate `cellStyleForUtcDay`, zero `monthNetFor`.
- `_applyFilters` is the one dispatch-and-write funnel; `_onChangeCalendarFilters` records `_filters` **before** the loaded guard.
- `panelShowsAll` has no chip, survives `cleared()`. The agenda inherits **only** `hiddenCategoryIds`.

## Holidays and fasting

- **Built-in holidays are computed, never stored**: the table holds custom + suppressed rows; never a seeding pass or "years covered" window.
- Accuracy lives in the builders (`if (year >= NNNN)`, substitutes in `forYear`); observed dates via `publicHolidayObserved`, never a bare duplicate.
- Fasting **subtracts, never invents**; `forceDates` wins; `calendar_fasting_weekdays` is never written; the hint follows the **selected** scope.
- `CalendarBounds` (1900–2100) is the one navigable domain.

## Recurrence, dates, times

- Normalize days with `DateTime.utc(y, m, d)`; skips and presence take date-only UTC; `allDay` is derived; hot callers use `occursOnUtcDay`.
- **Never back-project the anchor** (`retroactive` = `_beforeStart`); `RecurrenceCodec` is the one encoding; `endDate` is enforced in `occursOn`.
- `RecurrenceFormatter.countLabel` is the one count entry point.
- Dates via `CalendarDatePickerSheet`, never `showDatePicker`; times via `TimePadSheet.pick`, never `showTimePicker`; formatters honour `alwaysUse24HourFormat`.
- Linked notes via `NoteRepository.getNotesByIds([id])`, never `getNoteById`.

## Presence, skips, occurrences

- **Skips are not presence**: a missed occurrence still occurs (never invalidate); the skip filter lives **only** in `CalendarEvent.occursOn` and invalidates the day cache.
- Gate on `rule is OneTimeRecurrence`, never `_RepeatMode`; skips never change counts; `markSkipped` clears the day's absence.
- `isMissed`: an explicit absence row wins both ways; no wall clock on reads; converting never rewrites marks; `CalendarMissedDisplay.hidden` spares the day panel.
- `OccurrenceDescriptions.descriptionFor` is the one entry; **a present row wins, `''` included**; never delete rows to clean up.
- One description controller: swap text via `loadText`, never `set text`; **never a `ListenableBuilder` on a re_editor controller**.
- Quick edit: emptying writes `''`, an unchanged Done nothing; `onCheckboxTap` null when read-only. Money is always off in descriptions.

## Panel, agenda, FAB

- `CalendarBottomPanel` owns panel-local state; scans live in `EventAgenda`, never `eventLoader` or the bloc; scrollables pad `AppSpacing.fabClearance`.
- The upcoming anchor is never persisted nor re-anchored on an `agendaRow` selection; `SelectCalendarDay` requires a source.
- `UpcomingAgendaFilters` parse forward-compatibly, save in one `setValues`; leave the agenda's three `now()` reads alone; never per-row `DateFormat(...)` / `DateTime.now()`.
- `perEvent` is a **post-filter**, never a scan short-circuit; `summary` never calls `occursOn`; retired bools stay read-time fallbacks.
- Agenda Events is **one menu over all four `AgendaEventType` values**, never a switch + sub-choice; disabled rows dim, never hide.
- **Every entry row is `_AgendaCard`; do not restyle without asking.** Search folds via `normalizeForSearch`.
- The agenda re-reads facades every rebuild. Rows stay fed by `EventSummaryProvider`; their `MarkdownInlineText` taps null.
- `EventDetailSheet` mirrors the editor's groups, order and glyphs.
- `CalendarEvent.withExplicitDates` is the one dates writer; `_occurrenceSurvives` reads `result.skippedDays` only.
- Priorities P1..P5 via `EventPriorities`, never a stepper; `EventAgenda.compareWithinDay` is the one same-day order.

## Overview, drill-down, years

- `AgendaMonthStore`: **resolve on navigation, never in build** (bar `tilesFor`); never re-add the twelve-months-back window; `ensure` chunks every run at twelve months (a longer run is split, never truncated).
- `CalendarOverviewPage` owns no data and ignores the grid filters. Its list's unit is an `OverviewPeriod` (this year · a rolling preset · a custom span), never a bare year; **the search query is a post-filter** through `EventQueryMatcher` over a query-free store, never a scan input; a period longer than `OverviewListMetrics.syncMonths` resolves in runs between frames under a generation token and stops at `maxEntries`; the rows have one geometry per kind (exact extents, `captionMaxLines: 1`, single-line headers) — never give a page row a height that depends on its text.
- A row tap from the overview **pushes** a calendar over it (`AppNavigator.occurrenceCalendarRouteName`, unstamped, never restored); only the last live calendar serves `pendingCalendarOccurrence`.
- `AgendaDayListRowBuilder` is the one renderer of dated entry rows, for the day list sheet and the overview alike; a row look change goes there, never into one surface.
- A gesture lane over a scrollable (`ListScrubber`) gives its recognizer `MediaQuery.maybeGestureSettingsOf(context)`: the `Scrollable` takes Android's 8 dp touch slop from the platform while a bare recognizer waits for `kTouchSlop` (18), so without it the list wins every real touch although widget tests pass.

## Event editor and sub-sheets

- `EventRepeatSheet` edits an `EventRepeatDraft`, never a rule; `_buildRule()` / `_initRecurrenceFrom` are the only encoder / decoder.
- On save keep `copyWith(clearIconKey: _iconKey == null)`. Priority is a `FormMenuRow`, never chips or a stepper.
- Dirty leave asks (`_fingerprint()`); `_leave()` serves ✕, back, `PopScope`, drag; Save bypasses it; sub-sheets unguarded.
- Autofocus the title on new events only; `_blur()` before every modal; `!mounted` after awaits.
- Preserve: `_canSave` = title non-empty ∧ (not weekly ∨ weekdays non-empty) ∧ both scopes within limit; interval clamped 1–99 for the four periodic rules only; weekday sets `Set.unmodifiable`; `_initRecurrenceFrom` sealed rehydration; the birthday built-in pre-fills yearly + counting on a still-one-time event.
- Templates: two entry points only; `buildEvent` clears repeat-only flags for one-time.
- Guards: `event_editor_redesign_test.dart, event_repeat_sheet_test.dart, event_look_sheet_test.dart`, six older editor suites, `sheet_bottom_clearance_test.dart`.

## The alert sheet and the quick alarm

- Sheet suites go through `AlertSheetRobot` / `QuickAlarmRobot`: a widget change edits the robot, never a test body.
- `AlertEditorSheet.show` serves both callers; Save returns `widget.alert.copyWith(…)`, passing through what is not on screen.
- Reminder tier: sound and remove-after at 38 %, never hidden. **Remove-after is the event's flag**: handed back as it came, `false` only when this sheet made an alarm a reminder.
- `EventAlert.describe` is the one formatter.
- **After Save, one message at most** (`_afterAlertsSaved`: permission, else `AlertCountdown`); `OverlaySnackbar` under a sheet.

## Alerts hub, navigation, export

- The Alerts hub owns no data, writes only via `CalendarBloc`; never poll or create alerts there. Only the Alarm tier reaches `packages/alarm/`.
- Only the alarm page shows above the keyguard; `MainActivity.ringObserver` leaves with **`moveTaskToBack` first, lowers the flags second**.
- While ringing, `_drainPendingNavigation` routes **only** `OpenAlarmIntent`s; an action into the app calls `unlock()` **before** stopping; never `showWhenLocked` / `turnScreenOn` in the manifest.
- `AlarmPage` **renders from the `AlertPayload` alone**, **its rows settled on the first frame**; no perpetual animation, no text field; back does nothing; it closes its own route, never the navigator's top.
- Notification words come only from `alertNotificationContent`; `AndroidAlertGateway` writes no text inline.
- Never format a time or date in the background isolate: `AlertLabels` writes them at arm time.
- A new fact is an optional `AlertPayload` field, its absence the old behaviour for good.
- Move `kAlertArmGrammarToken` when an armed entry's content changes; never edit `alertArmSignature` for it.
- Avatar files are named for all they draw; excerpts never split a surrogate pair.
- Quiet kinds post on `alerts_quiet`; reminders carry `kAlertGroupKey` on Android 16+, **never a summary**.
- A ring's end has a cause: `_settleEndedRing` has no default; clear both ring maps and hold `_stopping` before `Alarm.stop`.
- **Never arm over a ringing or due entry** (`_reconcile`); while any ring runs a past-due row stays in flight.
- A pass cancels a `fired` row's entry only if it settled it; a fire never takes a ringing or `fired` id.
- No scheduling pass calls `AppDatabase.getInstance()`. **Stop decides the removal at the press and may only narrow it**.
- After a Keep, take remove-after from the bloc's copy (`afterKeep`).
- `AppNavigator.toCalendar` is a normal push; options only on `CalendarSettingsPage`; no `AppLocalizations.byKey`.
- `CalendarViewMenu` is the one grid-format control; switch pages via `AppNavigator.switchTo…`, never a bare push.
- Each page exports via its own `CalendarExportController`; `.ics` via `IcsSerializer`, no `ics` `ExportFormat`.

## Change-set recipes

- **New persisted event field**: table + guarded migration → DAO → `CalendarEventService` mapping → model `copyWith` (+ `clearX`) → editor row → backup → `build_runner` → ARB ×3 + `gen-l10n` → upgrade-chain and parity tests.
- **New holiday profile**: `HolidayProfile` value → `profileNameOf` → `holidayProfile<Name>` ARB trio → `_<name>Seeds(year)` from `_buildSeeds`; new holidays: `PublicHoliday` value + `nameOf` + ARB trio. No schema change.
- **New grid filter axis**: `CalendarGridFilters` field + codec + `apply` (or `allowsOccurrence` + `hasOccurrenceAxis`) + `CalendarFilterSummary` facet + `_Trait` in `_traitsOf` or a row + chip label.
- **New sheet**: the `ui-language` chrome, the clearance test entry, its own widget suite.

## File map

- Pages: `calendar_page.dart, calendar_overview_page.dart, calendar_settings_page.dart, calendar_categories_page.dart, alerts_page.dart, alarm_page.dart`; `lib/bloc/calendar/calendar_bloc.dart`; `lib/controllers/`: `alert_ring_controller.dart, calendar_export_controller.dart`.
- Services: `calendar_event_service.dart, category_service.dart, public_holiday_service.dart, event_occurrence_service.dart, event_presence_service.dart, event_skip_service.dart, event_template_service.dart, event_alert_service.dart, filter_preset_service.dart, day_summary_resolver.dart, alert_scheduler.dart, alert_gateway.dart, android_alert_gateway.dart, alert_keep_notice.dart, session_chip.dart`.
- Models: `calendar_event.dart, recurrence_rule.dart, calendar_grid_filters.dart, calendar_appearance.dart, upcoming_agenda_filters.dart, calendar_panel_mode.dart, agenda_day_list.dart, alert_payload.dart`.
- Utils: `event_agenda.dart, agenda_month_store.dart, agenda_day_list_index.dart, calendar_filter_summary.dart, category_search.dart, date_stamp.dart, ics_serializer.dart, day_timeline_layout.dart, alert_offset.dart, quick_alarm.dart, alert_notification_content.dart, alert_labels.dart, alert_excerpt.dart`.
- Widgets: `calendar_bottom_panel.dart, upcoming_agenda_view.dart, agenda_list_view.dart, agenda_filters_sheet.dart, agenda_day_list_sheet.dart, agenda_day_list_rows.dart, agenda_period_nav.dart, agenda_month_grid.dart, agenda_year_grid.dart, agenda_year_pager.dart, calendar_add_fab.dart, calendar_header_menus.dart, calendar_day_cell.dart, calendar_day_bars.dart, calendar_day_rail.dart, day_summary_panel.dart, day_timeline_view.dart, event_detail_sheet.dart, event_editor_sheet.dart, event_repeat_sheet.dart, event_look_sheet.dart, event_description_sheet.dart, calendar_date_picker_sheet.dart, time_pad_sheet.dart, month_year_picker_sheet.dart, category_picker_sheet.dart, calendar_filter_sheet.dart, filter_check_list_sheet.dart, filter_preset_sheet.dart, alert_editor_sheet.dart, alert_offset_sheet.dart, alert_type_row.dart, alert_sound_sheet.dart, quick_alarm_sheet.dart, event_template_editor_sheet.dart, event_template_picker_sheet.dart, category_editor_sheet.dart, fasting_schedule_sheet.dart, fasting_style_sheet.dart, removed_holidays_sheet.dart, color_swatch_picker.dart, color_palette_sheet.dart, color_picker_sheet.dart, lock_screen_curtain.dart` (`alarm_metrics.dart, alarm_ground.dart`: `ui-language`).
- Constants: `calendar_bounds.dart, calendar_categories.dart, calendar_icons.dart, public_holidays.dart, fasting_calendar.dart, event_priorities.dart, event_presence.dart, event_skips.dart, occurrence_descriptions.dart, event_alerts.dart, alert_constants.dart, event_title.dart, category_name.dart, fasting_style_limits.dart`.
- QA: `tool/qa/fixtures/calendar.json, alerts.json, alerts_pair.json` (`test/qa/calendar_fixture_test.dart` pins the first); `tool/qa/flows/calendar/*.txt, alerts/, alerts_pair/`. Update a flow in the slice that changes its screen.

## References

| File | When to read it |
| --- | --- |
| `references/subsystems.md` (per heading: anatomy, contracts, whys, full rule lines) | Before changing a surface, or for a rule's why; one section |
| `references/schema-lineage.md` | A migration, a backup question, which version added a column |
| `references/context-log.md` (dated changelog since v14, ~200 KB) | To learn why; grep a version, date or class; one entry only |
| `references/colour-palette.md` | Before changing a colour default, its storage or a picker |
| `references/alarm-fork.md` (nine fork patches; rules: `.claude/rules/alarm-fork.md`) | Before touching `packages/alarm/`, or when an alarm acts unlike upstream |
