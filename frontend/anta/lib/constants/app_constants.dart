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
  // - WithAction: capped equally so an Undo prompt can't outstay its
  //   welcome; users tap immediately if they're going to.
  static const Duration snackbarDuration = Duration(seconds: 3);
  static const Duration snackbarErrorDuration = Duration(seconds: 3);
  static const Duration snackbarSuccessDuration = Duration(seconds: 2);
  static const Duration snackbarActionMaxDuration = Duration(seconds: 3);

  // ============================================================
  // UI CONSTANTS
  // ============================================================
  static const double edgeScrollThreshold = 80.0;
  static const double autoScrollSpeed = 10.0;

  // Markdown toolbar sizing
  static const double markdownToolbarPadding = 8.0;
  static const double markdownToolbarButtonPadding = 10.0;
  static const double markdownToolbarButtonMargin = 2.0;
  static const double markdownToolbarIconSize = 20.0;
  static const double markdownToolbarTextSize = 16.0;

  /// Minimum toolbar shortcut ratio (30%).
  static const double minToolbarRatio = 0.3;

  /// Maximum toolbar shortcut ratio (80%).
  static const double maxToolbarRatio = 0.8;

  // ============================================================
  // PAGINATION CONSTANTS
  // ============================================================
  static const int defaultPageSize = 20;
  static const int notePickerPageSize = 6;

  // ============================================================
  // CACHE CONSTANTS
  // ============================================================
  static const int maxNoteCacheSize = 200;
  static const int maxContentCacheSize = 50;
  static const int maxFolderCacheSize = 100;
  static const Duration cacheExpiry = Duration(minutes: 5);

  // ============================================================
  // CONTENT CONSTANTS
  // ============================================================
  static const int defaultChunkSize = 10000; // 10KB chunks
  static const int compressionThreshold = 5000;
  static const int previewMaxLength = 200;

  // ============================================================
  // SEARCH CONSTANTS
  // ============================================================
  static const int maxRecentSearches = 10;
  static const int maxSearchMatches = 1000;

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

  /// Maximum allowed length for markdown bar profile names.
  static const int maxBarProfileNameLength = 30;

  /// A settings list only grows a search field once it exceeds this many
  /// entries — short, fixed lists stay free of search chrome.
  static const int listSearchThreshold = 12;

  AppConstants._();
}
