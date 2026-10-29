---
name: calendar-events
description: The rulebook and file map for ANTA's calendar, events and alerts - the invariants a calendar change must keep and where each piece lives, with on-demand references for each surface's anatomy, the schema lineage and the dated change log. USE FOR - any change to the calendar's pages, bloc, services, models or widgets; to how events are stored, recur, are filtered or drawn; to categories, public holidays or fasting; to presence, skipped days, per-occurrence descriptions or templates; to grid filters, saved filters, the agenda or the overview; to the event editor or any of its sub-sheets; to alerts - scheduling, notifications, the Alerts hub, the alarm page, the quick alarm. Load together with anta-context; add ui-language and calendar-ui for anything visual.
---

# Calendar & Events

## Hardest constraints

- **The nine calendar services are lazy** (`EventDigestService` since v42): `await X.getInstance()`, never `GetIt.I<>`; `CalendarBloc._onLoad` awaits all nine in one wrapped `Future.wait` and **only then emits `CalendarPageLoaded`**; other facade readers live under it or await the owner.
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
| The guide (2026-10-29): the hub, the topic pages, the "Try it" cards, the practice calendar, the sandbox seams | `docs/calendar-guide-page.md` §2 (D1–D12, the first build) and §7 (the hands-on rework: §7.1 D13–D37, §7.2 the slice specs with their as-built and review notes); its §3–§4 are the newcomer review and the proposals |
| Categories at scale | `docs/category-scaling-roadmap.md` |

Reworks follow `ui-revamp`. **Before changing a surface, read its section in `references/subsystems.md`**.

## Schema lineage (current v43)

Chain: `references/schema-lineage.md`. Rules for every version:

- Recurrence **interval rides in `rule_payload`** (written only when `> 1`, decoded clamped to 1); never an `interval` column.
- Additive columns: `PRAGMA table_info` guards, defaults an old row already meant, **no backfill**; backup stays v7 unless import semantics change.
- A **swapped index is dropped and recreated** (v27 / v37); `IF NOT EXISTS` alone strands upgraders.
- A new index goes in the creator whose tables exist when it runs (`createCalendarDeltaIndexes()` vs `createCalendarIndexes()`).
- `alert_registrations` is **device-local**: no CRDT, hard deletes, never exported or synced.
- Backup: an absent `eventOccurrences` / `eventSkips` / `eventAlerts` beside `calendarEvents` **clears** the table; `calendarFilterPresets` and `overviewViews` (v41, the same shape) have no strand rule; categories import **before** events.
- `categoryAlerts` is keyed to categories (the `eventTemplates` rule: absent beside `calendarCategories` **clears**); `eventDigests` follows `overviewViews` (absent → untouched); the event's `categoryAlerts` flag absent → on.

## Bloc, caches, revisions

- `_syncGenerations` heads **both** `eventsForDay` and `monthNetFor`; holiday revisions are a **generation** (drop the cache, never widen the key).
- `CalendarPageLoading` is **never emitted**; `_didInitialLoad` gates the first load only.
- Never inline the `monthNetFor` scan into `headerTitleBuilder`. `loadContentForNotes`: absent = unreadable, `''` = empty; never `?? ''`.
- Descriptions and presence bump `occurrenceRevision` (agenda never rescans), presence also `presenceRevision`; skips and reloads `membershipRevision`.
- A presence default flip bumps nothing: never value-compare `allEvents`. Handlers build fresh `allEvents` / `filters` (compared by identity).
- Callbacks read `context.read<CalendarBloc>().state` at press time.
- Only `importData()` / `reset()` / `notifyExternalChange()` bump `CalendarEventService.externalRevision`; the last also fires the static `externalChanges` stream, which `CalendarBloc` turns into `ExternalCalendarChange` (an in-place reload, no loading state). `BackupService.importFromJson` calls it once at the end of a restore, never mid-import. Sheets never fire the `RouteObserver`.

## Services and facades

