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
  /// The two halves of [LeadingNavPair], on every nested screen. The root
  /// browser's lone menu button carries [navMenu] too, so a flow opens the
  /// drawer by one id wherever it starts; a settings bar drawn without the
  /// menu button marks its lone arrow [navBack], so a flow leaves either kind
  /// by one id.
  static const String navBack = 'nav-back';
  static const String navMenu = 'nav-menu';

  /// The browser's create bar. `createNote` only exists below the root — a
  /// note cannot live at the database root, where that half is the importer.
  static const String createNote = 'create-note';
  static const String createFolder = 'create-folder';

  /// A browser row — a folder or a note — keyed by the item's id, and the
  /// drag handle it shows in selection mode, keyed by the row's position in
  /// the reorderable list (section headers count): an imported item gets a
  /// fresh id, so a flow over a seed can only spell the position. The row's
  /// long press opens its sheet; only the handle starts a reorder.
  static String browserRow(String id) => 'browser-row-$id';
  static String browserDragHandle(int position) =>
      'browser-drag-handle-$position';

  /// Select in a browser row's long-press sheet — the way into selection,
  /// and so into the drag handles.
  static const String rowActionSelect = 'row-action-select';

  /// The browser bar's magnifier, and the query field it raises — the same
  /// field on the browser, the note lists and the search page.
  static const String searchOpen = 'search-open';
  static const String searchField = 'search-field';

  /// The note editor: the editing surface itself, the markdown toolbar under
  /// it, and the overflow menu that holds move/label/share/delete.
  static const String editorBody = 'editor-body';
  static const String editorToolbar = 'editor-toolbar';
  static const String editorMore = 'editor-more';

  /// A level in the markdown bar's heading menu, 1 to 6.
  static String editorHeadingLevel(int level) => 'editor-heading-$level';

  /// Drawer destinations (D1 of `docs/settings-rework-roadmap.md`): the
  /// places, top to bottom. `drawerSettings` opens the settings hub.
  static const String drawerCalendar = 'drawer-calendar';
  static const String drawerCalendarOverview = 'drawer-calendar-overview';
  static const String drawerCalendarReport = 'drawer-calendar-report';
  static const String drawerCalendarCategories = 'drawer-calendar-categories';
  static const String drawerAlerts = 'drawer-alerts';
  static const String drawerCounters = 'drawer-counters';
  static const String drawerSettings = 'drawer-settings';
  static const String drawerHowTo = 'drawer-how-to';

  /// The drawer's About row, which opens the about dialog.
  static const String drawerAbout = 'drawer-about';

  /// The About dialog's title, which a flow waits for before reading the
  /// version beside it.
  static const String aboutDialog = 'about-dialog';

  /// The settings hub's Language and Theme dialogs, by their titles: a flow
  /// waits for each without spelling the title's words.
  static const String languageDialog = 'language-dialog';
  static const String themeDialog = 'theme-dialog';

  /// The drawer header's app icon, whose five taps unlock Developer options:
  /// the one way a flow reaches that page's hub row.
  static const String drawerHeaderIcon = 'drawer-header-icon';

  /// The drawer's scrolling list of rows. A flow reaching a row past the
  /// list's cache extent swipes inside it (`scroll-to … --in id:drawer-list`):
  /// the first scrollable a dump lists is the header's avatar block, and a
  /// swipe there scrolls nothing (settings pass, 2026-10-31).
  static const String drawerList = 'drawer-list';

  /// The two smart rows above the root browser's folders. Named for the
  /// drawer because that is the vocabulary the driver was written against;
  /// the destinations themselves have never lived in the drawer.
  static const String drawerAllNotes = 'drawer-all-notes';
  static const String drawerRecent = 'drawer-recent';

  /// The primary pair of the shared confirmation and text-input dialogs, which
  /// every destructive action and every rename funnels through.
  static const String sheetConfirm = 'sheet-confirm';
  static const String sheetCancel = 'sheet-cancel';

  /// The form sheets' leave guard (`AppDialogs.confirmDiscard`): its title,
  /// which a flow waits for, and its two buttons.
  static const String unsavedDialog = 'unsaved-dialog';
  static const String unsavedKeepEditing = 'unsaved-keep-editing';
  static const String unsavedDiscard = 'unsaved-discard';

  /// The Undo of an action snackbar a flow waits for or taps; the bar's
  /// message stays an assertion, its action word is translated.
  static const String snackbarUndo = 'snackbar-undo';

  /// The settings hub's Theme row, which opens the theme dialog (D11: the
  /// id moved with the row from the drawer).
  static const String settingsAppearance = 'settings-appearance';

  /// The search field of every settings page that has one; its hint says
  /// which list it filters, so a flow tells the pages apart by their rows.
  static const String settingsSearch = 'settings-search';

  /// The settings search field's clear button, drawn only while the field
  /// holds text.
  static const String settingsSearchClear = 'settings-search-clear';

  /// App settings' bar title. Each `settingsBar*` id is the anchor a flow
  /// waits on to know which settings page is on top, since the title text is
  /// translated.
  static const String settingsBarApp = 'settings-bar-app';

  /// App settings' list, every row on it and its Reset to defaults (S17,
  /// D13), in the page's order; the four deprecated preview rows last.
  static const String appSettingsList = 'app-settings-list';
  static const String appSettingsRestoreLocation =
      'app-settings-restore-location';
  static const String appSettingsNotePreview = 'app-settings-note-preview';
  static const String appSettingsLabelStyle = 'app-settings-label-style';
  static const String appSettingsStatsBar = 'app-settings-stats-bar';
  static const String appSettingsFolderSwipe = 'app-settings-folder-swipe';
  static const String appSettingsLiveMarkdown = 'app-settings-live-markdown';
  static const String appSettingsWordWrap = 'app-settings-word-wrap';
  static const String appSettingsAutoBreak = 'app-settings-auto-break';
  static const String appSettingsLineNumbers = 'app-settings-line-numbers';
  static const String appSettingsCursorLine = 'app-settings-cursor-line';
  static const String appSettingsScrollCursor = 'app-settings-scroll-cursor';
  static const String appSettingsNoteSwipe = 'app-settings-note-swipe';
  static const String appSettingsAutoSave = 'app-settings-auto-save';
  static const String appSettingsAutoSaveInterval =
      'app-settings-auto-save-interval';
  static const String appSettingsHaptics = 'app-settings-haptics';
  static const String appSettingsConfirmDelete = 'app-settings-confirm-delete';
  static const String appSettingsPreviewMode = 'app-settings-preview-mode';
  static const String appSettingsPreviewWhenHidden =
      'app-settings-preview-when-hidden';
  static const String appSettingsPreviewScrollbar =
      'app-settings-preview-scrollbar';
  static const String appSettingsPreviewChunk = 'app-settings-preview-chunk';
  static const String appSettingsReset = 'app-settings-reset';

  /// Calendar settings' bar title.
  static const String settingsBarCalendar = 'settings-bar-calendar';

  /// The Alerts hub's bar title.
  static const String settingsBarAlerts = 'settings-bar-alerts';

  /// The Alerts hub's ⚙, which opens Alert settings (D5).
  static const String alertsSettingsOpen = 'alerts-settings-open';

  /// The Alert settings page's bar title.
  static const String settingsBarAlertSettings = 'settings-bar-alert-settings';

  /// The Fasting settings page's bar title.
  static const String settingsBarFasting = 'settings-bar-fasting';

  /// The Report cards settings page's bar title.
  static const String settingsBarReportCards = 'settings-bar-report-cards';

  /// Markdown shortcuts' bar title.
  static const String settingsBarMarkdown = 'settings-bar-markdown';

  /// Markdown shortcuts' scroll view, its bar's ⋮ (Reset, Remove custom),
  /// the bar selector's ⋮ and its per-note entry, and the rows a flow reads
  /// (S6 of the settings rework).
  static const String markdownSettingsList = 'markdown-settings-list';
  static const String markdownBarMenu = 'markdown-bar-menu';
  static const String markdownProfileMenu = 'markdown-profile-menu';
  static const String markdownPerNoteBars = 'markdown-per-note-bars';
  static const String markdownMoneyStart = 'markdown-money-start';
  static const String markdownMoneySymbol = 'markdown-money-symbol';
  static const String markdownPerNoteCurrency = 'markdown-per-note-currency';
  static const String markdownVocabularyTrigger = 'markdown-vocabulary-trigger';

  /// One utility-button row, by its `UtilityButtonDefinition` id.
  static String markdownUtility(String id) => 'markdown-utility-$id';

  /// One shortcut row, its visibility toggle and its ⋮, by the shortcut's id.
  static String markdownShortcutRow(String id) => 'markdown-shortcut-row-$id';
  static String markdownShortcutVisibility(String id) =>
      'markdown-shortcut-visibility-$id';
  static String markdownShortcutMenu(String id) => 'markdown-shortcut-menu-$id';

  /// The Vocabularies page's list, one vocabulary row and its switch by the
  /// vocabulary's id, and the create button.
  static const String vocabulariesList = 'vocabularies-list';
  static String vocabularyRow(String id) => 'vocabulary-row-$id';
  static String vocabularyEnabled(String id) => 'vocabulary-enabled-$id';
  static const String vocabulariesAdd = 'vocabularies-add';

  /// The per-note bar page's bar title, its list, and one note's row and ⋮
  /// by the note's id.
  static const String settingsBarNoteBars = 'settings-bar-note-bars';
  static const String noteBarsList = 'note-bars-list';
  static String noteBarRow(String noteId) => 'note-bar-row-$noteId';
  static String noteBarMenu(String noteId) => 'note-bar-menu-$noteId';

  /// The per-note currency page's bar title, its list, and one note's row
  /// and ⋮ by the note's id.
  static const String settingsBarNoteCurrencies =
      'settings-bar-note-currencies';
  static const String noteCurrenciesList = 'note-currencies-list';
  static String noteCurrencyRow(String noteId) => 'note-currency-row-$noteId';
  static String noteCurrencyMenu(String noteId) => 'note-currency-menu-$noteId';

  /// The Counters page's bar title.
  static const String settingsBarCounters = 'settings-bar-counters';

  /// The Sharing page's bar title.
  static const String settingsBarSharing = 'settings-bar-sharing';

  /// The Sharing page's list, and its rows by the action their tap performs.
  /// The account row and the pairing row each carry the id of the state they
  /// are in — signed out it is [sharingSignIn], signed in [sharingSignOut],
  /// on a build without sync (the QA build has no Firebase) the disabled
  /// [sharingUnavailable] — so a flow waits on the id of the state it expects.
  static const String sharingList = 'sharing-list';
  static const String sharingUnavailable = 'sharing-unavailable';
  static const String sharingSignIn = 'sharing-sign-in';
  static const String sharingSignOut = 'sharing-sign-out';
  static const String sharingRetry = 'sharing-retry';
  static const String sharingPair = 'sharing-pair';
  static const String sharingUnpair = 'sharing-unpair';
  static const String sharingClose = 'sharing-close';

  /// The Sharing page's Sync section: unbound it is the one [sharingSync]
  /// row, bound the status row, Sync now and the stop row — so a flow tells
  /// the two apart by which ids it finds. [sharingSyncStopConfirm] is the
  /// stop dialog's confirm, apart from the app-wide [sheetConfirm] so a
  /// flow cannot answer another dialog by mistake.
  static const String sharingSync = 'sharing-sync';
  static const String sharingSyncStatus = 'sharing-sync-status';
  static const String sharingSyncNow = 'sharing-sync-now';
  static const String sharingSyncStop = 'sharing-sync-stop';
  static const String sharingSyncStopConfirm = 'sharing-sync-stop-confirm';

  /// The bind picker: its body, its ✕, one row per space by the space's id,
  /// and its three choices — [syncPickerMerge] also on "Sync with …", the
  /// merge of a database that holds nothing.
  static const String syncPicker = 'sync-picker';
  static const String syncPickerClose = 'sync-picker-close';
  static String syncPickerSpace(String spaceId) => 'sync-picker-space-$spaceId';
  static const String syncPickerMerge = 'sync-picker-merge';
  static const String syncPickerDownload = 'sync-picker-download';
  static const String syncPickerUpload = 'sync-picker-upload';

  /// The Databases page's bar title.
  static const String settingsBarDatabases = 'settings-bar-databases';

  /// The Databases page's own scroll, which a flow swipes to reach the cards
  /// below the first screen (`scroll-to --in`).
  static const String databasesPage = 'databases-page';

  /// The Databases page's list of database files: a flow reaching a lower
  /// row swipes inside it (`scroll-to --in`), never the page around it.
  static const String databasesList = 'databases-list';

  /// One database row and its ⋮, by the database's file name — the ⋮ under
  /// a prefix no other id starts with, so no database's name (`menu-x`,
  /// `delete`) can make it the row's id or a menu entry's.
  static String databaseRow(String name) => 'database-row-$name';
  static String databaseMore(String name) => 'database-more-$name';

  /// The entries of a database row's menu.
  static const String databaseMenuSwitch = 'database-menu-switch';
  static const String databaseMenuRename = 'database-menu-rename';
  static const String databaseMenuDelete = 'database-menu-delete';

  /// The Databases page's buttons and the selectable path.
  static const String databaseCreate = 'database-create';
  static const String databaseImport = 'database-import';
  static const String databaseShare = 'database-share';
  static const String databaseOptimize = 'database-optimize';
  static const String databaseDeleteAll = 'database-delete-all';
  static const String databasePath = 'database-path';

  /// Developer options' bar title.
  static const String settingsBarDeveloper = 'settings-bar-developer';

  /// Developer options' list; one switch row by its `DevOptions` field name
  /// (`colorMarkdownBlocks`, `showFpsCounter`, …); the footer's two buttons.
  static const String developerOptionsList = 'developer-options-list';
  static String developerOption(String key) => 'developer-option-$key';
  static const String developerOptionsReset = 'developer-options-reset';
  static const String developerOptionsLock = 'developer-options-lock';

  /// The Permissions page's bar title.
  static const String settingsBarPermissions = 'settings-bar-permissions';

  /// The Permissions page's list; one permission row by its `AppPermission`
  /// name (`notifications`, `exactAlarms`, …); the launch-check switch and
  /// the system-settings row.
  static const String permissionsList = 'permissions-list';
  static String permissionTile(String kind) => 'permission-$kind';
  static const String permissionsLaunchCheck = 'permissions-launch-check';
  static const String permissionsSystemSettings = 'permissions-system-settings';

  /// The welcome screen's scroll view and its two buttons.
  static const String onboardingList = 'onboarding-list';
  static const String onboardingStartFresh = 'onboarding-start-fresh';
  static const String onboardingRestore = 'onboarding-restore';

  /// The settings hub's bar title.
  static const String settingsBarHub = 'settings-bar-hub';

  /// The Appearance page's bar title.
  static const String settingsBarAppearance = 'settings-bar-appearance';

  /// The settings hub's search field — its own, so a flow typing into the
  /// hub never lands in a page's field left beneath it.
  static const String settingsHubSearch = 'settings-hub-search';

  /// The settings hub's list: a flow reaching a lower row swipes inside it
  /// (`scroll-to --in`), never in the search field above.
  static const String settingsHubList = 'settings-hub-list';

  /// One row of the settings hub, by the name of the page or dialog it
  /// opens: `calendarSettings`, `calendarAppearance`, `calendarCategories`,
  /// `markdownSettings`, `counterManagement`, `settings` (General),
  /// `language`, `databaseSettings`, `syncSettings`, `permissions`,
  /// `developerOptions`, `calendarGuide`. The Theme row carries
  /// [settingsAppearance] instead, the id it had in the drawer.
  static String settingsHubRow(String kind) => 'settings-hub-row-$kind';

  /// The calendar's controls that are not a day cell. The month title opens
  /// the month/year picker; its label is the month itself.
  static const String calendarToday = 'calendar-today';
  static const String calendarAddEvent = 'calendar-add-event';
  static const String calendarMonthTitle = 'calendar-month-title';

  /// The bottom panel's mode segments (`day`, `timeline`, `upcoming`), keyed
  /// by `CalendarPanelMode.name`.
  static String panelMode(String mode) => 'panel-mode-$mode';

  /// The view menu behind the app-bar title of the calendar and the overview,
  /// and its rows. The Overview row keeps the id the app-bar button it
  /// replaced carried, so a script that opened the overview still does once
  /// it has opened the menu.
  static const String calendarViewMenu = 'calendar-view-menu';
  static const String calendarViewCalendar = 'calendar-view-calendar';
  static const String calendarOverviewOpen = 'calendar-overview-open';
  static const String calendarReportOpen = 'calendar-report-open';
  static const String calendarFormatMonth = 'calendar-format-month';
  static const String calendarFormatTwoWeeks = 'calendar-format-two-weeks';
  static const String calendarFormatWeek = 'calendar-format-week';

  /// The ⋮ menu of the calendar and the overview, and its rows.
  static const String calendarMore = 'calendar-more';
  static const String calendarAlertsOpen = 'calendar-alerts-open';
  static const String calendarMenuCategories = 'calendar-menu-categories';
  static const String calendarExport = 'calendar-export';
  static const String calendarGuideOpen = 'calendar-guide-open';
  static const String calendarSettingsOpen = 'calendar-settings-open';

  /// The calendar guide's list: a flow waits on the page and scrolls inside
  /// it without depending on the guide's wording or the locale.
  static const String calendarGuide = 'calendar-guide';

  /// One guide row, keyed by a slug frozen in the page, so a flow checks a
  /// row is there whatever its text says.
  static String calendarGuideRow(String slug) => 'calendar-guide-$slug';

  /// A hub row that opens one of the guide's pages, keyed by the page's slug;
  /// the `page-` infix keeps it apart from a read row of the same slug.
  static String calendarGuidePage(String slug) => 'calendar-guide-page-$slug';

  /// One guide page's list: a flow waits on it after the push and scrolls
  /// inside it, as it does in the hub's [calendarGuide].
  static String calendarGuideTopic(String slug) => 'calendar-guide-topic-$slug';

  /// The practice calendar's body and its band: a flow waits on the page
  /// and reads the coach line without depending on its wording.
  static const String calendarGuidePractice = 'calendar-guide-practice';
  static const String calendarGuidePracticeBanner =
      'calendar-guide-practice-banner';

  /// The practice page's body in its filtering lesson, so a flow knows which
  /// lesson it opened. Only the body differs: the band, the bar and the add
  /// button keep the ids below in both lessons, because the two are one
  /// page and never on screen together, so a flow cannot land on the wrong
  /// one.
  static const String calendarGuidePracticeFiltering =
      'calendar-guide-practice-filtering';

  /// The practice page's bar buttons and add button. Their own ids, not the
  /// real calendar's, so a flow that taps one can never land on the other.
  static const String practiceReset = 'practice-reset';
  static const String practiceFilterOpen = 'practice-filter-open';
  static const String practiceMore = 'practice-more';
  static const String practiceAddEvent = 'practice-add-event';

  /// The band's skip past the tour's current step: a flow checks the band
  /// is the coached one without reading its words. Since D70 it names the
  /// forward button, which skips at the live line.
  static const String practiceSkip = 'practice-skip';

  /// The band's back button, to an earlier step's line (D89).
  static const String practiceStepBack = 'practice-step-back';

  /// A task page's "Try it" card, keyed by the page's slug: a container
  /// node, so the stage's controls stay nodes of their own.
  static String calendarGuideTry(String slug) => 'calendar-guide-try-$slug';

  /// The card's live coach line, read by a flow whatever it says. The id
  /// is the caption's it replaced; ids are never renamed.
  static String calendarGuideTryCaption(String slug) =>
      'calendar-guide-try-$slug-caption';

  /// The coach line's skip. Not `try-<slug>-skip`: the kinds stage's Skip
  /// this day row has held `try-kinds-skip` since it shipped. Since D70 it
  /// names the forward button, which skips at the live line.
  static String calendarGuideTrySkip(String slug) => 'try-$slug-skip-step';

  /// The coach line's back button, to an earlier step's line (D89).
  static String calendarGuideTryStepBack(String slug) => 'try-$slug-step-back';

  /// A control a card adds to its stage. The real widgets a stage draws
  /// keep their own ids — the screen card's title menu is
  /// `calendar-view-menu` with its rows — because the real calendar and a
  /// card never share a screen, so a flow cannot land on the wrong one; the
  /// controls the cards add are `try-*`.
  ///
  /// The screen stage's (D86): `try-screen-saved-filters` and
  /// `try-screen-filter` on the Calendar's bar, `try-screen-overview-options`
  /// and `try-screen-overview-views` on the Overview's — each disabled, never
  /// hidden — and `try-screen-more`, the ⋮ of every view; the Overview's
  /// body keeps the `try-overview-*` ids of the card it was.
  static String calendarGuideTryControl(String slug, String control) =>
      'try-$slug-$control';

  /// The screen stage's view body — `calendar`, `overview` or `report`, a
  /// `CalendarViewPage`'s name (`try-screen-view-calendar` …): a container
  /// node, so a flow can wait for the view the title menu switched to.
  static String calendarGuideScreenView(String view) =>
      calendarGuideTryControl('screen', 'view-$view');

  /// Calendar settings' rows that open a page or a sheet, and the two
  /// default-alert rows (on Alert settings since D5): a section header shares
  /// some of their words, and the rest read back a value. A fasting style row
  /// exists per enabled tradition, so it is keyed by `FastingTradition.name`.
  static const String calendarAppearanceOpen = 'calendar-appearance-open';
  static const String calendarCategoriesOpen = 'calendar-categories-open';
  static const String calendarRemovedHolidaysOpen =
      'calendar-removed-holidays-open';
  static const String calendarFastingScheduleOpen =
      'calendar-fasting-schedule-open';
  static String calendarFastingStyleOpen(String tradition) =>
      'calendar-fasting-style-open-$tradition';
  static const String calendarEventTemplatesOpen =
      'calendar-event-templates-open';
  static const String alertsDefaultTimed = 'alerts-default-timed';
  static const String alertsDefaultAllDay = 'alerts-default-all-day';

  /// Calendar settings' one row left where its alerts section was (D5): it
  /// opens the Alert settings page.
  static const String calendarSettingsAlertsOpen =
      'calendar-settings-alerts-open';

  /// The Alert settings page's list, for a flow that swipes inside it, and
  /// its rows that had no id while they lived on Calendar settings — the two
  /// defaults and the test alarm keep theirs. The categories and how-it-works
  /// rows open a page each.
  static const String alertSettingsList = 'alert-settings-list';
  static const String alertSettingsSound = 'alert-settings-sound';
  static const String alertSettingsSnooze = 'alert-settings-snooze';
  static const String alertSettingsNotice = 'alert-settings-notice';
  static const String alertSettingsSilence = 'alert-settings-silence';
  static const String alertSettingsPermissions = 'alert-settings-permissions';
  static const String alertSettingsCategoriesOpen =
      'alert-settings-categories-open';
  static const String alertSettingsHowItWorksOpen =
      'alert-settings-how-it-works-open';

  /// Calendar settings' one row left where its fasting section was (D6): it
  /// opens the Fasting settings page.
  static const String calendarSettingsFastingOpen =
      'calendar-settings-fasting-open';

  /// Calendar settings' row that opens the Report cards page (W).
  static const String calendarSettingsReportOpen =
      'calendar-settings-report-open';

  /// A Report cards row's switch and its drag handle, by its
  /// `ReportCardKind` name: `report-card-switch-dueSoon`, … — one each per
  /// card, so a flow can turn a card off or drag it without reading labels.
  static String reportCardSwitch(String card) => 'report-card-switch-$card';
  static String reportCardHandle(String card) => 'report-card-handle-$card';

  /// The Report cards page's reset to the default order, every card on.
  static const String reportCardsReset = 'report-cards-reset';

  /// Calendar settings' rows that had no id (D13): the holiday set's
  /// row, the filter chips switch, the description-limit slider and
  /// Delete all events.
  static const String calendarHolidayProfile = 'calendar-holiday-profile';
  static const String calendarShowFilterChips = 'calendar-show-filter-chips';
  static const String calendarDescriptionLimit = 'calendar-description-limit';
  static const String calendarDeleteAllEvents = 'calendar-delete-all-events';

  /// One profile in the holiday set's menu, keyed by `HolidayProfile.name`.
  static String calendarHolidayProfileItem(String profile) =>
      'calendar-holiday-profile-$profile';

  /// The Fasting settings page's list and its rows that had no id while they
  /// lived on Calendar settings — the look and practice rows keep theirs
  /// (`calendarFastingStyleOpen`, `calendarFastingScheduleOpen`). A tradition
  /// switch is keyed by `FastingTradition.name`.
  static const String fastingSettingsList = 'fasting-settings-list';
  static String fastingTraditionSwitch(String tradition) =>
      'fasting-tradition-switch-$tradition';
  static const String fastingGreatFastsSwitch = 'fasting-great-fasts-switch';
  static const String fastingSettingsHowItWorksOpen =
      'fasting-settings-how-it-works-open';

  /// The appearance page's Today highlight and Highlight color rows —
  /// containers above their own segments and swatches — and the Missed days
  /// segments.
  static const String appearanceTodayStyle = 'appearance-today-style';
  static const String appearanceAccentColor = 'appearance-accent-color';

  /// The appearance page's Week starts on row, one day in its menu (keyed by
  /// `CalendarWeekStart.name`), and the On fasting days row.
  static const String appearanceWeekStart = 'appearance-week-start';
  static String appearanceWeekStartItem(String start) =>
      'appearance-week-start-$start';
  static const String appearanceTintConflict = 'appearance-tint-conflict';
  static const String missedDisplayFaded = 'missed-display-faded';
  static const String missedDisplayHidden = 'missed-display-hidden';

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

  /// The name dialog the saved filters and the overview's saved views share:
  /// its field and its Save button. "Save" alone is no target, since the
  /// sheets behind it say "Save the current list" and "Saved views".
  static const String filterPresetName = 'filter-preset-name';
  static const String filterPresetNameSave = 'filter-preset-name-save';

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

  /// The Dates sheet's view segments (`month`, `year`, `list`), keyed by
  /// `CalendarDatePickerView.name`: their words are the day list's too.
  static String datePickerView(String view) => 'date-picker-view-$view';

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

  /// The description cell's Open full editor button.
  static const String eventDescriptionExpand = 'event-description-expand';
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

  /// The Repeat sheet's ✕ and its kind rows, keyed by `RepeatKind.name`
  /// (`repeat-kind-daily` …); "Does not repeat" has none.
  static const String repeatClose = 'repeat-close';
  static String repeatKind(String kind) => 'repeat-kind-$kind';

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

  /// A one-off's Cancel this event and the Cancelled state's Restore — ids
  /// of their own, because a flow that cancels a one-off must not be able to
  /// pass by tapping a recurring event's Skip this day.
  static const String eventDetailCancel = 'event-detail-cancel';
  static const String eventDetailRestore = 'event-detail-restore';
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

  /// The alarm page's Open row while it is the switch to another database —
  /// an id of its own, because a flow that taps "open the event" must never
  /// find itself switching databases instead — and the page's scrolling
  /// body. The body scrolls from its end, so on a short screen the time is
  /// what has left the top: a flow brings it back with `scroll-to --up --in
  /// id:alarm-body`.
  static const String alarmOpenDatabase = 'alarm-open-database';
  static const String alarmBody = 'alarm-body';

  /// The Alert settings row that arms a ring ten seconds from now.
  static const String alertsTestAlarm = 'alerts-test-alarm';

  /// The event editor's "Add alert" chip and the Save of the sheet it raises.
  /// A device pass has to arm an alarm on a real event, and both controls sit
  /// inside a scrolling form with no other stable landmark.
  static const String eventAlertAdd = 'event-alert-add';
  static const String alertSheetSave = 'alert-sheet-save';
  static const String eventAlertRemoveAfter = 'event-alert-remove-after';

  /// The ✕ on the editor's own alert rows, by the row's position: the rows
  /// share one tooltip and an alert's id is not something a flow can spell.
  static String eventAlertRemove(int index) => 'event-alert-remove-$index';

  /// The alert sheet's ✕ and rows (Tier 2,
  /// `docs/calendar-language-tier-2-roadmap.md`); its header action keeps
  /// [alertSheetSave]. A When menu item is keyed by what it stores — minutes
  /// before the start for a timed event, days before for an all-day one —
  /// because its label is a phrase that changes with the locale.
  static const String alertSheetClose = 'alert-sheet-close';
  static const String alertTypeReminder = 'alert-type-reminder';
  static const String alertTypeAlarm = 'alert-type-alarm';
  static const String alertWhen = 'alert-when';
  static String alertWhenItem(int minutes) => 'alert-when-$minutes';
  static String alertWhenDayItem(int days) => 'alert-when-day-$days';
  static const String alertWhenCustom = 'alert-when-custom';
  static const String alertWhenDayCustom = 'alert-when-day-custom';
  static const String alertTimeOfDay = 'alert-time-of-day';
  static const String alertSound = 'alert-sound';
  static const String alertRemoveAfter = 'alert-remove-after';
  static const String alertRemove = 'alert-remove';

  /// The alert sheet's second When row, offered for a category alert only
  /// (**v42**): a category serves timed and all-day events at once, so the
  /// sheet edits both offset sets, the timed one on [alertWhen].
  static const String alertWhenAllDay = 'alert-when-all-day';

  /// The category editor's Alerts group (**v42**) by position — a category
  /// alert's label is a locale's phrase — with each row's switch, the
  /// category's own on / off for that alert (D5); the event editor's switch
  /// that opts one event out of its category's alerts, and its read rows of
  /// what the event inherits.
  static const String categoryAlertAdd = 'category-alert-add';
  static String categoryAlertRow(int index) => 'category-alert-$index';
  static String categoryAlertSwitch(int index) =>
      'category-alert-switch-$index';
  static const String eventCategoryAlerts = 'event-category-alerts';
  static String eventInheritedAlert(int index) =>
      'event-inherited-alert-$index';

  /// The Alerts hub's Digests group (**v42**): Add digest, each digest's row
  /// and its switch, and a digest's fire row among the day groups — by the
  /// digest's id, since its title may be derived and so not unique; a fire
  /// also by its instant (epoch ms), since a digest lists two.
  static const String alertsDigestAdd = 'alerts-digest-add';
  static String alertsDigestRow(String id) => 'alerts-digest-$id';
  static String alertsDigestSwitch(String id) => 'alerts-digest-switch-$id';
  static String alertsDigestFire(String id, DateTime fireAt) =>
      'alerts-digest-fire-$id-${fireAt.millisecondsSinceEpoch}';

  /// The digest sheet's ✕, Save and rows. A menu item is keyed by what it
  /// stores — the cadence's name, the anchor's weekday (1–7) or day of the
  /// month (1–28), the lead in days — because its label is the locale's.
  static const String digestSheetClose = 'digest-sheet-close';
  static const String digestSheetSave = 'digest-sheet-save';

  /// The sheet's scrolling body — a container, so `scroll-to … --in
  /// id:digest-sheet-body` swipes the rows and not the header above them.
  static const String digestSheetBody = 'digest-sheet-body';
  static const String digestName = 'digest-name';
  static const String digestCategories = 'digest-categories';

  /// The Shows row and its items, keyed `upcoming`, `week-report` and
  /// `month-report`.
  static const String digestShows = 'digest-shows';
  static String digestShowsItem(String name) => 'digest-shows-$name';
  static const String digestCadence = 'digest-cadence';
  static String digestCadenceItem(String name) => 'digest-cadence-$name';
  static const String digestAnchor = 'digest-anchor';
  static String digestAnchorItem(int value) => 'digest-anchor-$value';
  static const String digestTime = 'digest-time';
  static const String digestLead = 'digest-lead';
  static String digestLeadItem(int days) => 'digest-lead-$days';
  static const String digestIncludeEmpty = 'digest-include-empty';
  static const String digestDelete = 'digest-delete';

  /// The Custom sub-sheet behind the When menu's last item: its ✕ and Done,
  /// the three unit chips a timed event gets and the stepper's two buttons.
  static const String alertCustomClose = 'alert-custom-close';
  static const String alertCustomDone = 'alert-custom-done';
  static const String alertCustomUnitMinutes = 'alert-custom-unit-minutes';
  static const String alertCustomUnitHours = 'alert-custom-unit-hours';
  static const String alertCustomUnitDays = 'alert-custom-unit-days';
  static const String alertCustomLess = 'alert-custom-less';
  static const String alertCustomMore = 'alert-custom-more';

  /// The quick-alarm sheet (parent Session 6) and the picker row that opens
  /// it: a device pass sets an alarm in whatever language the phone is in.
  static const String quickAlarmRow = 'quick-alarm-row';
  static const String quickAlarmTime = 'quick-alarm-time';
  static const String quickAlarmName = 'quick-alarm-name';
  static const String quickAlarmSave = 'quick-alarm-save';
  static const String quickAlarmRemoveAfter = 'quick-alarm-remove-after';

  /// The quick alarm's ✕, its three presets and its two tier chips (Tier 2).
  /// The tier chips are the alert sheet's words on a second sheet, so they
  /// take ids of their own rather than sharing [alertTypeReminder].
  static const String quickAlarmClose = 'quick-alarm-close';
  static const String quickAlarmPreset20 = 'quick-alarm-preset-20';
  static const String quickAlarmPreset60 = 'quick-alarm-preset-60';
  static const String quickAlarmPresetTonight = 'quick-alarm-preset-tonight';
  static const String quickAlarmTypeReminder = 'quick-alarm-type-reminder';
  static const String quickAlarmTypeAlarm = 'quick-alarm-type-alarm';

  /// The Event templates page's create button and each row's delete, by the
  /// row's position: a template a flow has just created has an id it cannot
  /// spell.
  static const String templatesCreate = 'templates-create';
  static String templateDelete(int index) => 'template-delete-$index';

  /// The template form (Tier 2): its ✕ and Save and every row. The form is
  /// the event editor's twin and wears the editor's labels, so its rows are
  /// told apart from the editor's by id — the editor's `event-…` as
  /// `template-…`.
  static const String templateClose = 'template-close';
  static const String templateSave = 'template-save';
  static const String templateName = 'template-name';
  static const String templateCategory = 'template-category';
  static const String templateLook = 'template-look';
  static const String templateDescription = 'template-description';
  static const String templateAllDay = 'template-all-day';
  static const String templateStarts = 'template-starts';
  static const String templateEnds = 'template-ends';
  static const String templateEndsClear = 'template-ends-clear';
  static const String templateRepeat = 'template-repeat';
  static const String templateCount = 'template-count';
  static const String templateCountStyleNumbered =
      'template-count-style-numbered';
  static const String templateCountStyleElapsed =
      'template-count-style-elapsed';
  static const String templatePresence = 'template-presence';
  static const String templateAssumePresent = 'template-assume-present';
  static const String templateAssumeAbsent = 'template-assume-absent';
  static const String templatePerDay = 'template-per-day';
  static const String templatePriority = 'template-priority';
  static String templatePriorityItem(int priority) =>
      'template-priority-$priority';

  /// The agenda day list (Tier 3, `docs/calendar-language-tier-3-roadmap.md`):
  /// its ✕ and the ← that replaces it under a drilled month, the mode chips,
  /// the year-scope chips, a picked day's "Whole month" ✕, the scrolling
  /// body, and the navigation row's four controls — one set, since the month
  /// nav and the year nav never share a screen. "Previous month" and "This
  /// year" repeat across surfaces, so none of them is a label a flow can use.
  static const String dayListClose = 'day-list-close';
  static const String dayListBack = 'day-list-back';
  static const String dayListModeList = 'day-list-mode-list';
  static const String dayListModeMonth = 'day-list-mode-month';
  static const String dayListModeYear = 'day-list-mode-year';
  static const String dayListScopeUpcoming = 'day-list-scope-upcoming';
  static const String dayListScopeCalendarYear = 'day-list-scope-calendar-year';
  static const String dayListWholeMonth = 'day-list-whole-month';
  static const String dayListBody = 'day-list-body';
  static const String dayListNavPrevious = 'day-list-nav-previous';
  static const String dayListNavNext = 'day-list-nav-next';
  static const String dayListNavToday = 'day-list-nav-today';
  static const String dayListNavTitle = 'day-list-nav-title';

  /// The calendar overview (`docs/calendar-overview-list-roadmap.md` §3.10):
  /// the mode chips (§3.11) and the search button ending their row, the
  /// summoned search row, the list options sheet and its rows (the
  /// categories row among them since §3.13), the nav — its title opens the
  /// period menu, whose items are `overview-period-*` — the list, the
  /// scrubber, and one id per row — a title repeats down a list of
  /// occurrences, so a flow taps a row by event and day, or by event alone
  /// under "One per event".
  static const String overviewViewYear = 'overview-view-year';
  static const String overviewViewMonth = 'overview-view-month';
  static const String overviewViewList = 'overview-view-list';
  static const String overviewSearchOpen = 'overview-search-open';
  static const String overviewOptionsOpen = 'overview-options-open';
  static const String overviewOptionsClose = 'overview-options-close';
  static const String overviewOrder = 'overview-order';
  static const String overviewOrderOldest = 'overview-order-oldest';
  static const String overviewOrderNewest = 'overview-order-newest';
  static const String overviewRows = 'overview-rows';
  static const String overviewRowsEvery = 'overview-rows-every';
  static const String overviewRowsPerEvent = 'overview-rows-per-event';
  static const String overviewMissedOnly = 'overview-missed-only';
  static const String overviewSearch = 'overview-search';
  static const String overviewCategories = 'overview-categories';
  static const String overviewPeriodThisWeek = 'overview-period-this-week';
  static const String overviewPeriodThisMonth = 'overview-period-this-month';
  static const String overviewPeriodThisYear = 'overview-period-this-year';
  static const String overviewPeriodLast12Months =
      'overview-period-last-12-months';
  static const String overviewPeriodLast90Days = 'overview-period-last-90-days';
  static const String overviewPeriodAllTime = 'overview-period-all-time';
  static const String overviewPeriodCustom = 'overview-period-custom';
  static const String overviewNavPrevious = 'overview-nav-previous';
  static const String overviewNavNext = 'overview-nav-next';
  static const String overviewNavToday = 'overview-nav-today';
  static const String overviewNavTitle = 'overview-nav-title';
  static const String overviewList = 'overview-list';
  static const String overviewWholeMonth = 'overview-whole-month';
  static const String overviewScrubber = 'overview-scrubber';
  static String overviewRow(String eventId, DateTime day) =>
      'overview-row-$eventId-${_isoDate(day)}';

  /// A day row's presence button (2026-10-17), the [overviewRow] twin: a
  /// node beside the row's, whose tooltip changes with the state.
  static String overviewRowPresence(String eventId, DateTime day) =>
      'overview-row-presence-$eventId-${_isoDate(day)}';

  static String overviewEventRow(String eventId) => 'overview-event-$eventId';

  /// Year mode's continuous scroll (§3.14): the scroll view, and one header
  /// per year section, the node that names the year and its count, so a
  /// flow can wait on a year having scrolled into view.
  static const String overviewYears = 'overview-years';
  static String overviewYearHeader(int year) => 'overview-year-$year';

  /// The overview's saved views (§3.12, D17): the bar button, the sheet's
  /// chrome and one row per view with its handle and its ⋮ menu. A view's id
  /// is a UUID, so `overview-view-<id>` never meets the mode chips' names.
  static const String overviewViewsOpen = 'overview-views-open';
  static const String overviewViewsClose = 'overview-views-close';
  static const String overviewViewsSearch = 'overview-views-search';
  static const String overviewViewsSave = 'overview-views-save';
  static String overviewViewRow(String id) => 'overview-view-$id';
  static String overviewViewOptions(String id) => 'overview-view-options-$id';
  static String overviewViewHandle(String id) => 'overview-view-handle-$id';
  static const String overviewViewsRename = 'overview-views-rename';
  static const String overviewViewsUpdate = 'overview-views-update';
  static const String overviewViewsMoveTop = 'overview-views-move-top';
  static const String overviewViewsDelete = 'overview-views-delete';

  /// The "Show every day" button of an agenda summary card, keyed by the
  /// card's summary key (`category:<id>`, `holiday`, `fasting:<tradition>`)
  /// with its colon folded: every card's button wears the same tooltip, and
  /// a flow has to open one card among several.
  static String agendaCardDays(String key) =>
      'agenda-card-days-${key.replaceAll(':', '-')}';

  /// The category editor's ✕ and Save, its name field and its Icon row.
  static const String categoryEditorClose = 'category-editor-close';
  static const String categoryEditorSave = 'category-editor-save';
  static const String categoryEditorName = 'category-editor-name';
  static const String categoryEditorIcon = 'category-editor-icon';

  /// The category editor's body scroll view, a container id like
  /// [eventForm]: the profile rows sit below the fold since S3, and a flow
  /// scrolls to them inside it.
  static const String categoryEditorForm = 'category-editor-form';

  /// The category editor's profile rows (analytics S3): Report's Kind, Mark
  /// and Area, Measure & goal's Measure, Counts as and Goal.
  static const String categoryEditorKind = 'category-editor-kind';
  static const String categoryEditorMark = 'category-editor-mark';
  static const String categoryEditorArea = 'category-editor-area';
  static const String categoryEditorMeasure = 'category-editor-measure';
  static const String categoryEditorCountsAs = 'category-editor-counts-as';
  static const String categoryEditorGoal = 'category-editor-goal';

  /// The Mark menu's items — the kind's verb, the owner's word (or "Own
  /// word…"), Off — and its word dialog's field and Save.
  static const String categoryMarkKind = 'category-mark-kind';
  static const String categoryMarkOwn = 'category-mark-own';
  static const String categoryMarkOff = 'category-mark-off';
  static const String categoryMarkWordField = 'category-mark-word-field';
  static const String categoryMarkWordSave = 'category-mark-word-save';

  /// The Area menu's items, by `LifeArea` name.
  static String categoryArea(String area) => 'category-area-$area';

  /// The Measure menu's Auto and its measures, by `ReportMeasure` name.
  static const String categoryMeasureAuto = 'category-measure-auto';
  static String categoryMeasure(String measure) => 'category-measure-$measure';

  /// The Counts as menu's Off and its durations, by minutes.
  static const String categoryCountsAsOff = 'category-counts-as-off';
  static String categoryCountsAs(int minutes) => 'category-counts-as-$minutes';

  /// The kind picker's ✕, its body scroll view and its rows, by
  /// `CategoryKind` name.
  static const String categoryKindClose = 'category-kind-close';
  static const String categoryKindList = 'category-kind-list';
  static String categoryKind(String kind) => 'category-kind-$kind';

  /// The goal sheet's ✕ and Done, its type rows by `TargetKind` name, the
  /// value's stepper and field, its period chips by `TargetPeriod` name and
  /// Remove goal.
  static const String categoryGoalClose = 'category-goal-close';
  static const String categoryGoalDone = 'category-goal-done';
  static String categoryGoalType(String kind) => 'category-goal-type-$kind';
  static const String categoryGoalLess = 'category-goal-less';
  static const String categoryGoalMore = 'category-goal-more';
  static const String categoryGoalValue = 'category-goal-value';
  static String categoryGoalPeriod(String period) =>
      'category-goal-period-$period';
  static const String categoryGoalRemove = 'category-goal-remove';

  /// The Categories page's create button and each category's row, keyed by
  /// the category's id — a container above the row's own buttons.
  static const String categoryAdd = 'category-add';
  static String categoryRow(String id) => 'category-row-$id';

  /// The Categories page bar's ⋮, and its item that sorts every category A–Z.
  static const String categoryBarMenu = 'category-bar-menu';
  static const String categorySortAz = 'category-sort-az';

  /// The Categories page's search field, drawn above 12 categories.
  static const String categorySearch = 'category-search';

  /// The Categories page's two section headers: a flow reads which section a
  /// row landed in from the order of the dump (`expect --ordered`).
  static const String categorySectionInUseHeader = 'category-section-in-use';
  static const String categorySectionArchivedHeader =
      'category-section-archived';

  /// A category row's ⋮, keyed by the category's id: every row's button wears
  /// the same tooltip.
  static String categoryRowMenu(String id) => 'category-menu-$id';

  /// A category row's ⋮ item that moves the category to the top of the order.
  static const String categoryMenuMoveToTop = 'category-menu-move-to-top';

  /// A category row's ⋮ item that opens the category editor.
  static const String categoryMenuEdit = 'category-menu-edit';

  /// A category row's ⋮ item that archives or restores the category. Named
  /// for Archive, the action's name once the page is reworked, so a flow
  /// keeps its target across the rename.
  static const String categoryMenuArchive = 'category-menu-archive';

  /// A category row's ⋮ item that deletes a custom category.
  static const String categoryMenuDelete = 'category-menu-delete';

  /// The delete sheet's ✕, its Move events to row and its Delete.
  static const String categoryDeleteClose = 'category-delete-close';
  static const String categoryDeleteTarget = 'category-delete-target';
  static const String categoryDeleteConfirm = 'category-delete-confirm';

  /// The colour strip wherever a sheet embeds it: the row as a container
  /// above the swatches' own nodes (the Look sheet's keeps [lookColor]), the
  /// three dots whose tooltips change with the locale, and the three items
  /// of a custom swatch's long-press menu. A swatch itself is found by the
  /// hex it announces.
  static const String swatchRow = 'swatch-row';
  static const String swatchDefault = 'swatch-default';
  static const String swatchAdd = 'swatch-add';
  static const String swatchManage = 'swatch-manage';

  /// The collapsed strip's "Show N more colors" dot, whose count changes
  /// with the palette and the width.
  static const String swatchShowAll = 'swatch-show-all';
  static const String swatchMenuEdit = 'swatch-menu-edit';
  static const String swatchMenuDelete = 'swatch-menu-delete';
  static const String swatchMenuManage = 'swatch-menu-manage';

  /// The fasting schedule's ✕, its weekday chips (ISO 1–7) and month chips
  /// (1–12), the Select all / None rows under each, the weekday scope pair,
  /// the two exception rows, and each exception date's remove button keyed by
  /// the list it is in (`skip` or `force`) and the date.
  static const String fastingScheduleClose = 'fasting-schedule-close';
  static String fastingWeekday(int weekday) => 'fasting-weekday-$weekday';
  static const String fastingWeekdaysAll = 'fasting-weekdays-all';
  static const String fastingWeekdaysNone = 'fasting-weekdays-none';
  static const String fastingWeekdayScopeWeekly =
      'fasting-weekday-scope-weekly';
  static const String fastingWeekdayScopeAll = 'fasting-weekday-scope-all';
  static String fastingMonth(int month) => 'fasting-month-$month';
  static const String fastingMonthsAll = 'fasting-months-all';
  static const String fastingMonthsNone = 'fasting-months-none';
  static const String fastingDaysOff = 'fasting-days-off';
  static const String fastingExtraDays = 'fasting-extra-days';
  static String fastingDateRemove(String kind, DateTime date) =>
      'fasting-$kind-remove-${_isoDate(date)}';

  /// The fasting style's ✕, its two menu rows with their items, the Icon
  /// row and its reset, the Custom title row and its clear, and the
  /// Description row.
  static const String fastingStyleClose = 'fasting-style-close';
  static const String fastingStyleGrid = 'fasting-style-grid';
  static const String fastingStyleGridTint = 'fasting-style-grid-tint';
  static const String fastingStyleGridBar = 'fasting-style-grid-bar';
  static const String fastingStyleGridStrong = 'fasting-style-grid-strong';
  static const String fastingStyleGridNone = 'fasting-style-grid-none';
  static const String fastingStylePlacement = 'fasting-style-placement';
  static const String fastingStylePlacementFirst =
      'fasting-style-placement-first';
  static const String fastingStylePlacementBeforeHolidays =
      'fasting-style-placement-before-holidays';
  static const String fastingStylePlacementAfterHolidays =
      'fasting-style-placement-after-holidays';
  static const String fastingStylePlacementLast =
      'fasting-style-placement-last';
  static const String fastingStyleIcon = 'fasting-style-icon';
  static const String fastingStyleIconReset = 'fasting-style-icon-reset';
  static const String fastingStyleTitle = 'fasting-style-title';
  static const String fastingStyleTitleClear = 'fasting-style-title-clear';
  static const String fastingStyleDescription = 'fasting-style-description';

  /// The removed-holidays sheet's ✕ and each row's Restore, keyed by the
  /// holiday's name key and the date it was removed on.
  static const String removedHolidaysClose = 'removed-holidays-close';
  static String holidayRestoreButton(String nameKey, DateTime date) =>
      'holiday-restore-$nameKey-${_isoDate(date)}';

  /// The palette's ✕, its Add color and Reset colors rows, and each custom
  /// colour's row, handle and delete, keyed by the colour's six hex digits —
  /// what `CalendarPalette.hexOf` prints, its `#` dropped and lower-cased.
  static const String paletteClose = 'palette-close';
  static const String paletteAdd = 'palette-add';
  static const String paletteReset = 'palette-reset';
  static String paletteRow(String hex) => 'palette-row-${_hexKey(hex)}';
  static String paletteHandle(String hex) => 'palette-handle-${_hexKey(hex)}';
  static String paletteDelete(String hex) => 'palette-delete-${_hexKey(hex)}';

  /// The colour picker's ✕ and Select, its two geometry chips, the hex field
  /// and the copy button.
  static const String colorPickerClose = 'color-picker-close';
  static const String colorPickerSelect = 'color-picker-select';
  static const String colorModeSquare = 'color-mode-square';
  static const String colorModeWheel = 'color-mode-wheel';
  static const String colorHex = 'color-hex';
  static const String colorCopyHex = 'color-copy-hex';

  /// `yyyy-MM-dd` by hand: an id is a contract with the driver and never
  /// follows the locale a formatter would.
  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _hexKey(String hex) => hex.replaceFirst('#', '').toLowerCase();

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

  /// The calendar report (`docs/calendar-report-roadmap.md` §4.8): the bar's
  /// Categories button and ⋮, the band's nav, the Period menu's rows, the
  /// body, the Totals tiles and the footer rows.
  static const String reportCategoriesOpen = 'report-categories-open';
  static const String reportMore = 'report-more';
  static const String reportNavPrevious = 'report-nav-previous';
  static const String reportNavNext = 'report-nav-next';
  static const String reportNavToday = 'report-nav-today';
  static const String reportNavTitle = 'report-nav-title';
  static const String reportPeriodThisWeek = 'report-period-this-week';
  static const String reportPeriodLastWeek = 'report-period-last-week';
  static const String reportPeriodNextWeek = 'report-period-next-week';
  static const String reportPeriodThisMonth = 'report-period-this-month';
  static const String reportPeriodLastMonth = 'report-period-last-month';
  static const String reportPeriodNextMonth = 'report-period-next-month';
  static const String reportPeriodThisYear = 'report-period-this-year';
  static const String reportPeriodLastYear = 'report-period-last-year';
  static const String reportPeriodLast12Months = 'report-period-last-12-months';
  static const String reportPeriodLast90Days = 'report-period-last-90-days';
  static const String reportPeriodCustom = 'report-period-custom';
  static const String reportBody = 'report-body';

  /// A Totals tile, by its `ReportTile` name: `report-tile-events`,
  /// `-attended`, `-missed`, `-hours`, `-tasks`, `-planned`.
  static String reportTile(String tile) => 'report-tile-$tile';

  /// The Over time card, one node with the chart's spoken summary.
  static const String reportTrend = 'report-trend';
  static const String reportShowList = 'report-show-list';
  static const String reportShare = 'report-share';
  static const String reportSend = 'report-send';

  /// A Goals card row, by its category: a category carries one target, so
  /// the category names the row.
  static String reportGoal(String categoryId) => 'report-goal-$categoryId';

  /// An Insights card row, by its rank on the page (0 first): the ranking
  /// is deterministic, so a flow taps the same insight for the same data.
  static String reportInsight(int rank) => 'report-insight-$rank';

  /// A Due soon row, the [reportRow] shape: an event can be due on more
  /// than one day of a span, so the day is part of the id.
  static String reportDue(String eventId, DateTime day) =>
      'report-due-$eventId-${_isoDate(day)}';

  /// The Due soon card's disclosure row, one id whether it reads "n more"
  /// or "Show less".
  static const String reportDueMore = 'report-due-more';

  /// A category group's header, by its card's `ReportCard` name:
  /// `report-group-categories-<categoryId>`, `-missed-…`, `-ahead-…` — one
  /// category heads a group in each card, so the card is part of the id.
  static String reportGroup(String card, String categoryId) =>
      'report-group-$card-$categoryId';

  /// A group's disclosure row, one id whether it reads "n more" or "Show
  /// less", so a flow taps the same target both ways.
  static String reportGroupMore(String card, String categoryId) =>
      'report-group-more-$card-$categoryId';

  /// A group's "Show as list" row, under an expansion capped at
  /// `ReportMetrics.maxListRows`; its own id beside [reportGroupMore], since
  /// both rows stand under one capped group.
  static String reportGroupList(String card, String categoryId) =>
      'report-group-list-$card-$categoryId';

  /// The "n more categories" row under the Categories card, past
  /// `ReportMetrics.maxCategoryRows` groups; one per page.
  static const String reportCategoriesMore = 'report-categories-more';

  /// The "n more categories" sheet's ✕, which closes it with nothing picked.
  static const String reportMoreClose = 'report-more-close';

  /// The "n more categories" sheet's one scroll of the remaining groups;
  /// its groups carry the page's [reportGroup] ids.
  static const String reportMoreList = 'report-more-list';

  /// A routine's aggregate row; one per event in a card.
  static String reportRoutine(String eventId) => 'report-routine-$eventId';

  /// A dated row, the [overviewRow] shape.
  static String reportRow(String eventId, DateTime day) =>
      'report-row-$eventId-${_isoDate(day)}';

  /// A Missed row's presence button, a node beside the [reportRow].
  static String reportRowPresence(String eventId, DateTime day) =>
      'report-row-presence-$eventId-${_isoDate(day)}';

  /// A By tag header, by the tag's lower-cased key without `#`.
  static String reportTag(String key) => 'report-tag-$key';

  /// A tag's disclosure row, one id whether it reads "n more" or "Show
  /// less", the [reportGroupMore] shape.
  static String reportTagMore(String key) => 'report-tag-more-$key';

  /// A tag's "Show as list" row, the [reportGroupList] shape.
  static String reportTagList(String key) => 'report-tag-list-$key';

  /// A dated row under an open tag: its own prefix beside [reportRow],
  /// because the same occurrence can stand in a Categories group too.
  static String reportTagRow(String key, String eventId, DateTime day) =>
      'report-tag-row-$key-$eventId-${_isoDate(day)}';

  /// The By tag card's "n more" row, past `ReportMetrics.groupPreviewRows`
  /// tags; one per page.
  static const String reportTagsMore = 'report-tags-more';

  /// The When card, one node with the heatmap's spoken summary.
  static const String reportWhen = 'report-when';

  /// A Balance row, by its `LifeArea` name: `report-balance-work`, …
  static String reportBalance(String area) => 'report-balance-$area';

  /// A whole year's Records row of one record a year (S6 §2.7), by its kind
  /// in kebab case: `report-year-record-busiest-month`, `-busiest-week`,
  /// `-social-month`, `-money-month`, `-longest-trip`.
  static String reportYearRecord(String kind) => 'report-year-record-$kind';

  /// A Records streak row, by its event: a year holds one per routine.
  static String reportYearRecordStreak(String eventId) =>
      'report-year-record-streak-$eventId';

  /// A Records gap row, by its category: a year holds one per gap goal.
  static String reportYearRecordGap(String categoryId) =>
      'report-year-record-gap-$categoryId';

  /// The Records card's "n more" row, past `ReportMetrics.yearRecordRows`.
  static const String reportYearRecordsMore = 'report-year-records-more';

  /// A Months strip row, by its category.
  static String reportYearMonths(String categoryId) =>
      'report-year-months-$categoryId';

  /// The Months card's "n more" row, past its seventh category.
  static const String reportYearMonthsMore = 'report-year-months-more';

  /// The footer's Compare with row and its menu items; a saved view's item
  /// by the view's id, and the one disabled item shown with no saved view.
  static const String reportCompare = 'report-compare';
  static const String reportComparePrevious = 'report-compare-previous';
  static const String reportCompareLastYear = 'report-compare-last-year';
  static String reportCompareView(String viewId) =>
      'report-compare-view-$viewId';
  static const String reportCompareNone = 'report-compare-none';

  /// A tile of the compared view's Totals card, by its `ReportTile` name:
  /// its own prefix, so the page's [reportTile] ids stay unique.
  static String reportViewTile(String tile) => 'report-view-tile-$tile';

  static const String permissionsPromptContinue = 'permissions-prompt-continue';
  static const String permissionsPromptNotNow = 'permissions-prompt-not-now';
}
