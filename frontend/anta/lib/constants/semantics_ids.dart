/// Stable identifiers for the controls an automation driver targets.
///
/// Flutter exposes `Semantics.identifier` as the Android `resource-id` and the
/// iOS `accessibilityIdentifier`, separate from the label — so a driver can
/// find a control by id while the screen reader still announces the tooltip or
/// the row's text, and neither the locale nor a copy change moves the target.
///
/// These values are a contract with the driver: rename one and every script
/// that touches that control stops finding it. Add rather than rename, and
/// keep them kebab-case.
abstract final class SemanticsIds {
  /// The two halves of [LeadingNavPair], on every nested screen.
  static const String navBack = 'nav-back';
  static const String navMenu = 'nav-menu';

  /// The browser's create bar. `createNote` only exists below the root — a
  /// note cannot live at the database root, where that half is the importer.
  static const String createNote = 'create-note';
  static const String createFolder = 'create-folder';

  /// The browser bar's magnifier, and the query field it raises — the same
  /// field on the browser, the note lists and the search page.
  static const String searchOpen = 'search-open';
  static const String searchField = 'search-field';

  /// The note editor: the editing surface itself, the markdown toolbar under
  /// it, and the overflow menu that holds move/label/share/delete.
  static const String editorBody = 'editor-body';
  static const String editorToolbar = 'editor-toolbar';
  static const String editorMore = 'editor-more';

  /// Drawer destinations.
  static const String drawerSettings = 'drawer-settings';
  static const String drawerCalendar = 'drawer-calendar';
  static const String drawerCalendarOverview = 'drawer-calendar-overview';
  static const String drawerAlerts = 'drawer-alerts';
  static const String drawerPermissions = 'drawer-permissions';

  /// The two smart rows above the root browser's folders. Named for the
  /// drawer because that is the vocabulary the driver was written against;
  /// the destinations themselves have never lived in the drawer.
  static const String drawerAllNotes = 'drawer-all-notes';
  static const String drawerRecent = 'drawer-recent';

  /// The primary pair of the shared confirmation and text-input dialogs, which
  /// every destructive action and every rename funnels through.
  static const String sheetConfirm = 'sheet-confirm';
  static const String sheetCancel = 'sheet-cancel';

  /// Settings entry points, which live as drawer rows.
  static const String settingsAppearance = 'settings-appearance';
  static const String settingsDatabases = 'settings-databases';

  /// The calendar's controls that are not a day cell.
  static const String calendarToday = 'calendar-today';
  static const String calendarAddEvent = 'calendar-add-event';

  /// The view menu behind the app-bar title of the calendar and the overview,
  /// and its rows. The Overview row keeps the id the app-bar button it
  /// replaced carried, so a script that opened the overview still does once
  /// it has opened the menu.
  static const String calendarViewMenu = 'calendar-view-menu';
  static const String calendarViewCalendar = 'calendar-view-calendar';
  static const String calendarOverviewOpen = 'calendar-overview-open';
  static const String calendarFormatMonth = 'calendar-format-month';
  static const String calendarFormatTwoWeeks = 'calendar-format-two-weeks';
  static const String calendarFormatWeek = 'calendar-format-week';

  /// The ⋮ menu of the calendar and the overview, and its rows.
  static const String calendarMore = 'calendar-more';
  static const String calendarAlertsOpen = 'calendar-alerts-open';
  static const String calendarExport = 'calendar-export';
  static const String calendarSettingsOpen = 'calendar-settings-open';

  /// The calendar's two filter buttons in the app bar and the Filters sheet
  /// behind them (2026-09-27, `docs/calendar-filters-redesign-roadmap.md`):
  /// every row a flow drives, since "All" is not a unique label. The body
  /// scroll view is a container id like [eventForm].
  static const String calendarFilterOpen = 'calendar-filter-open';
  static const String calendarSavedFiltersOpen = 'calendar-saved-filters-open';
  static const String filterSheet = 'filter-sheet';
  static const String filterClose = 'filter-close';
  static const String filterApply = 'filter-apply';
  static const String filterSavedFilter = 'filter-saved-filter';
  static const String filterSave = 'filter-save';
  static const String filterCategories = 'filter-categories';
  static const String filterPriority = 'filter-priority';
  static const String filterRepeat = 'filter-repeat';
  static const String filterRepeatAll = 'filter-repeat-all';
  static const String filterRepeatRecurring = 'filter-repeat-recurring';
  static const String filterRepeatOneTime = 'filter-repeat-one-time';
  static const String filterTime = 'filter-time';
  static const String filterTimeAll = 'filter-time-all';
  static const String filterTimeTimed = 'filter-time-timed';
  static const String filterTimeAllDay = 'filter-time-all-day';
  static const String filterOnlyShow = 'filter-only-show';
  static const String filterHolidays = 'filter-holidays';
  static const String filterFasting = 'filter-fasting';
  static const String filterMoney = 'filter-money';
  static const String filterPanelAll = 'filter-panel-all';
  static const String filterReset = 'filter-reset';

