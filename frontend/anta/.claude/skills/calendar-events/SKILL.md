---
name: calendar-events
description: The rulebook and file map for ANTA's calendar, events and alerts - the invariants a calendar change must keep and where each piece lives, with on-demand references for each surface's anatomy, the schema lineage and the dated change log. USE FOR - any change to the calendar's pages, bloc, services, models or widgets; to how events are stored, recur, are filtered or drawn; to categories, public holidays or fasting; to presence, skipped days, per-occurrence descriptions or templates; to grid filters, saved filters, the agenda or the overview; to the event editor or any of its sub-sheets; to alerts - scheduling, notifications, the Alerts hub, the alarm page, the quick alarm. Load together with anta-context; add ui-language and calendar-ui for anything visual.
---

# Calendar & Events

## Hardest constraints

- **The ten calendar services are lazy** (`EventDigestService` since v42, `CategoryProfileService` since v44): `await X.getInstance()`, never `GetIt.I<>`; `CalendarBloc._onLoad` awaits all ten in one wrapped `Future.wait` and **only then emits `CalendarPageLoaded`**; other facade readers live under it or await the owner. A `getInstance()` never hands out a half-built instance or one from a dead generation (`_creating`, S14).
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
| The Report page (periods, tiles, groups, the chart, the share) and report digests | 2026-10-31 addendum (+ `docs/calendar-report-roadmap.md`: D1–D44, §4.8 the designer's spec, §7.1 the as-built notes per slice) |
| The analytics layer — kinds and profiles, one mark for every shape, measures, goals, insights, By tag, When, Balance, Compare with, the year in review, the report cards setting, the digest's judgment lines | 2026-11-05 addendum (+ `docs/calendar-analytics-roadmap.md`: A–CC, §6 the model, §12.2 per slice; the designer's specs in `docs/calendar-analytics-specs/`) |
| The header: view menu, ⋮, switching pages | 2026-09-26 header addendum (+ `docs/calendar-header-roadmap.md`) |
| Fasting schedule | §4.5 is the behaviour of record; `docs/fasting-schedule-roadmap.md` the design record |
| The guide (2026-10-29): the hub, the topic pages, the "Try it" cards, the practice calendar, the sandbox seams | `docs/calendar-guide-page.md` §2 (D1–D12, the first build) and §7 (the hands-on rework: §7.1 D13–D37, §7.2 the slice specs with their as-built and review notes); its §3–§4 are the newcomer review and the proposals |
| Categories at scale | `docs/category-scaling-roadmap.md` |

Reworks follow `ui-revamp`. **Before changing a surface, read its section in `references/subsystems.md`**.

## Schema lineage (calendar tables; the database is at `DatabaseSchema.currentVersion`)

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
- Range scans, the filtered memo's out-of-window days and every `allEventsForDay` miss (inside the window too) narrow through `EventWindowIndex` (recurring + the touched months' one-time events, list order; it never decides occurrence); the day memos evict only the oldest day outside the window past `CalendarCacheLimits.maxDayCacheEntries`. Never mutate an event list after handing it out: the index is memoised per list instance.
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
- The fold set is one key shared by Calendar settings, Appearance, Alert settings and Fasting: a toggle goes through `SettingsService.setCalendarSettingsSectionCollapsed(id, collapsed:)` (read, edit, write on one chained future; the page adopts the written set), never a page's in-memory copy written back — that dropped a child page's folds in the reload window (2026-11-01).
- `CalendarAppearance` and the palette are **passed down from `CalendarPage`**, never re-read in a leaf. Weekday labels from `intl`, never an ARB matrix.
- New setting: a `SettingsEntry` on the page that owns the subject — `CalendarSettingsPage` (Holidays · More settings · Filtering · Events), `AlertSettingsPage`, `FastingSettingsPage` or `CalendarAppearancePage` (the only one with a reset since S5, 2026-11-01) — + `SettingsService` getter/setter + `SettingsKeys`; count sliders bare, time with the unit through an ARB key, never `'${v}s'`.

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
- **One mark for every shape** (analytics S1, 2026-11-04): `EventPresence.appliesTo` is `tracksPresence` alone and `EventSkips.appliesTo` is `true` — a tracked one-off carries kept / missed marks, joins the day rail and can be cancelled (its skip on its start day); only `OccurrenceDescriptions.appliesTo` still gates on `rule is OneTimeRecurrence`, never `_RepeatMode`. `shapeOf` and `PresenceAdherence.compute` keep `rule is! OneTimeRecurrence` inline: a tracked one-off is a dated row with no adherence. The editor offers the switch to a one-off only when its category's kind marks or the event is already tracked (`CategoryProfiles.effectiveFor`), pre-set from the kind for a new event; the mark's verb is `markVerbLabel` / `markAsVerbLabel` (`lib/utils/mark_verb_labels.dart`, "Present" unprofiled); a one-off's cancel is the detail sheet's `eventDetailCancel`, in place, with Restore. A save that makes a rule one-time or moves a one-off's start day clears its skips (`CalendarEvent.strandsSkipsOf`, both write paths); v45 swept the rows older builds left. Skips never change counts; `markSkipped` clears the day's absence.
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