- Only `PublicHolidayService` mutates `public_holidays`; only its `_load()` republishes `PublicHolidays`.
- `CategoryService` mutations share one chain whose tail starts **`null`**; `updateCategory` never writes `sort_order` / `is_built_in` / `is_hidden`; `setHidden` writes only the flag.
- `FilterPresetService` has no facade (await it), refuses past 50. The occurrence-descriptions `reset()` clears singleton and facade.
- `FastingCalendar.resetConfiguration()` belongs to `SettingsService.reset`, never a direct `DatabaseLifecycle` registration. Counts per category: `countByCategory()`.
- `EventAlertService` owns `calendar_category_alerts` too (`categoryAlertsFor`, `replaceForCategory`, `tombstoneForCategory`); **`EventAlerts.effectiveFor(event)` is the one read for what an event's alerts are** — own + the category's projected (`toEventAlert`, the in-memory `categoryId`), the category resolved as rendering does (unknown → `other`), an inherited alert dropped when it would fire at the same instant as an own one (the offset set the event's shape uses, `dayMinute` null read as the default); `hasAlarm` / `hasReminder` take the event; `inheritedFor(event, own:)` is the inherited tail; `replaceForEvent` never stores a projected alert (`categoryId != null`).
- `EventDigestService` is `OverviewViewService`'s twin (ten at most on `create`; `importData` uncapped — the planner is the bound), facade `EventDigests`; an unreadable payload or unknown cadence decodes **`enabled = false`**.
- `CategoryService.deleteCategory` tombstones the category's alerts in its own transaction and requests `reconcileAllQuietly` **unawaited after** its serialize chain, never inside it.

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
- Fasting **subtracts, never invents**, in one place — `FastingSchedule.keeps`; tradition builders never read the schedule; a month turned off is never marked (no month scope since 2026-10-26); `forceDates` wins; `calendar_fasting_weekdays` is never written; the weekday hint follows the **selected** scope.
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

- `AgendaMonthStore`: **resolve on navigation, never in build** (the overview's Year scroll reads its `AgendaYearTileSource` in build and resolves in post-frame runs, one year per frame; the day list's pager keeps the one `tilesFor` exception); never re-add the twelve-months-back window; `ensure` chunks every run at twelve months (a longer run is split, never truncated); `forget(month)` is the one way to re-resolve a month — a presence change re-resolves its month, never replaces the store (the list would shrink under the finger on a long period).
- `CalendarOverviewPage` owns no data and ignores the grid filters. Its list's unit is an `OverviewPeriod` (this year · a rolling preset · a custom span), never a bare year; **the search query is a post-filter** through `EventQueryMatcher` over a query-free store, never a scan input; a period longer than `OverviewListMetrics.syncMonths` resolves in runs between frames under a generation token and stops at `maxEntries`; the rows have one geometry per kind (exact extents, `captionMaxLines: 1`, single-line headers) — never give a page row a height that depends on its text.
- The overview's Year · Month · List switch is a chip row on the page (never in the title menu — the owner lost the tiles behind a menu on 2026-10-13); it folds with the keyboard inset over its own height, and since 2026-10-14 it ends with the search button that summons the Search row (the filter group is gone: Categories live in the options sheet, the period in the nav's title). The nav's title is the Period menu in every mode: a pick outside List mode switches to List on that period, This year in Year mode only jumps the years scroll to this year; the title never opens the jump picker on the overview.
- A row tap on the overview opens the event's detail sheet **in place** through `EventSheetsFlow` (`lib/controllers/event_sheets_flow.dart`): the one trip through an event's sheets — detail, editor, quick description, dates, skip, linked note, wiki link, the Keep-after-ring guard — owned by the calendar page and the overview alike, writing only through the app-wide `CalendarBloc`, one `SheetGuard` slot per page. Never push a calendar for a row. Every page that owns the flow serves `AlertKeepNotice` — count, and a reload while the notice is still pending, **never `take()`** outside the calendar page, so the flag stays for the calendar an Open event pushes and its `_predatesKeep` guard holds. While the trip holds the guard the overview parks bloc states and adopts them once at the end.
- `AppNavigator.toCalendarOccurrence` is the alert paths' (a notification tap, the alarm page, the hub): over an overview it **pushes** an unstamped calendar (`occurrenceCalendarRouteName`, never restored), otherwise it collapses; only the last live calendar serves `pendingCalendarOccurrence`.
- The overview's three modes draw one `AgendaPeriodNav` band under the chip row, its title box measured per mode since 2026-10-14 (Year one line, Month the twelve titles, List the span templates through `titleTemplates`): in List mode ◄ / ► step the period by its own length (`OverviewPeriod.stepped` — a stepped preset is a custom span; All time never steps) and the Today slot returns to the period as picked (`_home`); **a step never persists** and never moves `_home`. In Year mode (one continuous scroll of year sections since 2026-10-15) ◄ / ► and Today `animateToYear` within `_scrollYears`, the D28 span, while List, Month and the range picker keep the full `_years`; the title is the year whose header has passed half its height. The one-line totals slot under the nav (two lines before 2026-10-14) counts kept entries per category over what the mode lists (the missed ones under Missed only; Year mode from the tiles' marks) — text changes, geometry never.
- The years scroll (`AgendaYearScroll`, record §3.14): one section per year, a fixed extent, `initialScrollOffset` on today's year and no post-frame jump; the builder reads the `AgendaYearTileSource` only — never `ensureTallies` in build — and `_scheduleYearRun` resolves one year per frame in a post-frame callback (the top year, the visible years, the two neighbours; never a year scrolled past; nothing while `isLanding` or `_covered`); the opening year and a landing's target resolve synchronously before their frame; a keyboard frame rebuilds no tile (no height read in the sections' `LayoutBuilder`, one delegate instance); a query change keeps the near years' tiles until the same `setState` refolds them and drops the rest; `YearMonthTile.columnsFor` is the grid delegate's rule — never a second column formula; `AgendaYearPager` stays the day list's.
- Presence from the overview's rows is the day panel's button in the row's trailing slot (D31, 2026-10-17 — the Mark presence switch and the tap-to-mark mode are retired; the owner found the switch dead where the page lands): `AgendaDayListRowBuilder.onEntryPresence` draws it on every `presenceTracked` entry (set at `AgendaListView.eventDayEntries` from `EventPresence.appliesTo`) where the page offers it — Month mode's rows and the list's every-occurrence rows (`_dayRowsShown`), and under the hidden missed display only on the picked day's rows (D32, 2026-10-17: a mark on a whole-month row would remove it with no way back); a press writes `EventSheetsFlow.setOccurrencePresence` (explicit statuses, never a clear), a row tap always opens the sheet, the pencil outranks the button in the slot (the day list sheet); a mark re-resolves its month alone (`_pendingMarks`, `AgendaMonthStore.forget`). Never a mode that changes what a row tap does.
- **The picked day in Month mode is the day panel's twin** (D32, record §2.8 / §3.16): its rows come from a one-day scan converted with `faded` (`_pickedDayEntries`: `_scan(day, day)` → `AgendaListView.eventDayEntries(missedDisplay: faded)` → `_matches` under a query → `_listed`), never from the month's bucket, so under `hidden` a missed or assumed-absent occurrence is listed faded with its button; `_occurrenceMask` (folded in `_resolve` from the scan before conversion, cleared with `_markedKept`) makes every day with any occurrence a day to pick (`_hasOccurrence` → the grid's `hasEntry`, `_toggleSelectedDay`; `_hasEntry` alone under a live query); the whole-month rows, the bars, the counts, Year and List keep the `hidden` drop. `AgendaMonthGrid.hasEntry` means "a day to pick" — enabled and full-strength, bars or not.
- **The overview speaks the language whole** (D33, record §2.9 / §3.17, 2026-10-17): its bar is `AppBarMetrics` on `pageGround` with no tint (the calendar page's bar the same height); `AgendaPeriodNav`'s title is 17 / 500 and its count the caption role on `FormMetrics.captionLineHeight`, with an Android hint; the Period menu is `showFormMenu(alignment: FormMenuAlignment.center)`; year tiles take the host's `rowGroup` through `tileBackground`; the views and saved-filters sheets' ✕ says `close`, their hairline is `FormHeaderHairline`, their name dialog `AppDialogs.textInput` with `kSavedListNameMaxLength`; the options sheet disables Missed only in Year mode and clamps Categories at two lines under `FormSheetSemanticsRefresh`; the search button is a 48 dp target; every nav, tile and mini-grid number is named (`FormMetrics.periodNav*` / `miniGrid*`, `OverviewListMetrics.yearTile*`). Snackbars app-wide are decision 9 of the master record: the theme's `snackBarTheme` on `menuSurface`, never `inverseSurface`. What §2.9 leaves for the owner stays as it is until they decide.
- Saved views are the saved filters' twin: `overview_views` (v41, the v29 CRDT block, soft deletes), `OverviewViewService` (50 at most, `matching`, lifecycle reset), `OverviewViewSheet` behind the bar's `overview-views-open`; a view holds the period (a custom span allowed; This year stays rolling through the `thisYear` kind, a paged year pins its number), Order, Rows, Missed only and the allowlist — never the query or the mode — and applying one switches to List and persists each part as a pick would. Change the presets and the views together.
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
- `AlertEditorSheet.show(forCategory: true)` shows **two** When rows (`alertsDefaultTimed`, `alertsDefaultAllDay` — both sets are on screen and both reach Save) and never remove-after; the two existing callers see what they saw. The category editor's alert rows are two-line (the all-day wording over "Timed events: … · tier") with a trailing **enabled switch** (the category's master switch); removal is the sheet's Remove; a new category alert drafts without the settings defaults (D7) and takes a fresh id — `replaceForCategory` refuses an id another category owns.
- The event editor lists **enabled** inherited alerts read-only ("From {category}"), re-read on a category pick; Add alert counts own rows only; remove-after reads own alarms only; the Category alerts switch is **last** in the group and **dims** the inherited rows at 38 % where they stand — they never leave.

## Alerts hub, navigation, export

- The Alerts hub owns no data, writes only via `CalendarBloc`; never poll; never an *event-alert*-creation affordance there — Add digest is the one creation the hub holds, because a digest has no other owner. Only the Alarm tier reaches `packages/alarm/`.
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
- The ⋮ of the calendar and the overview is one `CalendarOverflowMenu`: Alerts · Export · divider · the guide (`CalendarGuidePage`, `AppNavigator.toCalendarGuide`, a stamped `NavDestinationKind.calendarGuide`, no reload on return) · Calendar settings **last**. The guide quotes labels through ARB placeholders (`“{save}”` ← `l10n.save`), never retyped; a new row is a slug + icon + the three languages in one change (`docs/calendar-guide-page.md` D1–D12).
- **The guide is a hub** (since 2026-10-29): `CalendarGuidePage` lists the Practice calendar and nine topic pages (`CalendarGuideTopicPage(topic)` over the catalogue `lib/models/calendar_guide_content.dart` — a plain `AppNavigator.push`, never stamped, a relaunch lands on the hub); its search keeps only the rows `matchSettingsEntry` matches, one kit section per page. Every task page opens with one **"Try it" card** (`calendar_guide_try_card.dart` + one `calendar_guide_try_<topic>.dart` per page): a stage of the **real** widgets under `sandbox: true`, a `FormCaptionSlot` live caption whose candidates are every string the card can show, the demo state owned by the page's `State` (the kit's list disposes a card scrolled away), nothing animated. `CalendarGuidePracticePage` is a calendar over a page-owned `GuideDemoCalendar` (`lib/models/calendar_guide_demo.dart`: six seed events, its own presence map, skips and per-day descriptions, a per-day map rebuilt only on changes). **Nothing a demo does may write**: the sandbox seams (`EventEditorSheet.show(sandbox:)`, `CategoryPickerSheet`, `EventLookSheet` / `ColorSwatchPicker`, `CalendarFilterSheet.show`, `CategoryEditorSheet.show`, `IconPickerSheet`, `AlarmPage.preview` — pushed on its own page route) drop every writing affordance, and a shared widget that read a static cache by event id took a **read seam** whose default is today's static read (`isMissed` on `DayBarsResolver.defaults`, `DayTimelineView`, `EventDetailSheet.show`, `PresenceAdherence.compute`; `EventEditorSheet.show(initialSkippedDays:, initialAlerts:)`; `CalendarViewMenu(namesRoute:)`; `PanelModeBar.onToggleExpanded` nullable = disabled) — a demo feeds its facts through those, never through `EventPresence.updateCache`, `EventSkips`, `OccurrenceDescriptions` or `CalendarCategories.updateCache`. A new write path in any of those widgets gets a sandbox gate and a no-write test in the same change; the guide suites run every case over a statement interceptor (`test/widgets/support/sandbox_write_log.dart`). Numbers in `GuideMetrics` (`lib/constants/guide_metrics.dart`).
- `CalendarViewMenu` is the one grid-format control; switch pages via `AppNavigator.switchTo…`, never a bare push.
- Each page exports via its own `CalendarExportController`; `.ics` via `IcsSerializer`, no `ics` `ExportFormat`.
- The hub's Digests group (on the UI language; the day rows stay Tier 4) lists `EventDigests.all` with a switch each (`ToggleEventDigest`), tap → `DigestEditorSheet` (`SaveEventDigest` / `DeleteEventDigest`), Add digest under `kDigestHorizon.maxDigests`; the fires of enabled digests sit among the day groups from `AlertScheduler.digestEntries()` (planned fresh, no switch of their own), deliveries under Recent (`AlertHistoryEntry.digest`). An inherited row's switch is **the event's `categoryAlerts` flag** (`UpdateCalendarEvent` with the flag alone, the event read from the bloc state at press time); `hubEntries()` imagines an opted-out event's inherited rows and skips paused category alerts, so the hub is never a one-way switch. Row keys carry the event id (twins share an alert id).
- **Registry identity is `(alert_id, event_id, day, kind)`** with `source` (`event | category | digest`); seeds: event-sourced unchanged, category-sourced with the event, a digest `"$db|$digestId|$spanStartIso|digest"`. A category-sourced payload carries `inherited` (`inh`): the background Snooze re-post seeds with the event and `cancelSnoozeForAlert(alertId, eventId, day)` matches it. Every snooze a v41 build armed survives a pass.
- **Digests**: `DigestPlanner` is pure (`now` injected; the wall-clock constructor; the span = fire day + lead, one unit; `occurrencesInRange` with the allowlist alone — never `hiddenCategoryIds`; every occurrence a line; an empty span unarmed unless `includeEmpty`; clamps what it reads); every word is written at arm time on the UI isolate by `digestNotificationContent` through `AlertLabels` (the period phrase from the app's `CalendarWeekStart` and `spanStart.day == 1`, never the locale); `AlertNotificationKind.digest` places strings; the channel is `alerts_digest` at **default** importance; `scheduleDigest` is abstract (the no-op answers true); a digest row past its instant is **`fired` in every band** — never cancelled, never an OS cancel, never missed, never a notice or a snooze; the signature hashes words, tint, glyph, allowlist and span.
- **A digest's tap** is `OpenOverviewIntent` → `AppNavigator.toCalendarOverviewLook` → `pendingOverviewLook` (the `pendingCalendarOccurrence` twin): the overview serves it once settings have loaded (a look wins), clears the query and Missed only, lands in List mode on the custom span with the allowlist, persists mode and allowlist and **never the period** (`encode` would delete the key), keeps Order and Rows; `_listLook` is shared with `_applyView`, which still persists a view's period. While a ring is in progress the intent waits.
- `AlertPermissionCheck.afterSave(context)` is the one permission check after a save (the flow, the category editor, the digest sheet); the flow checks effective alerts, so an event whose only alerts are inherited still asks and still shows the countdown.

## Change-set recipes

- **New persisted event field**: table + guarded migration → DAO → `CalendarEventService` mapping → model `copyWith` (+ `clearX`) → editor row → backup → `build_runner` → ARB ×3 + `gen-l10n` → upgrade-chain and parity tests.
- **New holiday profile**: `HolidayProfile` value → `profileNameOf` → `holidayProfile<Name>` ARB trio → `_<name>Seeds(year)` from `_buildSeeds`; new holidays: `PublicHoliday` value + `nameOf` + ARB trio. No schema change.
- **New grid filter axis**: `CalendarGridFilters` field + codec + `apply` (or `allowsOccurrence` + `hasOccurrenceAxis`) + `CalendarFilterSummary` facet + `_Trait` in `_traitsOf` or a row + chip label.
- **New sheet**: the `ui-language` chrome, the clearance test entry, its own widget suite.
- **New alert offset semantics**: land it in `EventAlert` **and** `CategoryAlert` (both store both offset sets), in `effectiveFor`'s dedupe key, in `describe`, in the alert sheet's two When rows, and in the fixture.

## File map

- Pages: `calendar_page.dart, calendar_overview_page.dart, calendar_settings_page.dart, calendar_categories_page.dart, calendar_guide_page.dart, calendar_guide_topic_page.dart, calendar_guide_practice_page.dart, alerts_page.dart, alarm_page.dart`; the guide's `lib/models/calendar_guide_content.dart`, `calendar_guide_demo.dart`, `lib/widgets/calendar_guide_rows.dart`, `calendar_guide_try_card.dart`, `calendar_guide_try_{screen,events,kinds,alerts,attendance,categories,finding,setup}.dart`, `lib/constants/guide_metrics.dart`; `lib/bloc/calendar/calendar_bloc.dart`; `lib/controllers/`: `alert_ring_controller.dart, calendar_export_controller.dart, event_sheets_flow.dart, alert_permission_check.dart`.
- Services: `event_digest_service.dart, calendar_event_service.dart, category_service.dart, public_holiday_service.dart, event_occurrence_service.dart, event_presence_service.dart, event_skip_service.dart, event_template_service.dart, overview_view_service.dart, event_alert_service.dart, filter_preset_service.dart, day_summary_resolver.dart, alert_scheduler.dart, alert_gateway.dart, android_alert_gateway.dart, alert_keep_notice.dart, session_chip.dart`.
- Models: `calendar_event.dart, recurrence_rule.dart, calendar_grid_filters.dart, calendar_appearance.dart, upcoming_agenda_filters.dart, calendar_panel_mode.dart, agenda_day_list.dart, overview_period.dart, overview_list_options.dart, overview_view.dart, alert_payload.dart, category_alert.dart, event_digest.dart`.
- Utils: `event_agenda.dart, agenda_month_store.dart, agenda_day_list_index.dart, calendar_filter_summary.dart, category_search.dart, date_stamp.dart, ics_serializer.dart, day_timeline_layout.dart, alert_offset.dart, quick_alarm.dart, alert_notification_content.dart, alert_labels.dart, alert_excerpt.dart, sheet_guard.dart, digest_planner.dart, digest_notification_content.dart, digest_labels.dart`.
- Widgets: `calendar_bottom_panel.dart, upcoming_agenda_view.dart, agenda_list_view.dart, agenda_filters_sheet.dart, agenda_day_list_sheet.dart, agenda_day_list_rows.dart, agenda_period_nav.dart, overview_options_sheet.dart, overview_view_sheet.dart, agenda_month_grid.dart, agenda_year_grid.dart, agenda_year_pager.dart, calendar_add_fab.dart, calendar_header_menus.dart, calendar_day_cell.dart, calendar_day_bars.dart, calendar_day_rail.dart, day_summary_panel.dart, day_timeline_view.dart, event_detail_sheet.dart, event_editor_sheet.dart, event_repeat_sheet.dart, event_look_sheet.dart, event_description_sheet.dart, calendar_date_picker_sheet.dart, time_pad_sheet.dart, month_year_picker_sheet.dart, category_picker_sheet.dart, calendar_filter_sheet.dart, filter_check_list_sheet.dart, filter_preset_sheet.dart, alert_editor_sheet.dart, alert_offset_sheet.dart, alert_type_row.dart, alert_sound_sheet.dart, quick_alarm_sheet.dart, event_template_editor_sheet.dart, event_template_picker_sheet.dart, category_editor_sheet.dart, fasting_schedule_sheet.dart, fasting_style_sheet.dart, removed_holidays_sheet.dart, color_swatch_picker.dart, color_palette_sheet.dart, color_picker_sheet.dart, lock_screen_curtain.dart, digest_editor_sheet.dart` (`alarm_metrics.dart, alarm_ground.dart`: `ui-language`).
- Constants: `calendar_bounds.dart, calendar_categories.dart, calendar_icons.dart, public_holidays.dart, fasting_calendar.dart, event_priorities.dart, event_presence.dart, event_skips.dart, occurrence_descriptions.dart, event_alerts.dart, alert_constants.dart, event_title.dart, category_name.dart, fasting_style_limits.dart, event_digests.dart`.
- DAOs: `category_alert_dao.dart, event_digest_dao.dart`.
- QA: `tool/qa/fixtures/calendar.json, alerts.json, alerts_pair.json` (`test/qa/calendar_fixture_test.dart` pins the first); `tool/qa/flows/calendar/*.txt, alerts/, alerts_pair/`; the alerts fixture's category alert and digest, flows `alerts/03_category_alerts.txt`, `alerts/04_digests.txt` (names as S5 lands them). Robots: `category_editor_robot.dart`, `digest_sheet_robot.dart`. Update a flow in the slice that changes its screen.

## References

| File | When to read it |
| --- | --- |
| `references/subsystems.md` (per heading: anatomy, contracts, whys, full rule lines) | Before changing a surface, or for a rule's why; one section |
| `references/schema-lineage.md` | A migration, a backup question, which version added a column |
| `references/context-log.md` (dated changelog since v14, ~200 KB) | To learn why; grep a version, date or class; one entry only |
| `references/colour-palette.md` | Before changing a colour default, its storage or a picker |
| `references/alarm-fork.md` (nine fork patches; rules: `.claude/rules/alarm-fork.md`) | Before touching `packages/alarm/`, or when an alarm acts unlike upstream |