  /// The check-list sub-sheet the Priority and Only show rows open, and its
  /// rows: `priority-1` … `priority-5`, then the seven traits (`tracked`,
  /// `missed`, `linked-note`, `money`, `description`, `counted`, `not-ended`).
  static const String filterListClose = 'filter-list-close';
  static const String filterListDone = 'filter-list-done';
  static String filterListRow(String id) => 'filter-list-$id';

  /// The shared category picker, keyed by category id for its rows.
  static const String categoryPickClose = 'category-pick-close';
  static const String categoryPickDone = 'category-pick-done';
  static const String categoryPickSearch = 'category-pick-search';
  static const String categoryPickSelectAll = 'category-pick-select-all';
  static const String categoryPickSelectNone = 'category-pick-select-none';
  static const String categoryPickCreate = 'category-pick-create';
  static String categoryPickRow(String id) => 'category-pick-$id';

  /// The saved-filters sheet: its rows, each row's drag handle and ⋮, keyed
  /// by preset id, and the four items of that menu.
  static const String filterPresetClose = 'filter-preset-close';
  static const String filterPresetNone = 'filter-preset-none';
  static const String filterPresetSearch = 'filter-preset-search';
  static const String filterPresetSave = 'filter-preset-save';
  static String filterPresetRow(String id) => 'filter-preset-$id';
  static String filterPresetOptions(String id) => 'filter-preset-options-$id';
  static const String filterPresetRename = 'filter-preset-rename';
  static const String filterPresetUpdate = 'filter-preset-update';
  static const String filterPresetDelete = 'filter-preset-delete';
  static String filterPresetHandle(String id) => 'filter-preset-handle-$id';
  static const String filterPresetMoveToTop = 'filter-preset-move-top';

  /// The Upcoming agenda's filter sheet (2026-09-27, Tier 1 of
  /// `docs/calendar-language-tier-1-roadmap.md`): the panel's tune button,
  /// the sheet's chrome and scrolling body, every row and every menu item.
  /// The Filters sheet's twin, so it gets the same treatment: its labels are
  /// the same few words ("All", "Every day") and not unique on the screen.
  static const String agendaFilterOpen = 'agenda-filter-open';
  static const String agendaFilterSheet = 'agenda-filter-sheet';
  static const String agendaFilterClose = 'agenda-filter-close';
  static const String agendaFilterApply = 'agenda-filter-apply';
  static const String agendaFilterPeriod = 'agenda-filter-period';
  static const String agendaFilterPeriod7 = 'agenda-filter-period-7';
  static const String agendaFilterPeriod30 = 'agenda-filter-period-30';
  static const String agendaFilterPeriod90 = 'agenda-filter-period-90';
  static const String agendaFilterPeriodRestOfYear =
      'agenda-filter-period-rest-of-year';
  static const String agendaFilterPeriodThisYear =
      'agenda-filter-period-this-year';
  static const String agendaFilterPeriodCustom = 'agenda-filter-period-custom';
  static const String agendaFilterFollow = 'agenda-filter-follow';
  static const String agendaFilterEvents = 'agenda-filter-events';
  static const String agendaFilterEventsAll = 'agenda-filter-events-all';
  static const String agendaFilterEventsRecurring =
      'agenda-filter-events-recurring';
  static const String agendaFilterEventsOneTime =
      'agenda-filter-events-one-time';
  static const String agendaFilterEventsNone = 'agenda-filter-events-none';
  static const String agendaFilterCategories = 'agenda-filter-categories';
  static const String agendaFilterPriority = 'agenda-filter-priority';
  static const String agendaFilterHolidays = 'agenda-filter-holidays';
  static const String agendaFilterFasting = 'agenda-filter-fasting';
  static const String agendaFilterEventRows = 'agenda-filter-event-rows';
  static const String agendaFilterEventRowsEvery =
      'agenda-filter-event-rows-every';
  static const String agendaFilterEventRowsPerEvent =
      'agenda-filter-event-rows-per-event';
  static const String agendaFilterEventRowsSummary =
      'agenda-filter-event-rows-summary';
  static const String agendaFilterFastingRows = 'agenda-filter-fasting-rows';
  static const String agendaFilterFastingRowsEveryDay =
      'agenda-filter-fasting-rows-every-day';
  static const String agendaFilterFastingRowsPeriods =
      'agenda-filter-fasting-rows-periods';
  static const String agendaFilterFastingRowsSummary =
      'agenda-filter-fasting-rows-summary';
  static const String agendaFilterHolidayRows = 'agenda-filter-holiday-rows';
  static const String agendaFilterHolidayRowsEveryDay =
      'agenda-filter-holiday-rows-every-day';
  static const String agendaFilterHolidayRowsSummary =
      'agenda-filter-holiday-rows-summary';
  static const String agendaFilterReset = 'agenda-filter-reset';

