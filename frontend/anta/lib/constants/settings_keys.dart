class SettingsKeys {
  // Onboarding
  static const String onboardingCompleted = 'onboarding_completed';

  // Font settings
  static const String previewFontSize = 'preview_font_size';
  static const String editorFontSize = 'editor_font_size';

  // App settings (from app_settings_bloc)
  static const String locale = 'locale';
  static const String themeMode = 'theme_mode';

  // Date settings
  static const String dateFormat = 'date_format';
  static const String defaultDateFormat = 'MMMM d, yyyy';

  // Markdown settings
  static const String markdownShortcuts = 'markdown_shortcuts';
  static const String customShortcuts = 'custom_shortcuts';

  // Control settings (migrated from SharedPreferences)
  static const String folderSwipeEnabled = 'folder_swipe_enabled';
  static const String noteSwipeEnabled = 'note_swipe_enabled';
  static const String confirmDelete = 'confirm_delete';
  static const String autoSaveEnabled = 'auto_save_enabled';
  static const String autoSaveInterval = 'auto_save_interval';
  static const String showNotePreview = 'show_note_preview';

  /// How a labelled row draws its colour (a `LabelStyle` name) — the trailing
  /// dot or the leading edge stripe. Rendering only: it changes nothing about
  /// what a label is or how it is stored.
  static const String labelStyle = 'label_style';
  static const String defaultLabelStyle = 'dot';

  static const String showStatsBar = 'show_stats_bar';
  static const String defaultNotesSortOrder = 'default_notes_sort_order';
  static const String hapticFeedback = 'haptic_feedback';

  // Editor settings
  static const String liveMarkdownRendering = 'live_markdown_rendering';
  static const String showLineNumbers = 'show_line_numbers';
  static const String wordWrap = 'word_wrap';
  static const String showCursorLine = 'show_cursor_line';
  static const String autoBreakLongLines = 'auto_break_long_lines';
  static const String previewWhenKeyboardHidden =
      'preview_when_keyboard_hidden';
  static const String scrollCursorOnKeyboard = 'scroll_cursor_on_keyboard';
  static const String previewModeEnabled = 'preview_mode_enabled';

  // Vocabulary autocomplete settings
  static const String vocabularySuggestionsEnabled =
      'vocabulary_suggestions_enabled';
  static const String vocabularyTriggerChar = 'vocabulary_trigger_char';

  // Money ledger settings
  /// Master switch for the `$`-prefixed money ledger syntax. Off by
  /// default — the toolbar shortcuts still insert their text, but `$`
  /// lines render as plain text on both surfaces and the calendar
  /// summary stays empty until this is enabled.
  static const String moneyLedgerEnabled = 'money_ledger_enabled';
  static const String moneyStartCents = 'money_start_cents';
  static const String moneyCurrencySymbol = 'money_currency_symbol';
  static const String moneyCurrencySuffix = 'money_currency_suffix';

  /// Prefix for per-note currency overrides: `money_note_currency_<noteId>`
  /// stores `symbol` or `symbol|suffix`; absent = inherit the global
  /// currency (mirrors the `note_bar_<noteId>` override precedent).
  static const String moneyNoteCurrencyPrefix = 'money_note_currency_';

  // Markdown colour settings
  /// User-defined colours for `{name:text}` and `==name:text==`, stored
  /// as `name=aarrggbb;name=aarrggbb`. Absent/empty means presets only.
  /// Decoded by `MarkdownColorPalette.decode`.
  static const String markdownCustomColors = 'markdown_custom_colors';

  // Preview settings
  static const String showPreviewScrollbar = 'show_preview_scrollbar';

  /// Comma-separated ids of the markdown settings sections the user left
  /// folded. Stores the *collapsed* set so the empty default keeps every
  /// section open, exactly as before the state was persisted.
  static const String markdownSectionsCollapsed = 'markdown_sections_collapsed';

  // Toolbar settings
  static const String toolbarShortcutRatio = 'toolbar_shortcut_ratio';
  static const String toolbarSplitEnabled = 'toolbar_split_enabled';
  static const String toolbarUtilityConfig = 'toolbar_utility_config';

  // Preview performance settings
  static const String previewLinesPerChunk = 'preview_lines_per_chunk';

  // Calendar settings
  static const String calendarMaxDayBars = 'calendar_max_day_bars';
  static const String holidayProfile = 'holiday_profile';

  /// Maximum characters allowed in an event description. Enforced by the
  /// editor sheet's save guard, not by truncation — a description is markdown
  /// the user typed, so going over blocks Save and says so rather than
  /// silently dropping the tail.
  static const String eventDescriptionLimit = 'event_description_limit';

  // Calendar appearance settings
  static const String calendarTodayStyle = 'calendar_today_style';
  static const String calendarMarkerStyle = 'calendar_marker_style';
  static const String calendarWeekStart = 'calendar_week_start';

  /// Explicit ARGB accent for today/selected highlights. Empty/absent means
  /// "follow the theme's primary color".
  static const String calendarAccentColor = 'calendar_accent_color';
  static const String calendarHighlightWeekends = 'calendar_highlight_weekends';
  static const String calendarShowWeekNumbers = 'calendar_show_week_numbers';

  /// Whether the removable filter chips row is drawn above the grid while a
  /// grid filter is active.
  static const String calendarShowFilterChips = 'calendar_show_filter_chips';

  /// Recently used custom event colors (comma-separated ARGB ints,
  /// most-recent-first). **Retired** in favour of [calendarCustomColors]:
  /// `CalendarPaletteService` reads it once to fold the colors a user had
  /// already reached for into the permanent palette, then clears it. Never
  /// written again.
  static const String recentEventColors = 'recent_event_colors';

  /// The user's own calendar swatches (comma-separated ARGB ints, in the
  /// order they were added). Rendered after the built-in swatches on every
  /// colour surface; built-ins are never stored here, so a change to
  /// `CalendarColors.swatchPalette` still reaches existing installs.
  static const String calendarCustomColors = 'calendar_custom_colors';

  /// Which window the upcoming agenda covers (`AgendaPeriodMode` name):
  /// rollingDays / wholeYear / restOfYear. Parsed with a forward-compatible
  /// fallback to `rollingDays`, which is what [calendarUpcomingRangeDays]
  /// alone used to mean.
  static const String calendarUpcomingPeriodMode =
      'calendar_upcoming_period_mode';

  /// Last look-ahead window (in days) used in the upcoming events sheet.
  /// Applies only while [calendarUpcomingPeriodMode] is `rollingDays`.
  static const String calendarUpcomingRangeDays =
      'calendar_upcoming_range_days';

  /// Priorities selected in the upcoming agenda, as a sorted CSV on the
  /// 1-is-highest scale. An empty value means "all priorities"; an absent
  /// key means "never set". (A superseded `calendar_upcoming_min_priority`
  /// threshold key is folded into this one by the v18 migration.)
  static const String calendarUpcomingPriorities =
      'calendar_upcoming_priorities';

  /// Explicit agenda date range as `yyyyMMdd|yyyyMMdd`, empty when the
  /// preset look-ahead window is in use.
  static const String calendarUpcomingCustomRange =
      'calendar_upcoming_custom_range';

  /// Last search text typed in the upcoming agenda.
  static const String calendarUpcomingQuery = 'calendar_upcoming_query';

  /// Whether the upcoming agenda lists public holidays alongside events.
  static const String calendarUpcomingShowHolidays =
      'calendar_upcoming_show_holidays';

  /// Whether the upcoming agenda lists configured fasting days alongside
  /// events.
  static const String calendarUpcomingShowFasting =
      'calendar_upcoming_show_fasting';

  /// How the upcoming agenda presents events (`AgendaEventDisplay` name):
  /// everyOccurrence / perEvent / summary. Parsed with a forward-compatible
  /// fallback to `everyOccurrence`.
  static const String calendarUpcomingEventDisplay =
      'calendar_upcoming_event_display';

  /// **Legacy, read-only.** Superseded by [calendarUpcomingEventDisplay]; read
  /// only when that key is absent, mapping `true` to `perEvent` and `false` to
  /// `everyOccurrence` so nobody's configuration resets on update. Never
  /// written again.
  static const String calendarUpcomingCollapseRecurring =
      'calendar_upcoming_collapse_recurring';

  /// How the upcoming agenda presents fasting days (`AgendaFastingDisplay`
  /// name): everyDay / periods / summary. Parsed with a forward-compatible
  /// fallback to `periods`.
  static const String calendarUpcomingFastingDisplay =
      'calendar_upcoming_fasting_display';

  /// **Legacy, read-only.** Superseded by [calendarUpcomingFastingDisplay];
  /// read only when that key is absent, mapping `true` to `periods` and
  /// `false` to `everyDay` so nobody's configuration resets on update. Never
  /// written again.
  static const String calendarUpcomingCollapseFasting =
      'calendar_upcoming_collapse_fasting';

  /// How the upcoming agenda presents public holidays (`AgendaHolidayDisplay`
  /// name): everyDay / summary. Parsed with a forward-compatible fallback to
  /// `everyDay`. A new axis rather than a replacement, so unlike
  /// [calendarUpcomingFastingDisplay] it has no legacy key to fall back on.
  static const String calendarUpcomingHolidayDisplay =
      'calendar_upcoming_holiday_display';

  /// Whether the upcoming agenda's window restarts from the calendar's
  /// selected day instead of always starting today.
  static const String calendarUpcomingFollowSelectedDay =
      'calendar_upcoming_follow_selected_day';

  /// Which events the upcoming agenda lists (`AgendaEventType` name):
  /// all / recurring / oneTime / none. Parsed with a forward-compatible
  /// fallback to `all`.
  static const String calendarUpcomingEventType =
      'calendar_upcoming_event_type';

  /// Category-id allowlist for the upcoming agenda, as a sorted CSV. Empty =
  /// every category (the filter off).
  static const String calendarUpcomingCategories =
      'calendar_upcoming_categories';

  /// Which mode the calendar's bottom panel was left in (day / timeline /
  /// upcoming). Parsed with a forward-compatible fallback.
  static const String calendarPanelMode = 'calendar_panel_mode';

  /// Which presentation the agenda summary cards' drill-down sheet was left in
  /// (`AgendaDayListMode` name): list / month / year. Parsed with a
  /// forward-compatible fallback to `list`.
  static const String calendarDayListMode = 'calendar_day_list_mode';

  /// Category-id allowlist of the calendar overview page, as a sorted CSV.
  /// Empty = every category.
  static const String calendarOverviewCategories =
      'calendar_overview_categories';

  /// Which presentation the calendar overview page was left in
  /// (`AgendaDayListMode` name). Parsed with a forward-compatible fallback to
  /// [defaultCalendarOverviewMode].
  static const String calendarOverviewMode = 'calendar_overview_mode';

  /// Whether day-panel / agenda event rows mention the repeat pattern
  /// ("Daily", "Every 2 weeks", …) in their subtitle.
  static const String calendarShowRecurrenceLabels =
      'calendar_show_recurrence_labels';

  /// How occurrences marked as missed are drawn (`faded` / `hidden`). Parsed
  /// with a forward-compatible fallback by `CalendarMissedDisplay.fromName`.
  static const String calendarMissedDisplay = 'calendar_missed_display';

  /// Wash each day cell with its top event's colour, at a strength set by
  /// that event's priority.
  static const String calendarEventTint = 'calendar_event_tint';

  /// Which tint source wins a day that carries more than one (`eventWins` /
  /// `fastingWins` / `both`). Parsed with a forward-compatible fallback by
  /// `CalendarTintConflict.fromName`.
  static const String calendarTintConflict = 'calendar_tint_conflict';

  /// How the resolved day-cell wash is painted in the **light** theme
  /// (`solid` / `fade` / `outline`). Parsed with a forward-compatible
  /// fallback by `CalendarCellStyle.fromName`. Its own key per theme because
  /// one alpha does not read the same on a near-white and a near-black
  /// ground.
  static const String calendarCellStyleLight = 'calendar_cell_style_light';

  /// How the resolved day-cell wash is painted in the **dark** theme
  /// (`solid` / `fade` / `outline`). See [calendarCellStyleLight].
  static const String calendarCellStyleDark = 'calendar_cell_style_dark';

  /// How the left-edge day rail is drawn (`none` / `line` / `dot`). Parsed
  /// with a forward-compatible fallback by `DayRailStyle.fromName`.
  static const String calendarDayRailStyle = 'calendar_day_rail_style';

  /// Maximum rail marks per day cell before the neutral overflow mark. Its
  /// own key rather than a share of [calendarMaxDayBars]: different geometry,
  /// different capacity, different content.
  static const String calendarMaxDayRailMarks = 'calendar_max_day_rail_marks';

  /// Which end of the `line` rail the tint runner-up's band takes (`bottom` /
  /// `top`). Parsed with a forward-compatible fallback by
  /// `DayRailBasePosition.fromName`.
  static const String calendarDayRailBasePosition =
      'calendar_day_rail_base_position';

  /// JSON blob holding the calendar grid's filter set (`CalendarGridFilters`),
  /// one key rather than fifteen rows — the shape
  /// [calendarFastingSchedule] already uses for a compound setting. Only
  /// non-default fields are written, so an absent field reads as its default
  /// and a build that adds an axis still understands an older blob. Absent or
  /// malformed decodes to "nothing filtered".
  static const String calendarGridFilters = 'calendar_grid_filters';

  /// CSV of enabled [FastingTradition] names ('' or absent = fasting off).
  /// Unknown names are dropped on read for forward compatibility.
  static const String calendarFastingTraditions = 'calendar_fasting_traditions';

  /// Retired single global [FastingDisplayStyle]; still **read** as the seed
  /// for [calendarFastingAppearance] when the latter is absent, so an
  /// install that only ever had the global style keeps its look.
  static const String calendarFastingStyle = 'calendar_fasting_style';

  /// Per-tradition fasting look & feel, encoded by `FastingAppearance` as a
  /// JSON object keyed by tradition name (the retired
  /// `tradition:style|argb|iconKey|placement;…` form is still readable).
  /// Unknown traditions and malformed fields degrade to defaults on read.
  static const String calendarFastingAppearance = 'calendar_fasting_appearance';

  /// Whether the Orthodox multi-day fasts (plus strict single days and
  /// Cheesefare) are computed, or only the weekly fast days.
  static const String calendarFastingOrthodoxGreatFasts =
      'calendar_fasting_orthodox_great_fasts';

  /// Retired CSV of `DateTime.weekday` ints (1=Mon..7=Sun) for the weekly
  /// fast; still **read** as the seed for [calendarFastingSchedule] when the
  /// latter is absent, so an install that only ever picked weekdays keeps
  /// them. Absent = the traditional Wednesday+Friday; '' = the user cleared
  /// them all, and the two must stay distinguishable.
  static const String calendarFastingWeekdays = 'calendar_fasting_weekdays';

  /// The personal fasting practice — weekly days, the months kept, what a
  /// disabled month suppresses, and exception dates — encoded by
  /// `FastingSchedule` as a JSON object. Malformed fields degrade to their
  /// defaults on read; an absent key falls back to [calendarFastingWeekdays].
  static const String calendarFastingSchedule = 'calendar_fasting_schedule';

  /// The icon keys picked most recently, newest first, as a CSV. Backs the
  /// icon picker's "Recently used" section — the thing that keeps a catalog
  /// of hundreds feeling small. Icon keys never contain a comma, and unknown
  /// keys are dropped on read, so a retired icon simply stops appearing.
  static const String recentIconKeys = 'recent_icon_keys';

  /// The navigation stack the user was looking at, bottom-to-top, encoded by
  /// `NavDestination.encodeStack`. Replayed on the next cold launch so the app
  /// reopens where it left off — folders, notes, the calendar and its
  /// sub-pages, and the drawer's settings pages alike.
  ///
  /// Lives in `user_settings`, so each local database remembers its own place
  /// across the restart a database switch prompts.
  static const String lastLocationStack = 'last_location_stack';

  /// How much of [lastLocationStack] to replay: `off`, `notes`, or
  /// `everything` (the default), parsed by `RestoreLocationMode.fromName`.
  /// Filters at replay only — recording never stops, so turning restore back
  /// on takes effect immediately rather than after the next navigation.
  static const String restoreLocationMode = 'restore_location_mode';

  /// Retired in favour of [lastLocationStack], which can express a chain of
  /// any depth instead of one folder plus one note. Kept only so
  /// `SettingsService` can migrate an existing install's value on first read
  /// and then delete these rows; nothing writes them any more.
  static const String lastFolderId = 'last_folder_id';
  static const String lastFolderTitle = 'last_folder_title';
  static const String lastNoteId = 'last_note_id';

  // Note position (prefix for per-note storage)
  static const String notePositionPrefix = 'note_position_';

  // Cloud sync pairing (Phase 01). These live in `user_settings`, so pairing
  // is per-database by construction — and they are deliberately absent from
  // `BackupService._exportSettings`: restoring a backup onto a third device
  // must not clone a pair membership.
  static const String pairingPairId = 'pairing_pair_id';

  /// The account the stored pairing belongs to. Signing in as a different
  /// Google account must clear the pairing rather than leave a `pairId` that
  /// answers `permission-denied` to every read.
  static const String pairingAccountUid = 'pairing_account_uid';

  static const String pairingPartnerUid = 'pairing_partner_uid';

  /// Cached so the paired row can name the partner while offline; the live
  /// value comes from the pair document's `profiles` map.
  static const String pairingPartnerName = 'pairing_partner_name';

  /// The invite this device generated. Persisted because a restart between
  /// generating and redeeming would otherwise strand the creator: the code is
  /// the only handle it has on the pair the other side is about to create.
  static const String pairingPendingCode = 'pairing_pending_code';
  static const String pairingPendingExpiresAt = 'pairing_pending_expires_at';

  /// Set when the partner ended the link, cleared when the user acknowledges
  /// it. The app has no push notifications, so next foreground is the only
  /// moment available to tell them.
  static const String pairingEndedNotice = 'pairing_ended_notice_pending';

  // Default values for control settings
  static const bool defaultFolderSwipeEnabled = true;
  static const bool defaultNoteSwipeEnabled = true;
  static const bool defaultConfirmDelete = true;
  static const bool defaultAutoSaveEnabled = true;
  static const int defaultAutoSaveInterval = 5;
  static const bool defaultShowNotePreview = true;
  static const bool defaultShowStatsBar = true;
  static const bool defaultHapticFeedback = true;
  static const int defaultDefaultNotesSortOrder = 0;

  // Default values for editor settings
  static const bool defaultLiveMarkdownRendering = true;
  static const bool defaultShowLineNumbers = false;
  static const bool defaultWordWrap = true;
  static const bool defaultShowCursorLine = false;
  static const bool defaultAutoBreakLongLines = true;
  static const bool defaultPreviewWhenKeyboardHidden = false;
  static const bool defaultScrollCursorOnKeyboard = false;
  static const bool defaultPreviewModeEnabled = false;

  // Default values for vocabulary autocomplete
  static const bool defaultVocabularySuggestionsEnabled = true;
  static const String defaultVocabularyTriggerChar = '@';

  // Default values for money ledger settings
  /// Ledger folds start from this balance (cents); 0 keeps the original
  /// "every note starts at zero" behavior.
  static const bool defaultMoneyLedgerEnabled = false;
  static const int defaultMoneyStartCents = 0;
  static const String defaultMoneyCurrencySymbol = '';
  static const bool defaultMoneyCurrencySuffix = false;

  // Default values for markdown colour settings
  /// No custom colours: the presets-only palette.
  static const String defaultMarkdownCustomColors = '';

  // Default values for preview settings
  static const bool defaultShowPreviewScrollbar = false;

  // Default values for toolbar settings
  /// Default ratio of shortcuts section width (0.0–1.0). 0.7 = 70% shortcuts.
  static const double defaultToolbarShortcutRatio = 0.7;
  static const bool defaultToolbarSplitEnabled = true;

  // Default values for preview performance
  static const int defaultPreviewLinesPerChunk = 10;

  // Default values for calendar
  /// Maximum number of bars shown in a calendar day cell before an "+X"
  /// overflow indicator is rendered in place of the last bar.
  static const int defaultCalendarMaxDayBars = 3;

  /// Character budget for an event description. 2000 is the value the field
  /// carried as a hardcoded `maxLength` before it became configurable.
  static const int defaultEventDescriptionLimit = 2000;

  /// Slider bounds for [eventDescriptionLimit]. The floor still comfortably
  /// holds a session checklist; the ceiling is where an "event note" has
  /// clearly become a note and belongs in one.
  static const int minEventDescriptionLimit = 500;
  static const int maxEventDescriptionLimit = 10000;

  /// Slider step for [eventDescriptionLimit].
  static const int eventDescriptionLimitStep = 500;

  // Default values for calendar appearance (enum names are parsed with a
  // forward-compatible fallback in `calendar_appearance.dart`).
  static const String defaultCalendarTodayStyle = 'tonal';
  static const String defaultCalendarMarkerStyle = 'bars';
  static const String defaultCalendarWeekStart = 'monday';
  static const bool defaultCalendarHighlightWeekends = false;
  static const bool defaultCalendarShowWeekNumbers = false;
  static const bool defaultCalendarShowFilterChips = false;
  static const bool defaultCalendarShowRecurrenceLabels = true;

  /// Missed occurrences stay visible by default: a mark the user just made
  /// should visibly do something, and hiding by default reads as a delete.
  static const String defaultCalendarMissedDisplay = 'faded';

  /// Event tinting is opt-in: it repaints most cells on a busy calendar and
  /// competes with the marker strip the user already reads.
  static const bool defaultCalendarEventTint = false;
  static const String defaultCalendarTintConflict = 'eventWins';

  /// Both themes default to the wash exactly as it has always shipped, so
  /// turning the setting on changes nothing until the user picks otherwise.
  static const String defaultCalendarCellStyleLight = 'solid';
  static const String defaultCalendarCellStyleDark = 'solid';

  /// The rail is opt-in like every other appearance option; there is no
  /// first-run nudge and no conditional default.
  static const String defaultCalendarDayRailStyle = 'none';

  /// Rail capacity runs 1-5, not the marker strip's 1-6: at the 44px usable
  /// height of a minimum row, five 5px dots and their gaps are what fits.
  static const int defaultCalendarMaxDayRailMarks = 3;
  static const int minCalendarMaxDayRailMarks = 1;
  static const int maxCalendarMaxDayRailMarks = 5;

  /// Commitments lead by default: the marks read downward from the day number
  /// and the fast is the condition underneath them.
  static const String defaultCalendarDayRailBasePosition = 'bottom';

  /// Default look-ahead window of the upcoming events sheet, in days.
  static const int defaultCalendarUpcomingRangeDays = 30;

  /// Default agenda priority filter: empty CSV = every priority shown.
  static const String defaultCalendarUpcomingPriorities = '';

  /// Default agenda holiday visibility: off, so the agenda stays a training
  /// log until the user opts in.
  static const bool defaultCalendarUpcomingShowHolidays = false;

  /// Default agenda fasting visibility: off (and inert until a fasting
  /// tradition is configured).
  static const bool defaultCalendarUpcomingShowFasting = false;

  /// Default event presentation: one row per occurring day. Condensing the
  /// events layer is entirely opt-in.
  static const String defaultCalendarUpcomingEventDisplay = 'everyOccurrence';

  /// Default fasting presentation: one row per period. A single Lent would
  /// otherwise contribute forty consecutive rows.
  static const String defaultCalendarUpcomingFastingDisplay = 'periods';

  /// Default holiday presentation: one row per holiday, interleaved into the
  /// day walk — what the agenda has always done.
  static const String defaultCalendarUpcomingHolidayDisplay = 'everyDay';

  /// Default: the agenda window starts today, and a grid tap only moves the
  /// grid. Opt in to have the selection re-anchor the window.
  static const bool defaultCalendarUpcomingFollowSelectedDay = false;

  /// Default bottom-panel mode name (see `CalendarPanelMode`).
  static const String defaultCalendarPanelMode = 'day';

  /// Default drill-down presentation: the flat, grouped list (see
  /// `AgendaDayListMode`).
  static const String defaultCalendarDayListMode = 'list';

  /// Default overview-page presentation: the year of dot-matrix tiles.
  static const String defaultCalendarOverviewMode = 'year';

  // ── Event alerts (v40) ──────────────────────────────────────────────

  /// What a new **timed** event's first alert is seeded with, encoded as
  /// `mode:offsetMinutes` — or the literal `none` for "no default", which
  /// starts new events with no alerts at all.
  ///
  /// Ships as `none` (2026-09-21): an alert is something the user goes out of
  /// their way to add, never something an event arrives with. Seeding one is
  /// the opt-in, made here in Calendar settings.
  static const String alertDefaultTimed = 'alert_default_timed';
  static const String defaultAlertDefaultTimed = 'none';

  /// The same for an **all-day** event, encoded as
  /// `mode:daysBefore:minuteOfDay`. Ships as `none` for the same reason; an
  /// all-day alert that never chose a time still anchors on
  /// `kDefaultAlertDayMinute`.
  static const String alertDefaultAllDay = 'alert_default_all_day';
  static const String defaultAlertDefaultAllDay = 'none';

  /// Which sound an alarm plays when its own alert names none.
  ///
  /// Read only through `AlertSound` (`lib/models/alert_sound.dart`), which is
  /// the one place the spellings live: `''` and `system:default` are both the
  /// phone's *current* default alarm (the app ships no sound of its own), and
  /// anything else is a `content://` URI picked out of the phone, armed
  /// verbatim since the `alarm` fork plays a URI directly. A value this build
  /// cannot read decodes to the phone's default, and one this device cannot
  /// open rings it — never silence.
  static const String alertSound = 'alert_sound';
  static const String defaultAlertSound = '';

  /// How long Snooze postpones a ring, in minutes. One length for every alert,
  /// because a screen used half asleep should not ask a question.
  static const String alertSnoozeMinutes = 'alert_snooze_minutes';
  static const int defaultAlertSnoozeMinutes = 10;
  static const int minAlertSnoozeMinutes = 5;

  /// One step under `kLateFireGrace` (30 min), and that is not a taste
  /// (OS-2 review, 2026-09-22): a native snooze taken with no Dart running
  /// moves the plugin's entry while the registry row keeps the original
  /// instant, and the snoozed ring is what launches the app — so at that
  /// launch the row is exactly the snooze length late. Under the grace it is
  /// *in flight* and the ring handler settles it; at the grace it would be
  /// reported as missed and cancelled as a stray while it rings.
  static const int maxAlertSnoozeMinutes = 25;
  static const int alertSnoozeMinutesStep = 5;

  /// How far ahead of an alarm its quiet "Alarm at {time}" notice is posted
  /// (OS-3, **B6**), in minutes. `0` turns the notice off. A change re-arms
  /// every standing alarm through the arm signature, so it reaches alarms
  /// already armed as well as the ones planned next.
  static const String alertNoticeLeadMinutes = 'alert_notice_lead_minutes';
  static const int defaultAlertNoticeLeadMinutes = 120;
  static const int minAlertNoticeLeadMinutes = 0;
  static const int maxAlertNoticeLeadMinutes = 1440;
  static const int alertNoticeLeadMinutesStep = 30;

  /// How long an unacknowledged alarm keeps ringing before it gives up, in
  /// minutes.
  static const String alertSilenceAfterMinutes = 'alert_silence_after_minutes';
  static const int defaultAlertSilenceAfterMinutes = 10;
  static const int minAlertSilenceAfterMinutes = 1;
  static const int maxAlertSilenceAfterMinutes = 30;

  /// Whether the runtime notification prompt has already been raised once.
  ///
  /// A latch, not a setting: Android shows `POST_NOTIFICATIONS` once and
  /// silently refuses every later ask, so without it the first alert of every
  /// session would fire a dialog that can no longer appear. Deliberately
  /// **outside** the alert bundle and outside reset-to-defaults — resetting
  /// the calendar's options must not make the app ask again — and deliberately
  /// not a permission cache: what the user granted is asked of the gateway,
  /// live, every time it matters.
  static const String alertNotificationsAsked = 'alert_notifications_asked';
  static const bool defaultAlertNotificationsAsked = false;

  static const String permissionPromptAcknowledged =
      'permission_prompt_acknowledged';
  static const String permissionLaunchPrompt = 'permission_launch_prompt';
  static const bool defaultPermissionLaunchPrompt = true;

  /// Maximum number of recently-used custom event colors to remember.
  ///
  /// Only the retired [recentEventColors] key is bounded by it; it caps how
  /// many colors the one-time fold into [calendarCustomColors] can carry.
  static const int maxRecentEventColors = 6;

  /// Which geometry the custom-colour picker opens with (a
  /// `ColorPickerMode` name). A standing preference, not a per-pick one.
  static const String colorPickerMode = 'color_picker_mode';
  static const String defaultColorPickerMode = 'square';

  /// Ceiling on the user's own swatches. A picker is a `Wrap` the user scans,
  /// not a list they search, so an unbounded palette would quietly turn every
  /// colour row into a wall of dots.
  static const int maxCustomCalendarColors = 24;

  /// CSV of folded section ids on the calendar settings page. A view
  /// preference of that page only — it changes nothing the calendar draws,
  /// which is why it stays out of [SettingsService.getCalendarPageSettings].
  /// Absent means every section is open, and an id that no longer matches a
  /// section is inert rather than an error.
  static const String calendarSettingsCollapsedSections =
      'calendar_settings_collapsed_sections';

  /// CSV of folded section ids on the app settings page — the same view-only
  /// preference as [calendarSettingsCollapsedSections], kept separate so the
  /// two pages fold independently. Absent means every section is open, and an
  /// id that no longer matches a section is inert rather than an error.
  static const String appSettingsCollapsedSections =
      'app_settings_collapsed_sections';
}