## Report (2026-10-31)

- The page's anatomy (the view-menu entry, its bloc, its navigation), the cards one by one and the report digests: `references/surface-rules.md` § Report — read it before changing `CalendarReportPage`, `CalendarReportBloc`, a `report_*` widget or a report digest.
- Periods: `OverviewWeekPeriod` / `OverviewMonthPeriod` beside the year (D25) — `thisWeek` / `thisMonth` encode only while they hold today, a stepped week or month is the true neighbour, a saved view re-resolves through `OverviewView.periodOn`; the report's relative menu rows (Last / Next week / month) persist their base preset; no All time; a custom span over 366 days keeps its *last* 366 days (D33). Stored: `SettingsKeys.reportPeriod` / `reportCategoryIds` (`getCalendarReportSettings`, one statement with the appearance, the palette and haptics), default This month and every category.
- Counting (D26–D32): Events = what happened and missed is never inside it (group headers sum to the tile); today's unmarked tracked occurrence is **pending** — out of every tile, under Ahead; tasks per the text the user sees; deltas like with like; the allowlist matches the **stored** category id as the overview and the planner do, grouping resolves; a wholly future period is a plan (Planned · Hours · Tasks, Categories only).

## Analytics (2026-11-04 → 05)

- `docs/calendar-analytics-roadmap.md` is the record (decisions A–CC, the model in §6, §12.2 per slice); `references/subsystems.md` "The analytics layer" holds the anatomy and the rules in full. The report record's §8 pins still hold, amended once: an unprofiled calendar's share gains By tag when a title carries a `#` word.
- **A category's profile is the category's** (`calendar_category_profiles`, v44, synced, backup v8; `CategoryProfiles.revision` joins the fold memo's key), never a setting; `CategoryProfile.effective()` fills every unset field from the kind, so a category with no explicit choice still folds. Settings hold the card list and nothing else (`SettingsKeys.reportCards`, `ReportCards` — an off card is absent, never collapsed).
- **One mark for every shape**: a one-off under a marking kind is tracked and assumes absent; the gates stay `EventPresence.appliesTo` and `CalendarEvent.withExplicitDates`; the verb is the kind's `MarkVerb`.
- **The builder is one pure pass** that also folds the compared span (`ReportCompare`, a memo entry like any other; a compared fold emits only what Compare reads; the benchmark bound is 1.75× the cold service) and the whole-year aggregates (`ReportYear`, only on an exact calendar year that is no plan); thresholds and caps live in `AnalyticsMetrics`, geometry and templates in `ReportMetrics`.
- **Rows never change height with their value**: `captionLines` come from templates measured at the caption width, bold-aware, through the one shared helper (`reportCaptionLines` / `ReportTagCaptions`); where a figure's width cannot be templated, the digit count or the real subject is measured and the slice's note says so.
- **Cards are absent without content, never collapsed**; every section label is a refold anchor (the nearest above the viewport corrects; a leaving label hands over to the first surviving label after it); the page arms the end slack when the cards above the anchors change shape.
- **One filter, one set of words**: `ReportInsightFilter.forPage` and `ReportLabels` are read by the page, the share (`ReportMarkdown`) and the digest; nothing is retyped. The guide is untouched (V).

## Overview, drill-down, years

- The mode chips, the in-place detail sheet (`EventSheetsFlow`), the period band, the years scroll, presence from a row, the picked day in Month mode and the page's look (D31–D33): `references/surface-rules.md` § Overview — read it before changing `CalendarOverviewPage`, `AgendaYearScroll` or the band above them.
- `AgendaMonthStore`: **resolve on navigation, never in build** (the overview's Year scroll reads its `AgendaYearTileSource` in build and resolves in post-frame runs, one year per frame; the day list's pager keeps the one `tilesFor` exception); never re-add the twelve-months-back window; `ensure` chunks every run at twelve months (a longer run is split, never truncated); `forget(month)` is the one way to re-resolve a month — a presence change re-resolves its month, never replaces the store (the list would shrink under the finger on a long period).
- `CalendarOverviewPage` owns no data and ignores the grid filters. Its list's unit is an `OverviewPeriod` (this year · a rolling preset · a custom span), never a bare year; **the search query is a post-filter** through `EventQueryMatcher` over a query-free store, never a scan input; a period longer than `OverviewListMetrics.syncMonths` resolves in runs between frames under a generation token and stops at `maxEntries`; the rows have one geometry per kind (exact extents, `captionMaxLines: 1`, single-line headers) — never give a page row a height that depends on its text.
- **Back on the overview is a ladder of three** (D34, 2026-11-01): the open Search row closes first, then a month opened from a year tile returns to Year (`_cameFromYear`, the day list sheet's flag — set only by the tile tap, cleared by every persisted mode change), then the route pops; one `PopScope` around the `Scaffold`, always present, never one per mode; mode switches never stack back steps.
- `AppNavigator.toCalendarOccurrence` is the alert paths' (a notification tap, the alarm page, the hub): over an overview it **pushes** an unstamped calendar (`occurrenceCalendarRouteName`, never restored), otherwise it collapses; only the last live calendar serves `pendingCalendarOccurrence`.
- Saved views are the saved filters' twin: `overview_views` (v41, the v29 CRDT block, soft deletes), `OverviewViewService` (50 at most, `matching`, lifecycle reset), `OverviewViewSheet` behind the bar's `overview-views-open`; a view holds the period (a custom span allowed; This year stays rolling through the `thisYear` kind, a paged year pins its number), Order, Rows, Missed only and the allowlist — never the query or the mode — and applying one switches to List and persists each part as a pick would. Change the presets and the views together.
- `AgendaDayListRowBuilder` is the one renderer of dated entry rows, for the day list sheet and the overview alike; a row look change goes there, never into one surface.
- A gesture lane over a scrollable (`ListScrubber`) gives its recognizer `MediaQuery.maybeGestureSettingsOf(context)`: the `Scrollable` takes Android's 8 dp touch slop from the platform while a bare recognizer waits for `kTouchSlop` (18), so without it the list wins every real touch although widget tests pass.

## Event editor and sub-sheets

- `EventRepeatSheet` edits an `EventRepeatDraft`, never a rule; `_buildRule()` / `_initRecurrenceFrom` are the only encoder / decoder.
- On save keep `copyWith(clearIconKey: _iconKey == null)`. Priority is a `FormMenuRow`, never chips or a stepper.
- Dirty leave asks (`_fingerprint()`); `_leave()` serves ✕, back, `PopScope`, drag; Save bypasses it; sub-sheets unguarded.
- Autofocus the title on new events only; `_blur()` before every modal; `!mounted` after awaits.
- Preserve: `_canSave` = title non-empty ∧ (not weekly ∨ weekdays non-empty) ∧ both scopes within limit; interval clamped 1–99 for the four periodic rules only; weekday sets `Set.unmodifiable`; `_initRecurrenceFrom` sealed rehydration; the birthday built-in pre-fills yearly + counting on a still-one-time event.
- Templates: two entry points only; `buildEvent` clears repeat-only flags for one-time (presence kept since analytics S1).
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

- The ⋮ menu (`CalendarOverflowMenu`), the guide (the hub, the topic pages, the "Try it" cards, the practice calendar), the hub's Digests group and the digest rules (`DigestPlanner`): `references/surface-rules.md` § Alerts hub, navigation, export — read it before changing the overflow menu, a guide page or a digest.
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
- The `_nothingCanArm()` fast path serves `launch` and `resumed` only; a registry hard delete that removed rows writes `alert_strays_pending` in its own transaction.
- After a Keep, take remove-after from the bloc's copy (`afterKeep`).
- `AppNavigator.toCalendar` is a normal push; options only on `CalendarSettingsPage`; no `AppLocalizations.byKey`.
- `CalendarViewMenu` is the one grid-format control; switch pages via `AppNavigator.switchTo…`, never a bare push.
- Each page exports via its own `CalendarExportController`; `.ics` via `IcsSerializer`, no `ics` `ExportFormat`.
- **Registry identity is `(alert_id, event_id, day, kind)`** with `source` (`event | category | digest`); seeds: event-sourced unchanged, category-sourced with the event, a digest `"$db|$digestId|$spanStartIso|digest"`. A category-sourced payload carries `inherited` (`inh`): the background Snooze re-post seeds with the event and `cancelSnoozeForAlert(alertId, eventId, day)` matches it. Every snooze a v41 build armed survives a pass.
- **A digest's tap** is `OpenOverviewIntent` → `AppNavigator.toCalendarOverviewLook` → `pendingOverviewLook` (the `pendingCalendarOccurrence` twin): the overview serves it once settings have loaded (a look wins), clears the query and Missed only, lands in List mode on the custom span with the allowlist, persists mode and allowlist and **never the period** (`encode` would delete the key), keeps Order and Rows; `_listLook` is shared with `_applyView`, which still persists a view's period. While a ring is in progress the intent waits.
- `AlertPermissionCheck.afterSave(context)` is the one permission check after a save (the flow, the category editor, the digest sheet); the flow checks effective alerts, so an event whose only alerts are inherited still asks and still shows the countdown.

## Change-set recipes

- **New persisted event field**: table + guarded migration → DAO → `CalendarEventService` mapping → model `copyWith` (+ `clearX`) → editor row → backup → `build_runner` → ARB ×3 + `gen-l10n` → upgrade-chain and parity tests.
- **New holiday profile**: `HolidayProfile` value → `profileNameOf` → `holidayProfile<Name>` ARB trio → `_<name>Seeds(year)` from `_buildSeeds`; new holidays: `PublicHoliday` value + `nameOf` + ARB trio. No schema change.
- **New grid filter axis**: `CalendarGridFilters` field + codec + `apply` (or `allowsOccurrence` + `hasOccurrenceAxis`) + `CalendarFilterSummary` facet + `_Trait` in `_traitsOf` or a row + chip label.
- **New sheet**: the `ui-language` chrome, the clearance test entry, its own widget suite.
- **New alert offset semantics**: land it in `EventAlert` **and** `CategoryAlert` (both store both offset sets), in `effectiveFor`'s dedupe key, in `describe`, in the alert sheet's two When rows, and in the fixture.

## File map

- Pages: `calendar_page.dart, calendar_overview_page.dart, calendar_report_page.dart, calendar_settings_page.dart, alert_settings_page.dart, fasting_settings_page.dart, calendar_categories_page.dart, calendar_guide_page.dart, calendar_guide_topic_page.dart, calendar_guide_practice_page.dart, alerts_page.dart, alarm_page.dart`; the guide's `lib/models/calendar_guide_content.dart`, `calendar_guide_demo.dart`, `lib/widgets/calendar_guide_rows.dart`, `calendar_guide_try_card.dart`, `calendar_guide_try_{screen,events,kinds,alerts,attendance,categories,finding,setup}.dart`, `lib/constants/guide_metrics.dart`; `lib/bloc/calendar/calendar_bloc.dart`; `lib/controllers/`: `alert_ring_controller.dart, calendar_export_controller.dart, event_sheets_flow.dart, alert_permission_check.dart`.
- Services: `event_digest_service.dart, calendar_event_service.dart, category_service.dart, public_holiday_service.dart, event_occurrence_service.dart, event_presence_service.dart, event_skip_service.dart, event_template_service.dart, overview_view_service.dart, calendar_report_service.dart, event_alert_service.dart, filter_preset_service.dart, day_summary_resolver.dart, alert_scheduler.dart, alert_gateway.dart, android_alert_gateway.dart, alert_keep_notice.dart, session_chip.dart`.
- Models: `calendar_event.dart, recurrence_rule.dart, calendar_grid_filters.dart, calendar_appearance.dart, upcoming_agenda_filters.dart, calendar_panel_mode.dart, agenda_day_list.dart, overview_period.dart, overview_list_options.dart, overview_view.dart, calendar_report.dart, report_look.dart, report_period_choice.dart, alert_payload.dart, category_alert.dart, event_digest.dart`.
- Utils: `event_agenda.dart, agenda_month_store.dart, agenda_day_list_index.dart, calendar_report_builder.dart, report_labels.dart, report_markdown.dart, task_count.dart, within_day_order.dart, calendar_filter_summary.dart, category_search.dart, date_stamp.dart, ics_serializer.dart, day_timeline_layout.dart, alert_offset.dart, quick_alarm.dart, alert_notification_content.dart, alert_labels.dart, alert_excerpt.dart, sheet_guard.dart, digest_planner.dart, digest_notification_content.dart, digest_labels.dart`.
- Widgets: `calendar_bottom_panel.dart, upcoming_agenda_view.dart, agenda_list_view.dart, agenda_filters_sheet.dart, agenda_day_list_sheet.dart, agenda_day_list_rows.dart, agenda_period_nav.dart, overview_options_sheet.dart, overview_view_sheet.dart, report_totals_card.dart, report_trend_chart.dart, report_category_group.dart, report_group_stack.dart, report_more_categories_sheet.dart, agenda_month_grid.dart, agenda_year_grid.dart, agenda_year_pager.dart, calendar_add_fab.dart, calendar_header_menus.dart, calendar_day_cell.dart, calendar_day_bars.dart, calendar_day_rail.dart, day_summary_panel.dart, day_timeline_view.dart, event_detail_sheet.dart, event_editor_sheet.dart, event_repeat_sheet.dart, event_look_sheet.dart, event_description_sheet.dart, calendar_date_picker_sheet.dart, time_pad_sheet.dart, month_year_picker_sheet.dart, category_picker_sheet.dart, calendar_filter_sheet.dart, filter_check_list_sheet.dart, filter_preset_sheet.dart, alert_editor_sheet.dart, alert_offset_sheet.dart, alert_type_row.dart, alert_sound_sheet.dart, quick_alarm_sheet.dart, event_template_editor_sheet.dart, event_template_picker_sheet.dart, category_editor_sheet.dart, fasting_schedule_sheet.dart, fasting_style_sheet.dart, removed_holidays_sheet.dart, color_swatch_picker.dart, color_palette_sheet.dart, color_picker_sheet.dart, lock_screen_curtain.dart, digest_editor_sheet.dart` (`alarm_metrics.dart, alarm_ground.dart`: `ui-language`).
- Constants: `calendar_bounds.dart, calendar_categories.dart, calendar_icons.dart, public_holidays.dart, fasting_calendar.dart, event_priorities.dart, event_presence.dart, event_skips.dart, occurrence_descriptions.dart, event_alerts.dart, alert_constants.dart, event_title.dart, category_name.dart, fasting_style_limits.dart, event_digests.dart, report_metrics.dart`; the report's bloc `lib/bloc/calendar_report/`.
- DAOs: `category_alert_dao.dart, event_digest_dao.dart`.
- QA: `tool/qa/fixtures/calendar.json, alerts.json, alerts_pair.json` (`test/qa/calendar_fixture_test.dart` pins the first); `tool/qa/flows/calendar/*.txt, alerts/, alerts_pair/`; the alerts fixture's category alert and digest, flows `alerts/03_category_alerts.txt`, `alerts/04_digests.txt` (names as S5 lands them). Robots: `category_editor_robot.dart`, `digest_sheet_robot.dart`. Update a flow in the slice that changes its screen.

## References

| File | When to read it |
| --- | --- |
| `references/subsystems.md` (per heading: anatomy, contracts, whys, full rule lines) | Before changing a surface, or for a rule's why; one section |
| `references/surface-rules.md` (the long rule lines of the Report page, the overview, the ⋮ menu, the guide and the digests, verbatim) | Before changing one of those surfaces; one section |
| `references/schema-lineage.md` | A migration, a backup question, which version added a column |
| `references/context-log.md` (dated changelog since v14, ~200 KB) | To learn why; grep a version, date or class; one entry only |
| `references/colour-palette.md` | Before changing a colour default, its storage or a picker |
| `references/alarm-fork.md` (nine fork patches; rules: `.claude/rules/alarm-fork.md`) | Before touching `packages/alarm/`, or when an alarm acts unlike upstream |