  /// The Dates sheet's Today slot (Tier 1, D11): the fixed 48 dp button after
  /// the title in the month grid's header row and the year view's ‹ year ›
  /// row, where the header's Today icon moved. Its tooltip is localized, so
  /// a flow reaches it by id like [datePickerSave].
  static const String datePickerToday = 'date-picker-today';

  /// The month/year picker's chrome (Tier 1, D13) and the two rows under its
  /// wheels — Today and the "Type the date" switch.
  static const String monthYearClose = 'month-year-close';
  static const String monthYearApply = 'month-year-apply';
  static const String monthYearToday = 'month-year-today';
  static const String monthYearTyped = 'month-year-typed';

  /// The description sheet's ✕ and Done (Tier 1, D14) — a guarded form sheet
  /// since then, so a flow that leaves it dirty meets the dialog and needs a
  /// stable ✕ to have opened with.
  static const String descriptionClose = 'description-close';
  static const String descriptionDone = 'description-done';

  /// The template picker (Tier 1, D16): its ✕, the blank-event row and one
  /// row per template keyed by the template's id, since two templates may
  /// share a name. The quick-alarm row keeps [quickAlarmRow].
  static const String templatePickClose = 'template-pick-close';
  static const String templatePickBlank = 'template-pick-blank';
  static String templatePickRow(String id) => 'template-pick-$id';

  /// The icon picker's ✕ and its pinned search row (Tier 1, D17); the field
  /// is what a flow types into.
  static const String iconPickClose = 'icon-pick-close';
  static const String iconPickSearch = 'icon-pick-search';

  /// The sound sheet's ✕ and its three exclusive rows (Tier 1, D18), whose
  /// labels change with the locale and the phone.
  static const String soundClose = 'sound-close';
  static const String soundInherit = 'sound-inherit';
  static const String soundPhoneDefault = 'sound-phone-default';
  static const String soundFromPhone = 'sound-from-phone';

  /// The event editor's rows and chrome, the two sub-sheets' Done and the
  /// detail sheet's actions: what the calendar flows under `tool/qa/flows/`
  /// target, so a copy change cannot break them.
  /// The editor's scrolling body — a container, so `scroll-to … --in
  /// id:event-form` swipes the form and not the header strip above it.
  static const String eventForm = 'event-form';
  static const String eventTitle = 'event-title';
  static const String eventCategory = 'event-category';
  static const String eventLook = 'event-look';

  /// The description cell's editing surface — a container above the
  /// editor's own text-field node, like [editorBody]: the field carries no
  /// label once it holds text, and the placeholder is not a tap target.
  static const String eventDescription = 'event-description';
  static const String eventDate = 'event-date';
  static const String eventDates = 'event-dates';
  static const String eventAddDate = 'event-add-date';
  static const String eventAllDay = 'event-all-day';
  static const String eventStarts = 'event-starts';
  static const String eventEnds = 'event-ends';
  static const String eventRepeat = 'event-repeat';
  static const String eventPriority = 'event-priority';
  static const String eventLinkedNote = 'event-linked-note';
  static const String eventSave = 'event-save';
  static const String eventClose = 'event-close';
  static const String eventSaveAsTemplate = 'event-save-as-template';
  static const String eventDelete = 'event-delete';
  static const String repeatDone = 'repeat-done';
  static const String lookDone = 'look-done';

