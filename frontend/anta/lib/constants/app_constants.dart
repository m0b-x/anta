class AppConstants {
  // ============================================================
  // SHARED PREFERENCES KEYS (for device-local state only)
  // ============================================================
  static const String recentSearchesKey = 'recent_searches';

  // ============================================================
  // TIMING CONSTANTS
  // ============================================================
  static const Duration autoSaveInterval = Duration(seconds: 30);
  static const Duration autoSaveDelay = Duration(seconds: 5);
  static const Duration debounceDelay = Duration(milliseconds: 500);
  static const Duration longPressDelay = Duration(milliseconds: 300);
  static const Duration shortDelay = Duration(milliseconds: 100);
  static const Duration animationDuration = Duration(milliseconds: 200);
  static const Duration historyDebounceDuration = Duration(milliseconds: 400);
  static const Duration autoScrollTickDuration = Duration(milliseconds: 50);

  // Snackbar timings. Kept short so transient messages never linger:
  // a snackbar is supposed to be peripheral feedback, not a modal.
  // - Default: success / informational ("Note moved", "Saved…").
  // - Error: same as default — errors that need more attention should
  //   be a dialog, not a long-lived snackbar.
  // - WithAction: the default keeps an Undo prompt as short as a message,
  //   since users tap at once if they are going to; a prompt that must be
  //   read first (the editor's link confirm) asks for more, and nothing
  //   with an action stays longer than the max.
  static const Duration snackbarDuration = Duration(seconds: 3);
  static const Duration snackbarErrorDuration = Duration(seconds: 3);
  static const Duration snackbarSuccessDuration = Duration(seconds: 2);
  static const Duration snackbarActionDefaultDuration = Duration(seconds: 3);
  static const Duration snackbarActionMaxDuration = Duration(seconds: 5);

  /// A share notice arrives unasked — nothing the person just did announces
  /// it — so it must be read first, and stays as long as any bar may.
  static const Duration shareNoticeDuration = snackbarActionMaxDuration;

  /// What a bar spends off its own time: a bar that replaces another waits
  /// out that one's exit, then its own entrance (250 ms each in
  /// `material/scaffold.dart`), before its duration starts. A caller that
  /// says two bars in a row waits this long past the first one's duration,
  /// or the second takes the first down early.
  static const Duration snackbarTransitions = Duration(milliseconds: 500);

  // ============================================================
  // UI CONSTANTS
  // ============================================================
  static const double edgeScrollThreshold = 80.0;
  static const double autoScrollSpeed = 10.0;

  /// Minimum toolbar shortcut ratio (30%).
  static const double minToolbarRatio = 0.3;

  /// Maximum toolbar shortcut ratio (80%).
  static const double maxToolbarRatio = 0.8;

  // ============================================================
  // PAGINATION CONSTANTS
  // ============================================================
  static const int defaultPageSize = 20;
  static const int notePickerPageSize = 6;

  /// How many "most recently edited" notes anything showing recents lists:
  /// the Recent page and the search surface's idle list, which used to
  /// disagree (50 against 20) under one label.
  static const int recentNotesLimit = 50;

  // ============================================================
  // CACHE CONSTANTS
  // ============================================================
  static const int maxNoteCacheSize = 200;
  static const int maxContentCacheSize = 50;

  /// The content cache's weight bound: 8 Mi UTF-16 code units (about
  /// 16 MB). Fifty bodies of a few megabytes each would otherwise all stay
  /// resident.
  static const int maxContentCacheCodeUnits = 8 * 1024 * 1024;
  static const int maxFolderCacheSize = 100;

  /// How much of an exception string an on-screen error carries — the
  /// render-error placeholder and the launch's failed state. Long enough to
  /// name what failed, short enough to stay a caption rather than a wall of
  /// stack frames.
  static const int errorDetailLimit = 300;

  /// What a checkpoint truncates the `-wal` sidecar back to (`PRAGMA
  /// journal_size_limit`), in bytes. Without a limit the WAL keeps the size
  /// of the largest transaction it ever held — a migration step or an
  /// Optimize leaves one the size of the database. Twice the ~4 MB the WAL
  /// reaches between automatic checkpoints, so ordinary writing never pays
  /// for a truncate and a regrow.
  static const int sqliteJournalSizeLimitBytes = 8 * 1024 * 1024;

  /// How many ids one `IN (?, …)` statement binds when a DAO takes an
  /// unbounded id list. SQLite refuses a statement over
  /// `SQLITE_MAX_VARIABLE_NUMBER` (32,766 in the bundled build), and the
  /// refusal rolls back the whole transaction around it — a folder delete
  /// over 33,000 notes failed outright.
  static const int sqlIdBatch = 500;

  /// How long a linked note's money ledger waits after its last change
  /// before it refolds: auto-save writes every few seconds while typing,
  /// and the calendar's totals need only the settled body.
  static const Duration ledgerRefoldDebounce = Duration(seconds: 1);
  static const Duration cacheExpiry = Duration(minutes: 5);

  // ============================================================
  // CONTENT CONSTANTS
  // ============================================================
  static const int previewMaxLength = 200;

  /// The `notes.title` column's `withLength` maximum, in UTF-16 code units:
  /// a title built in code (a sync conflict copy's) is cut to fit it, or the
  /// insert fails.
  static const int maxNoteTitleLength = 500;

  // ============================================================
  // SEARCH CONSTANTS
  // ============================================================
  static const int maxRecentSearches = 10;
  static const int maxSearchMatches = 1000;

  // ============================================================
  // MOVE HISTORY CONSTANTS
  // ============================================================
  /// How many moves the history keeps for undo, counted as the user made
  /// them: a selection moved together is one, however many items it held.
  static const int moveHistoryMaxUnits = 20;

  /// The most entries the history holds whatever the unit count, so twenty
  /// huge selections cannot pile up in memory. Older units are dropped whole;
  /// the newest is always kept whole, since its Undo is the one on screen.
  static const int moveHistoryMaxEntries = 2000;

  // ============================================================
  // ORDERING AND MOVE CONSTANTS
  // ============================================================
  /// The gap a new folder or note leaves after the last one, and the spacing
  /// a respread restores. Wide enough that a drag almost always lands between
  /// two neighbours without moving either; `position` is an int64 column, so
  /// the headroom is still some eight million million appends.
  static const int positionStride = 1 << 20;

  // ============================================================
  // EDITOR LAYOUT CONSTANTS
  // ============================================================
  /// Extra right padding added to the code editor to reserve space
  /// for the scroll-progress indicator overlay.
  static const double editorScrollbarPadding = 16.0;

  // ============================================================
  // PREVIEW CONSTANTS
  // ============================================================
  /// Notes under this line count get instant preview switching (pre-loaded offstage).
  /// Larger notes use lazy loading with a short scroll animation to avoid memory overhead.
  static const int previewPreloadLineThreshold = 3000;

  /// The same lazy path by size, in UTF-16 code units: a note of a few long
  /// lines passes the line gate while re-preparing it after every pause
  /// costs as much as a long one.
  static const int previewPreloadCodeUnitThreshold = 100000;

  /// Above this many UTF-16 code units, the editor's first load splits the
  /// note into lines off the UI isolate, so a large note's first frame is
  /// not held by the split.
  static const int asyncLineBuildThreshold = 256 * 1024;

  /// Maximum allowed length for markdown bar profile names.
  static const int maxBarProfileNameLength = 30;

  /// A settings list only grows a search field once it exceeds this many
  /// entries — short, fixed lists stay free of search chrome.
  static const int listSearchThreshold = 12;

  /// Joins a category row's caption segments: the space before the dot is
  /// a no-break one, so a wrapped line never starts with the dot — German
  /// and Romanian at 2.0 wrap there. The Categories page and the received
  /// categories sheet both read it.
  static const String captionSeparator = ' · ';

  AppConstants._();
}
