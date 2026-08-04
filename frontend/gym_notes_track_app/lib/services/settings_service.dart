import 'package:flutter/painting.dart';

import '../constants/settings_keys.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_panel_mode.dart';
import '../models/upcoming_agenda_filters.dart';
import '../models/utility_button_config.dart';
import '../utils/markdown_color_syntax.dart';

/// Service for managing app settings using SQLite database
class SettingsService {
  static SettingsService? _instance;
  late AppDatabase _db;

  SettingsService._();

  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      _instance = SettingsService._();
      _instance!._db = await AppDatabase.getInstance();
      DatabaseLifecycle.registerResetHandler(reset);
    }
    return _instance!;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  static void reset() {
    _instance = null;
  }

  // Helper methods for type conversion
  Future<bool> _getBool(String key, bool defaultValue) async {
    final value = await _db.userSettingsDao.getValue(key);
    if (value == null) return defaultValue;
    return value == 'true';
  }

  Future<void> _setBool(String key, bool value) async {
    await _db.userSettingsDao.setValue(key, value.toString());
  }

  /// The effective money display config for a note: whether the
  /// feature is enabled at all, the global start balance, and the
  /// note's currency override when present (else the global currency).
  /// Resolved once per note load by the editor page.
  Future<({bool enabled, int startCents, String symbol, bool suffix})>
  getMoneyConfig({String? noteId}) async {
    final enabled = await getMoneyLedgerEnabled();
    final startCents = await _getInt(
      SettingsKeys.moneyStartCents,
      SettingsKeys.defaultMoneyStartCents,
    );
    if (noteId != null && noteId.isNotEmpty) {
      final override = await _db.userSettingsDao.getValue(
        '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId',
      );
      if (override != null && override.isNotEmpty) {
        final sep = override.lastIndexOf('|');
        if (sep > 0) {
          return (
            enabled: enabled,
            startCents: startCents,
            symbol: override.substring(0, sep),
            suffix: override.substring(sep + 1) == 'true',
          );
        }
        return (
          enabled: enabled,
          startCents: startCents,
          symbol: override,
          suffix: false,
        );
      }
    }
    return (
      enabled: enabled,
      startCents: startCents,
      symbol:
          await _db.userSettingsDao.getValue(
            SettingsKeys.moneyCurrencySymbol,
          ) ??
          SettingsKeys.defaultMoneyCurrencySymbol,
      suffix: await _getBool(
        SettingsKeys.moneyCurrencySuffix,
        SettingsKeys.defaultMoneyCurrencySuffix,
      ),
    );
  }

  Future<bool> getMoneyLedgerEnabled() => _getBool(
    SettingsKeys.moneyLedgerEnabled,
    SettingsKeys.defaultMoneyLedgerEnabled,
  );

  Future<void> setMoneyLedgerEnabled(bool value) =>
      _setBool(SettingsKeys.moneyLedgerEnabled, value);

  Future<void> setMoneyStartCents(int cents) =>
      _setInt(SettingsKeys.moneyStartCents, cents);

  Future<void> setMoneyCurrencySymbol(String symbol) =>
      _db.userSettingsDao.setValue(SettingsKeys.moneyCurrencySymbol, symbol);

  Future<void> setMoneyCurrencySuffix(bool suffix) =>
      _setBool(SettingsKeys.moneyCurrencySuffix, suffix);

  /// The raw per-note currency override (`null` = inherits global).
  Future<({String symbol, bool suffix})?> getNoteMoneyCurrency(
    String noteId,
  ) async {
    final raw = await _db.userSettingsDao.getValue(
      '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId',
    );
    if (raw == null || raw.isEmpty) return null;
    final sep = raw.lastIndexOf('|');
    if (sep > 0) {
      return (
        symbol: raw.substring(0, sep),
        suffix: raw.substring(sep + 1) == 'true',
      );
    }
    return (symbol: raw, suffix: false);
  }

  /// Sets or clears (`null`) the per-note currency override.
  Future<void> setNoteMoneyCurrency(
    String noteId, {
    ({String symbol, bool suffix})? currency,
  }) async {
    final key = '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId';
    // `|` is the encoding separator — strip it from the symbol so a
    // pathological custom symbol can never corrupt the round-trip. A
    // symbol that is empty after sanitizing (e.g. the user typed only
    // `|`) has nothing to override with, so it clears like null (the
    // decoders require the separator at index > 0, so an empty symbol
    // part could never be read back anyway).
    final symbol = currency?.symbol.replaceAll('|', '') ?? '';
    if (currency == null || symbol.isEmpty) {
      await _db.userSettingsDao.deleteValue(key);
    } else {
      await _db.userSettingsDao.setValue(key, '$symbol|${currency.suffix}');
    }
  }

  /// Memoized palette, so repeated note opens skip the decode and the
  /// per-colour contrast resolution. Keyed by the persisted source, and
  /// returning the same instance also lets the render-cache key hit its
  /// `identical` fast path.
  MarkdownColorPalette? _colorPalette;

  /// The effective markdown colour palette: the built-in presets
  /// overlaid with the user's custom colours. Resolved by the editor
  /// page on note open and after returning from settings.
  Future<MarkdownColorPalette> getColorPalette() async {
    final source =
        await _db.userSettingsDao.getValue(SettingsKeys.markdownCustomColors) ??
        SettingsKeys.defaultMarkdownCustomColors;
    final cached = _colorPalette;
    if (cached != null && cached.source == source) return cached;
    return _colorPalette = MarkdownColorPalette.decode(source);
  }

  /// Persists the custom colours (name -> colour). Names must already be
  /// normalized by [MarkdownColorPalette.normalizeName].
  Future<void> setCustomColors(Map<String, Color> colors) async {
    final source = MarkdownColorPalette.encode(colors);
    await _db.userSettingsDao.setValue(
      SettingsKeys.markdownCustomColors,
      source,
    );
    _colorPalette = MarkdownColorPalette.decode(source);
  }

  Future<int> _getInt(String key, int defaultValue) async {
    final value = await _db.userSettingsDao.getValue(key);
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  Future<void> _setInt(String key, int value) async {
    await _db.userSettingsDao.setValue(key, value.toString());
  }

  // Folder swipe gesture (to open drawer)
  Future<bool> getFolderSwipeEnabled() async {
    return _getBool(
      SettingsKeys.folderSwipeEnabled,
      SettingsKeys.defaultFolderSwipeEnabled,
    );
  }

  Future<void> setFolderSwipeEnabled(bool value) async {
    await _setBool(SettingsKeys.folderSwipeEnabled, value);
  }

  // Note swipe gesture (to open drawer)
  Future<bool> getNoteSwipeEnabled() async {
    return _getBool(
      SettingsKeys.noteSwipeEnabled,
      SettingsKeys.defaultNoteSwipeEnabled,
    );
  }

  Future<void> setNoteSwipeEnabled(bool value) async {
    await _setBool(SettingsKeys.noteSwipeEnabled, value);
  }

  // Confirm before delete
  Future<bool> getConfirmDelete() async {
    return _getBool(
      SettingsKeys.confirmDelete,
      SettingsKeys.defaultConfirmDelete,
    );
  }

  Future<void> setConfirmDelete(bool value) async {
    await _setBool(SettingsKeys.confirmDelete, value);
  }

  // Auto-save
  Future<bool> getAutoSaveEnabled() async {
    return _getBool(
      SettingsKeys.autoSaveEnabled,
      SettingsKeys.defaultAutoSaveEnabled,
    );
  }

  Future<void> setAutoSaveEnabled(bool value) async {
    await _setBool(SettingsKeys.autoSaveEnabled, value);
  }

  // Auto-save interval in seconds
  Future<int> getAutoSaveInterval() async {
    return _getInt(
      SettingsKeys.autoSaveInterval,
      SettingsKeys.defaultAutoSaveInterval,
    );
  }

  Future<void> setAutoSaveInterval(int seconds) async {
    await _setInt(SettingsKeys.autoSaveInterval, seconds);
  }

  // Show note preview in list
  Future<bool> getShowNotePreview() async {
    return _getBool(
      SettingsKeys.showNotePreview,
      SettingsKeys.defaultShowNotePreview,
    );
  }

  Future<void> setShowNotePreview(bool value) async {
    await _setBool(SettingsKeys.showNotePreview, value);
  }

  // Show stats bar in note editor
  Future<bool> getShowStatsBar() async {
    return _getBool(
      SettingsKeys.showStatsBar,
      SettingsKeys.defaultShowStatsBar,
    );
  }

  Future<void> setShowStatsBar(bool value) async {
    await _setBool(SettingsKeys.showStatsBar, value);
  }

  // Default notes sort order (0 = updatedDesc, 1 = updatedAsc, 2 = titleAsc, 3 = titleDesc, 4 = createdDesc, 5 = createdAsc)
  Future<int> getDefaultNotesSortOrder() async {
    return _getInt(
      SettingsKeys.defaultNotesSortOrder,
      SettingsKeys.defaultDefaultNotesSortOrder,
    );
  }

  Future<void> setDefaultNotesSortOrder(int value) async {
    await _setInt(SettingsKeys.defaultNotesSortOrder, value);
  }

  // Haptic feedback
  Future<bool> getHapticFeedback() async {
    return _getBool(
      SettingsKeys.hapticFeedback,
      SettingsKeys.defaultHapticFeedback,
    );
  }

  Future<void> setHapticFeedback(bool value) async {
    await _setBool(SettingsKeys.hapticFeedback, value);
  }

  // Editor settings - Live markdown rendering in the text editor
  Future<bool> getLiveMarkdownRendering() async {
    return _getBool(
      SettingsKeys.liveMarkdownRendering,
      SettingsKeys.defaultLiveMarkdownRendering,
    );
  }

  Future<void> setLiveMarkdownRendering(bool value) async {
    await _setBool(SettingsKeys.liveMarkdownRendering, value);
  }

  // Editor settings - Show line numbers
  Future<bool> getShowLineNumbers() async {
    return _getBool(
      SettingsKeys.showLineNumbers,
      SettingsKeys.defaultShowLineNumbers,
    );
  }

  Future<void> setShowLineNumbers(bool value) async {
    await _setBool(SettingsKeys.showLineNumbers, value);
  }

  // Editor settings - Word wrap
  Future<bool> getWordWrap() async {
    return _getBool(SettingsKeys.wordWrap, SettingsKeys.defaultWordWrap);
  }

  Future<void> setWordWrap(bool value) async {
    await _setBool(SettingsKeys.wordWrap, value);
  }

  // Editor settings - Show cursor line highlight
  Future<bool> getShowCursorLine() async {
    return _getBool(
      SettingsKeys.showCursorLine,
      SettingsKeys.defaultShowCursorLine,
    );
  }

  Future<void> setShowCursorLine(bool value) async {
    await _setBool(SettingsKeys.showCursorLine, value);
  }

  // Editor settings - Auto break long lines on paste
  Future<bool> getAutoBreakLongLines() async {
    return _getBool(
      SettingsKeys.autoBreakLongLines,
      SettingsKeys.defaultAutoBreakLongLines,
    );
  }

  Future<void> setAutoBreakLongLines(bool value) async {
    await _setBool(SettingsKeys.autoBreakLongLines, value);
  }

  // Editor settings - Show preview when keyboard is hidden
  Future<bool> getPreviewWhenKeyboardHidden() async {
    return _getBool(
      SettingsKeys.previewWhenKeyboardHidden,
      SettingsKeys.defaultPreviewWhenKeyboardHidden,
    );
  }

  Future<void> setPreviewWhenKeyboardHidden(bool value) async {
    await _setBool(SettingsKeys.previewWhenKeyboardHidden, value);
  }

  // Editor settings - Scroll cursor into view when keyboard appears
  Future<bool> getScrollCursorOnKeyboard() async {
    return _getBool(
      SettingsKeys.scrollCursorOnKeyboard,
      SettingsKeys.defaultScrollCursorOnKeyboard,
    );
  }

  Future<void> setScrollCursorOnKeyboard(bool value) async {
    await _setBool(SettingsKeys.scrollCursorOnKeyboard, value);
  }

  // Preview settings - Show scrollbar
  Future<bool> getShowPreviewScrollbar() async {
    return _getBool(
      SettingsKeys.showPreviewScrollbar,
      SettingsKeys.defaultShowPreviewScrollbar,
    );
  }

  Future<void> setShowPreviewScrollbar(bool value) async {
    await _setBool(SettingsKeys.showPreviewScrollbar, value);
  }

  // Preview performance - Lines per chunk
  Future<int> getPreviewLinesPerChunk() async {
    return _getInt(
      SettingsKeys.previewLinesPerChunk,
      SettingsKeys.defaultPreviewLinesPerChunk,
    );
  }

  Future<void> setPreviewLinesPerChunk(int value) async {
    await _setInt(SettingsKeys.previewLinesPerChunk, value);
  }

  // Calendar - Max number of bars shown per day cell (overflow shows "+N").
  Future<int> getCalendarMaxDayBars() async {
    return _getInt(
      SettingsKeys.calendarMaxDayBars,
      SettingsKeys.defaultCalendarMaxDayBars,
    );
  }

  Future<void> setCalendarMaxDayBars(int value) async {
    await _setInt(SettingsKeys.calendarMaxDayBars, value);
  }

  // Calendar appearance - today highlight style.
  Future<CalendarTodayStyle> getCalendarTodayStyle() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarTodayStyle,
    );
    return CalendarTodayStyle.fromName(
      raw ?? SettingsKeys.defaultCalendarTodayStyle,
    );
  }

  Future<void> setCalendarTodayStyle(CalendarTodayStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarTodayStyle,
      style.name,
    );
  }

  // Calendar appearance - event marker style (bars / dots).
  Future<CalendarMarkerStyle> getCalendarMarkerStyle() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarMarkerStyle,
    );
    return CalendarMarkerStyle.fromName(
      raw ?? SettingsKeys.defaultCalendarMarkerStyle,
    );
  }

  Future<void> setCalendarMarkerStyle(CalendarMarkerStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarMarkerStyle,
      style.name,
    );
  }

  // Calendar appearance - first day of the week.
  Future<CalendarWeekStart> getCalendarWeekStart() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarWeekStart,
    );
    return CalendarWeekStart.fromName(
      raw ?? SettingsKeys.defaultCalendarWeekStart,
    );
  }

  Future<void> setCalendarWeekStart(CalendarWeekStart start) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarWeekStart,
      start.name,
    );
  }

  // Calendar appearance - custom highlight accent (null = theme primary).
  Future<int?> getCalendarAccentColor() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarAccentColor,
    );
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> setCalendarAccentColor(int? color) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarAccentColor,
      color?.toString() ?? '',
    );
  }

  // Calendar appearance - tint weekend day numbers.
  Future<bool> getCalendarHighlightWeekends() async {
    return _getBool(
      SettingsKeys.calendarHighlightWeekends,
      SettingsKeys.defaultCalendarHighlightWeekends,
    );
  }

  Future<void> setCalendarHighlightWeekends(bool value) async {
    await _setBool(SettingsKeys.calendarHighlightWeekends, value);
  }

  // Calendar appearance - show ISO week numbers.
  Future<bool> getCalendarShowWeekNumbers() async {
    return _getBool(
      SettingsKeys.calendarShowWeekNumbers,
      SettingsKeys.defaultCalendarShowWeekNumbers,
    );
  }

  Future<void> setCalendarShowWeekNumbers(bool value) async {
    await _setBool(SettingsKeys.calendarShowWeekNumbers, value);
  }

  /// Loads every upcoming-agenda filter in one call.
  Future<UpcomingAgendaFilters> getUpcomingAgendaFilters() async {
    final rangeDays = await _getInt(
      SettingsKeys.calendarUpcomingRangeDays,
      SettingsKeys.defaultCalendarUpcomingRangeDays,
    );
    final (customStart, customEnd) = UpcomingAgendaFilters.decodeRange(
      await _db.userSettingsDao.getValue(
            SettingsKeys.calendarUpcomingCustomRange,
          ) ??
          '',
    );
    return UpcomingAgendaFilters(
      rangeDays: rangeDays,
      priorities: await _readUpcomingPriorities(),
      customStart: customStart,
      customEnd: customEnd,
      query:
          await _db.userSettingsDao.getValue(
            SettingsKeys.calendarUpcomingQuery,
          ) ??
          '',
      filtersExpanded: await _getBool(
        SettingsKeys.calendarUpcomingFiltersExpanded,
        SettingsKeys.defaultCalendarUpcomingFiltersExpanded,
      ),
      showHolidays: await _getBool(
        SettingsKeys.calendarUpcomingShowHolidays,
        SettingsKeys.defaultCalendarUpcomingShowHolidays,
      ),
    );
  }

  /// Reads the priority set. The superseded single-threshold key is folded
  /// into this one (values flipped to the 1-is-highest scale) by the v18
  /// database migration, so no legacy fallback is needed here.
  Future<Set<int>> _readUpcomingPriorities() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingPriorities,
    );
    if (raw == null) return const {};
    return UpcomingAgendaFilters.decodePriorities(raw);
  }

  /// Persists every upcoming-agenda filter. Callers debounce the text query
  /// themselves; the discrete choices are cheap enough to write on change.
  Future<void> saveUpcomingAgendaFilters(UpcomingAgendaFilters filters) async {
    await _setInt(SettingsKeys.calendarUpcomingRangeDays, filters.rangeDays);
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingPriorities,
      UpcomingAgendaFilters.encodePriorities(filters.priorities),
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCustomRange,
      UpcomingAgendaFilters.encodeRange(filters.customStart, filters.customEnd),
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingQuery,
      filters.query,
    );
    await _setBool(
      SettingsKeys.calendarUpcomingFiltersExpanded,
      filters.filtersExpanded,
    );
    await _setBool(
      SettingsKeys.calendarUpcomingShowHolidays,
      filters.showHolidays,
    );
  }

  // Calendar - Which mode the bottom panel was left in.
  Future<CalendarPanelMode> getCalendarPanelMode() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarPanelMode,
    );
    return CalendarPanelMode.fromName(
      raw ?? SettingsKeys.defaultCalendarPanelMode,
    );
  }

  Future<void> setCalendarPanelMode(CalendarPanelMode mode) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarPanelMode,
      mode.name,
    );
  }

  /// Loads every calendar look & feel option in one call.
  Future<CalendarAppearance> getCalendarAppearance() async {
    return CalendarAppearance(
      todayStyle: await getCalendarTodayStyle(),
      markerStyle: await getCalendarMarkerStyle(),
      weekStart: await getCalendarWeekStart(),
      accentColorValue: await getCalendarAccentColor(),
      highlightWeekends: await getCalendarHighlightWeekends(),
      showWeekNumbers: await getCalendarShowWeekNumbers(),
      maxDayBars: await getCalendarMaxDayBars(),
    );
  }

  // Calendar - Recently used custom event colors (most-recent-first, capped).
  Future<List<int>> getRecentEventColors() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.recentEventColors,
    );
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').map(int.tryParse).whereType<int>().toList();
  }

  /// Pushes [color] to the front of the recent list (dedup, capped to
  /// [SettingsKeys.maxRecentEventColors]).
  Future<void> addRecentEventColor(int color) async {
    final current = await getRecentEventColors();
    final next = <int>[
      color,
      ...current.where((c) => c != color),
    ].take(SettingsKeys.maxRecentEventColors).toList();
    await _db.userSettingsDao.setValue(
      SettingsKeys.recentEventColors,
      next.join(','),
    );
  }

  // ── Last navigation location ─────────────────────────────────────────
  // Remembers the folder (and optionally the note inside it) the user was
  // viewing, so the app can reopen that location on the next cold launch.

  Future<String?> getLastFolderId() async {
    return _db.userSettingsDao.getValue(SettingsKeys.lastFolderId);
  }

  Future<String?> getLastFolderTitle() async {
    return _db.userSettingsDao.getValue(SettingsKeys.lastFolderTitle);
  }

  Future<String?> getLastNoteId() async {
    return _db.userSettingsDao.getValue(SettingsKeys.lastNoteId);
  }

  /// Records the folder the user just opened. Clears any remembered note,
  /// since entering a folder means we are no longer inside a note.
  Future<void> saveLastFolder(String folderId, String title) async {
    await _db.userSettingsDao.setValue(SettingsKeys.lastFolderId, folderId);
    await _db.userSettingsDao.setValue(SettingsKeys.lastFolderTitle, title);
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastNoteId);
  }

  /// Records the note the user just opened. The enclosing folder is already
  /// stored by the preceding [saveLastFolder] call.
  Future<void> saveLastNote(String noteId) async {
    await _db.userSettingsDao.setValue(SettingsKeys.lastNoteId, noteId);
  }

  /// Forgets the remembered location (e.g. when the target no longer exists).
  Future<void> clearLastLocation() async {
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastFolderId);
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastFolderTitle);
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastNoteId);
  }

  // Toolbar settings - Shortcut/utility ratio
  Future<double> getToolbarShortcutRatio() async {
    final value = await _db.userSettingsDao.getValue(
      SettingsKeys.toolbarShortcutRatio,
    );
    if (value == null) return SettingsKeys.defaultToolbarShortcutRatio;
    return double.tryParse(value) ?? SettingsKeys.defaultToolbarShortcutRatio;
  }

  Future<void> setToolbarShortcutRatio(double value) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.toolbarShortcutRatio,
      value.toString(),
    );
  }

  Future<bool> getToolbarSplitEnabled() async {
    return _getBool(
      SettingsKeys.toolbarSplitEnabled,
      SettingsKeys.defaultToolbarSplitEnabled,
    );
  }

  Future<void> setToolbarSplitEnabled(bool value) async {
    await _setBool(SettingsKeys.toolbarSplitEnabled, value);
  }

  // Toolbar utility buttons config
  Future<List<UtilityButtonConfig>> getToolbarUtilityConfig() async {
    final value = await _db.userSettingsDao.getValue(
      SettingsKeys.toolbarUtilityConfig,
    );
    if (value == null) return UtilityButtonConfig.defaults();
    return UtilityButtonConfig.decode(value);
  }

  Future<void> setToolbarUtilityConfig(
    List<UtilityButtonConfig> configs,
  ) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.toolbarUtilityConfig,
      UtilityButtonConfig.encode(configs),
    );
  }

  Future<bool> isOnboardingCompleted() async {
    return _getBool(SettingsKeys.onboardingCompleted, false);
  }

  Future<void> setOnboardingCompleted(bool value) async {
    await _setBool(SettingsKeys.onboardingCompleted, value);
  }
}