  /// The Look sheet's ✕ and its two rows (fix round of Tier 1, 2026-09-27):
  /// "Icon" is a substring of three nodes there — the sheet's title, the row
  /// and the Tint switch — so flow 11 counted labels until the row had an
  /// id. The colour id sits on the swatch row as a container, above the
  /// swatches' own nodes.
  static const String lookClose = 'look-close';
  static const String lookIcon = 'look-icon';
  static const String lookColor = 'look-color';
  static const String eventDetailEdit = 'event-detail-edit';
  static const String eventDetailClose = 'event-detail-close';

  /// The detail sheet's rows a flow drives (2026-09-26): the description
  /// pencil, the presence pair (whose labels change with the locale), Skip
  /// this day, Add date, the bundled Dates row and the linked note.
  static const String eventDetailDescription = 'event-detail-description';
  static const String eventDetailPresent = 'event-detail-present';
  static const String eventDetailMissed = 'event-detail-missed';
  static const String eventDetailSkip = 'event-detail-skip';
  static const String eventDetailAddDate = 'event-detail-add-date';
  static const String eventDetailDates = 'event-detail-dates';
  static const String eventDetailNote = 'event-detail-note';

  /// A day-panel or agenda row standing for one event, keyed by the event's
  /// id — a title is ambiguous because every marked day cell's marker label
  /// carries it too, and a seeded event's id is stable (`qa-cal-lift`).
  static String eventRow(String eventId) => 'event-row-$eventId';

  static const String datePickerCancel = 'date-picker-cancel';
  static const String datePickerSave = 'date-picker-save';

  /// The colour-label swatch strip, in whichever sheet raised it.
  static const String labelPicker = 'label-picker';

  /// The alarm page's four actions. Tagged because a device pass has to stop a
  /// ring in whatever language the phone is in, and because the page has no
  /// app bar and no other landmark to target.
  static const String alarmStop = 'alarm-stop';
  static const String alarmSnooze = 'alarm-snooze';
  static const String alarmOpenEvent = 'alarm-open-event';
  static const String alarmKeepEvent = 'alarm-keep-event';

  /// The calendar settings row that arms a ring ten seconds from now.
  static const String alertsTestAlarm = 'alerts-test-alarm';

  /// The event editor's "Add alert" chip and the Save of the sheet it raises.
  /// A device pass has to arm an alarm on a real event, and both controls sit
  /// inside a scrolling form with no other stable landmark.
  static const String eventAlertAdd = 'event-alert-add';
  static const String alertSheetSave = 'alert-sheet-save';
  static const String eventAlertRemoveAfter = 'event-alert-remove-after';

  /// The quick-alarm sheet (parent Session 6) and the picker row that opens
  /// it: a device pass sets an alarm in whatever language the phone is in.
  static const String quickAlarmRow = 'quick-alarm-row';
  static const String quickAlarmTime = 'quick-alarm-time';
  static const String quickAlarmName = 'quick-alarm-name';
  static const String quickAlarmSave = 'quick-alarm-save';
  static const String quickAlarmRemoveAfter = 'quick-alarm-remove-after';

  static const String timePadCancel = 'time-pad-cancel';
  static const String timePadDone = 'time-pad-done';
  static const String timePadHour = 'time-pad-hour';
  static const String timePadMinute = 'time-pad-minute';
  static const String timePadBackspace = 'time-pad-backspace';
  static const String timePadOnTheHour = 'time-pad-on-the-hour';
  static const String timePadHalfPast = 'time-pad-half-past';
  static const String timePadAm = 'time-pad-am';
  static const String timePadPm = 'time-pad-pm';
  static String timePadDigit(int digit) => 'time-pad-digit-$digit';

  static const String permissionsPromptContinue = 'permissions-prompt-continue';
  static const String permissionsPromptNotNow = 'permissions-prompt-not-now';
}
