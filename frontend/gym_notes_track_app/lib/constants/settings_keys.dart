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

  // Toolbar settings
  static const String toolbarShortcutRatio = 'toolbar_shortcut_ratio';
  static const String toolbarSplitEnabled = 'toolbar_split_enabled';
  static const String toolbarUtilityConfig = 'toolbar_utility_config';

  // Preview performance settings
  static const String previewLinesPerChunk = 'preview_lines_per_chunk';

  // Calendar settings
  static const String calendarMaxDayBars = 'calendar_max_day_bars';
  static const String holidayProfile = 'holiday_profile';

  // Calendar appearance settings
  static const String calendarTodayStyle = 'calendar_today_style';
  static const String calendarMarkerStyle = 'calendar_marker_style';
  static const String calendarWeekStart = 'calendar_week_start';

  /// Explicit ARGB accent for today/selected highlights. Empty/absent means
  /// "follow the theme's primary color".
  static const String calendarAccentColor = 'calendar_accent_color';
  static const String calendarHighlightWeekends = 'calendar_highlight_weekends';
  static const String calendarShowWeekNumbers = 'calendar_show_week_numbers';

  /// Recently used custom event colors (comma-separated ARGB ints,
  /// most-recent-first).
  static const String recentEventColors = 'recent_event_colors';

  /// Last look-ahead window (in days) used in the upcoming events sheet.
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

  /// Whether the agenda's period/priority chip rows were left expanded.
  static const String calendarUpcomingFiltersExpanded =
      'calendar_upcoming_filters_expanded';

  /// Whether the upcoming agenda lists public holidays alongside events.
  static const String calendarUpcomingShowHolidays =
      'calendar_upcoming_show_holidays';

  /// Which mode the calendar's bottom panel was left in (day / timeline /
  /// upcoming). Parsed with a forward-compatible fallback.
  static const String calendarPanelMode = 'calendar_panel_mode';

  // Last navigation location (restored on next app launch)
  static const String lastFolderId = 'last_folder_id';
  static const String lastFolderTitle = 'last_folder_title';
  static const String lastNoteId = 'last_note_id';

  // Note position (prefix for per-note storage)
  static const String notePositionPrefix = 'note_position_';

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

  // Default values for calendar appearance (enum names are parsed with a
  // forward-compatible fallback in `calendar_appearance.dart`).
  static const String defaultCalendarTodayStyle = 'tonal';
  static const String defaultCalendarMarkerStyle = 'bars';
  static const String defaultCalendarWeekStart = 'monday';
  static const bool defaultCalendarHighlightWeekends = true;
  static const bool defaultCalendarShowWeekNumbers = false;

  /// Default look-ahead window of the upcoming events sheet, in days.
  static const int defaultCalendarUpcomingRangeDays = 30;

  /// Default agenda priority filter: empty CSV = every priority shown.
  static const String defaultCalendarUpcomingPriorities = '';

  /// Default agenda filter-row state: collapsed, so the short bottom panel
  /// is mostly list rather than chrome.
  static const bool defaultCalendarUpcomingFiltersExpanded = false;

  /// Default agenda holiday visibility: off, so the agenda stays a training
  /// log until the user opts in.
  static const bool defaultCalendarUpcomingShowHolidays = false;

  /// Default bottom-panel mode name (see `CalendarPanelMode`).
  static const String defaultCalendarPanelMode = 'day';

  /// Maximum number of recently-used custom event colors to remember.
  static const int maxRecentEventColors = 6;
}
