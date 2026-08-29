import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../constants/calendar_icons.dart';
import '../constants/fasting_calendar.dart';
import '../constants/settings_keys.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_panel_mode.dart';
import '../models/upcoming_agenda_filters.dart';
import '../models/utility_button_config.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/vocabulary_trigger.dart';

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

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup. Exists so tests can
  /// exercise the real DAO against `NativeDatabase.memory()`; never use it in
  /// app code — the singleton is what the [DatabaseLifecycle] reset contract
  /// is built on.
  @visibleForTesting
  static SettingsService forTesting(AppDatabase db) {
    if (_instance != null) return _instance!;
    final service = SettingsService._();
    service._db = db;
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  ///
  /// Also clears the static [FastingCalendar] configuration: it is derived
  /// entirely from settings rows this service owns, and would otherwise keep
  /// painting the previous database's practice.
  static void reset() {
    _instance = null;
    FastingCalendar.resetConfiguration();
  }

  /// Decoders take the raw stored string so a value can be resolved either
  /// from a single-row read or from a bulk snapshot without a second copy of
  /// the parsing rules. `UserSettings.value` is non-nullable, so a `null` raw
  /// means "no row" from both sources alike — which is the distinction
  /// [_decodeFastingSchedule] and [_decodeFastingAppearance] depend on.
  static bool _decodeBool(String? raw, bool defaultValue) =>
      raw == null ? defaultValue : raw == 'true';

  static int _decodeInt(String? raw, int defaultValue) =>
      raw == null ? defaultValue : (int.tryParse(raw) ?? defaultValue);

  // Helper methods for type conversion
  Future<bool> _getBool(String key, bool defaultValue) async {
    final value = await _db.userSettingsDao.getValue(key);
    return _decodeBool(value, defaultValue);
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
  MarkdownColorPalette _decodeColorPalette(String? raw) {
    final source = raw ?? SettingsKeys.defaultMarkdownCustomColors;
    final cached = _colorPalette;
    if (cached != null && cached.source == source) return cached;
    return _colorPalette = MarkdownColorPalette.decode(source);
  }

  Future<MarkdownColorPalette> getColorPalette() async {
    return _decodeColorPalette(
      await _db.userSettingsDao.getValue(SettingsKeys.markdownCustomColors),
    );
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
    return _decodeInt(value, defaultValue);
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

  // Editor settings - Vocabulary autocomplete
  Future<bool> getVocabularySuggestionsEnabled() async {
    return _getBool(
      SettingsKeys.vocabularySuggestionsEnabled,
      SettingsKeys.defaultVocabularySuggestionsEnabled,
    );
  }

  Future<void> setVocabularySuggestionsEnabled(bool value) async {
    await _setBool(SettingsKeys.vocabularySuggestionsEnabled, value);
  }

  /// The character that opens the suggestion bar. Anything other than a single
  /// character from [VocabularyTrigger.availableTriggers] falls back to the
  /// default, so a corrupted row can never disable the feature silently.
  Future<String> getVocabularyTriggerChar() async {
    final stored = await _db.userSettingsDao.getValue(
      SettingsKeys.vocabularyTriggerChar,
    );
    if (stored == null || stored.length != 1) {
      return SettingsKeys.defaultVocabularyTriggerChar;
    }
    if (!VocabularyTrigger.availableTriggers.contains(stored)) {
      return SettingsKeys.defaultVocabularyTriggerChar;
    }
    return stored;
  }

  Future<void> setVocabularyTriggerChar(String value) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.vocabularyTriggerChar,
      value,
    );
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

  // Calendar - character budget for an event description. Clamped on both
  // sides of the boundary so a hand-edited or future-written value can never
  // leave the editor unable to save anything.
  Future<int> getEventDescriptionLimit() async {
    final stored = await _getInt(
      SettingsKeys.eventDescriptionLimit,
      SettingsKeys.defaultEventDescriptionLimit,
    );
    return stored.clamp(
      SettingsKeys.minEventDescriptionLimit,
      SettingsKeys.maxEventDescriptionLimit,
    );
  }

  Future<void> setEventDescriptionLimit(int value) async {
    await _setInt(
      SettingsKeys.eventDescriptionLimit,
      value.clamp(
        SettingsKeys.minEventDescriptionLimit,
        SettingsKeys.maxEventDescriptionLimit,
      ),
    );
  }

  // Calendar appearance - today highlight style.
  static CalendarTodayStyle _decodeCalendarTodayStyle(String? raw) =>
      CalendarTodayStyle.fromName(
        raw ?? SettingsKeys.defaultCalendarTodayStyle,
      );

  Future<CalendarTodayStyle> getCalendarTodayStyle() async {
    return _decodeCalendarTodayStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarTodayStyle),
    );
  }

  Future<void> setCalendarTodayStyle(CalendarTodayStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarTodayStyle,
      style.name,
    );
  }

  // Calendar appearance - event marker style (bars / dots).
  static CalendarMarkerStyle _decodeCalendarMarkerStyle(String? raw) =>
      CalendarMarkerStyle.fromName(
        raw ?? SettingsKeys.defaultCalendarMarkerStyle,
      );

  Future<CalendarMarkerStyle> getCalendarMarkerStyle() async {
    return _decodeCalendarMarkerStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarMarkerStyle),
    );
  }

  Future<void> setCalendarMarkerStyle(CalendarMarkerStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarMarkerStyle,
      style.name,
    );
  }

  // Calendar appearance - first day of the week.
  static CalendarWeekStart _decodeCalendarWeekStart(String? raw) =>
      CalendarWeekStart.fromName(raw ?? SettingsKeys.defaultCalendarWeekStart);

  Future<CalendarWeekStart> getCalendarWeekStart() async {
    return _decodeCalendarWeekStart(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarWeekStart),
    );
  }

  Future<void> setCalendarWeekStart(CalendarWeekStart start) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarWeekStart,
      start.name,
    );
  }

  // Calendar appearance - custom highlight accent (null = theme primary).
  static int? _decodeCalendarAccentColor(String? raw) =>
      (raw == null || raw.isEmpty) ? null : int.tryParse(raw);

  Future<int?> getCalendarAccentColor() async {
    return _decodeCalendarAccentColor(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarAccentColor),
    );
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

  Future<bool> getCalendarShowRecurrenceLabels() async {
    return _getBool(
      SettingsKeys.calendarShowRecurrenceLabels,
      SettingsKeys.defaultCalendarShowRecurrenceLabels,
    );
  }

  Future<void> setCalendarShowRecurrenceLabels(bool value) async {
    await _setBool(SettingsKeys.calendarShowRecurrenceLabels, value);
  }

  // Calendar appearance - how missed occurrences render (faded / hidden).
  static CalendarMissedDisplay _decodeCalendarMissedDisplay(String? raw) =>
      CalendarMissedDisplay.fromName(
        raw ?? SettingsKeys.defaultCalendarMissedDisplay,
      );

  Future<CalendarMissedDisplay> getCalendarMissedDisplay() async {
    return _decodeCalendarMissedDisplay(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarMissedDisplay),
    );
  }

  Future<void> setCalendarMissedDisplay(CalendarMissedDisplay display) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarMissedDisplay,
      display.name,
    );
  }

  // Calendar appearance - wash day cells with their top event's color.
  Future<bool> getCalendarEventTint() async {
    return _getBool(
      SettingsKeys.calendarEventTint,
      SettingsKeys.defaultCalendarEventTint,
    );
  }

  Future<void> setCalendarEventTint(bool value) async {
    await _setBool(SettingsKeys.calendarEventTint, value);
  }

  // Calendar appearance - which tint source wins a contested day.
  static CalendarTintConflict _decodeCalendarTintConflict(String? raw) =>
      CalendarTintConflict.fromName(
        raw ?? SettingsKeys.defaultCalendarTintConflict,
      );

  Future<CalendarTintConflict> getCalendarTintConflict() async {
    return _decodeCalendarTintConflict(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarTintConflict),
    );
  }

  Future<void> setCalendarTintConflict(CalendarTintConflict conflict) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarTintConflict,
      conflict.name,
    );
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
      periodMode: AgendaPeriodMode.fromName(
        await _db.userSettingsDao.getValue(
          SettingsKeys.calendarUpcomingPeriodMode,
        ),
      ),
      rangeDays: rangeDays,
      priorities: await _readUpcomingPriorities(),
      customStart: customStart,
      customEnd: customEnd,
      query:
          await _db.userSettingsDao.getValue(
            SettingsKeys.calendarUpcomingQuery,
          ) ??
          '',
      showHolidays: await _getBool(
        SettingsKeys.calendarUpcomingShowHolidays,
        SettingsKeys.defaultCalendarUpcomingShowHolidays,
      ),
      showFasting: await _getBool(
        SettingsKeys.calendarUpcomingShowFasting,
        SettingsKeys.defaultCalendarUpcomingShowFasting,
      ),
      eventDisplay: await _readUpcomingEventDisplay(),
      fastingDisplay: await _readUpcomingFastingDisplay(),
      holidayDisplay: AgendaHolidayDisplay.fromName(
        await _db.userSettingsDao.getValue(
              SettingsKeys.calendarUpcomingHolidayDisplay,
            ) ??
            SettingsKeys.defaultCalendarUpcomingHolidayDisplay,
      ),
      followSelectedDay: await _getBool(
        SettingsKeys.calendarUpcomingFollowSelectedDay,
        SettingsKeys.defaultCalendarUpcomingFollowSelectedDay,
      ),
      eventType: AgendaEventType.fromName(
        await _db.userSettingsDao.getValue(
          SettingsKeys.calendarUpcomingEventType,
        ),
      ),
      categoryIds: await _readUpcomingCategoryIds(),
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

  /// Reads the event presentation, falling back to the superseded
  /// `collapse_recurring` boolean when the new key has never been written
  /// (`true` was one row per event, `false` one row per occurrence). A
  /// read-time fallback rather than a migration pass, exactly like
  /// [_readUpcomingFastingDisplay].
  Future<AgendaEventDisplay> _readUpcomingEventDisplay() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingEventDisplay,
    );
    if (raw != null) return AgendaEventDisplay.fromName(raw);
    final legacy = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingCollapseRecurring,
    );
    if (legacy == null) {
      return AgendaEventDisplay.fromName(
        SettingsKeys.defaultCalendarUpcomingEventDisplay,
      );
    }
    return legacy == 'true'
        ? AgendaEventDisplay.perEvent
        : AgendaEventDisplay.everyOccurrence;
  }

  /// Reads the fasting presentation, falling back to the superseded
  /// `collapse_fasting` boolean when the new key has never been written
  /// (`true` was one row per period, `false` one row per day). A read-time
  /// fallback rather than a migration pass, exactly like the schedule's
  /// legacy weekday CSV — so nobody's configuration resets on update.
  Future<AgendaFastingDisplay> _readUpcomingFastingDisplay() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingFastingDisplay,
    );
    if (raw != null) return AgendaFastingDisplay.fromName(raw);
    final legacy = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingCollapseFasting,
    );
    if (legacy == null) {
      return AgendaFastingDisplay.fromName(
        SettingsKeys.defaultCalendarUpcomingFastingDisplay,
      );
    }
    return legacy == 'true'
        ? AgendaFastingDisplay.periods
        : AgendaFastingDisplay.everyDay;
  }

  Future<Set<String>> _readUpcomingCategoryIds() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingCategories,
    );
    if (raw == null) return const {};
    return UpcomingAgendaFilters.decodeCategories(raw);
  }

  /// Persists every upcoming-agenda filter. Callers debounce the text query
  /// themselves; the discrete choices are cheap enough to write on change.
  Future<void> saveUpcomingAgendaFilters(UpcomingAgendaFilters filters) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingPeriodMode,
      filters.periodMode.name,
    );
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
      SettingsKeys.calendarUpcomingShowHolidays,
      filters.showHolidays,
    );
    await _setBool(
      SettingsKeys.calendarUpcomingShowFasting,
      filters.showFasting,
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingEventDisplay,
      filters.eventDisplay.name,
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingFastingDisplay,
      filters.fastingDisplay.name,
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingHolidayDisplay,
      filters.holidayDisplay.name,
    );
    await _setBool(
      SettingsKeys.calendarUpcomingFollowSelectedDay,
      filters.followSelectedDay,
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingEventType,
      filters.eventType.name,
    );
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCategories,
      UpcomingAgendaFilters.encodeCategories(filters.categoryIds),
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

  /// How many icon keys the "Recently used" section remembers. Two rows of
  /// six at the picker's tile size — enough to hold a habit, short enough
  /// that the section never competes with the catalog below it.
  static const int recentIconLimit = 12;

  /// The icon keys picked most recently, newest first.
  ///
  /// **Unknown keys are dropped on read**, the forward-compatible parsing
  /// every calendar setting uses: icon keys are additive-only but an icon may
  /// be *retired* from the catalog, and a retired key must leave this list
  /// rather than render an empty tile. Duplicates are collapsed for the same
  /// reason the writer de-duplicates — a list written by an older build is
  /// still input.
  Future<List<String>> getRecentIconKeys() async {
    final raw = await _db.userSettingsDao.getValue(SettingsKeys.recentIconKeys);
    if (raw == null || raw.isEmpty) return const [];
    final keys = <String>[];
    final seen = <String>{};
    for (final part in raw.split(',')) {
      final key = part.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      if (CalendarIcons.forKey(key) == null) continue;
      keys.add(key);
      if (keys.length == recentIconLimit) break;
    }
    return keys;
  }

  /// Moves [key] to the front of the recent list, capped at
  /// [recentIconLimit]. Re-picking an icon promotes it rather than adding a
  /// second copy.
  Future<void> recordRecentIconKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    final current = await getRecentIconKeys();
    final next = <String>[
      trimmed,
      for (final existing in current)
        if (existing != trimmed) existing,
    ];
    if (next.length > recentIconLimit) {
      next.removeRange(recentIconLimit, next.length);
    }
    await _db.userSettingsDao.setValue(
      SettingsKeys.recentIconKeys,
      next.join(','),
    );
  }

  // Calendar - Enabled religious-fasting traditions (empty set = off).
  static Set<FastingTradition> _decodeFastingTraditions(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    final traditions = <FastingTradition>{};
    for (final part in raw.split(',')) {
      final tradition = FastingTradition.fromName(part.trim());
      if (tradition != null) traditions.add(tradition);
    }
    return traditions;
  }

  Future<Set<FastingTradition>> getFastingTraditions() async {
    return _decodeFastingTraditions(
      await _db.userSettingsDao.getValue(
        SettingsKeys.calendarFastingTraditions,
      ),
    );
  }

  Future<void> setFastingTraditions(Set<FastingTradition> traditions) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarFastingTraditions,
      traditions.map((t) => t.name).join(','),
    );
  }

  /// Per-tradition fasting look & feel. When the appearance key is absent,
  /// the retired global style key seeds every tradition, so upgrading never
  /// silently resets someone's chosen look.
  static FastingAppearance _decodeFastingAppearance(
    String? raw,
    String? legacyStyle,
  ) {
    if (raw != null && raw.isNotEmpty) {
      return FastingAppearance.decode(raw);
    }
    return FastingAppearance.decode(
      null,
      fallbackStyle: legacyStyle == null
          ? null
          : FastingDisplayStyle.fromName(legacyStyle),
    );
  }

  Future<FastingAppearance> getFastingAppearance() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarFastingAppearance,
    );
    return _decodeFastingAppearance(
      raw,
      // Only reached when the primary key is absent, so the retired key is
      // not read on the common path.
      (raw != null && raw.isNotEmpty)
          ? null
          : await _db.userSettingsDao.getValue(
              SettingsKeys.calendarFastingStyle,
            ),
    );
  }

  Future<void> setFastingAppearance(FastingAppearance appearance) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarFastingAppearance,
      appearance.encode(),
    );
  }

  Future<bool> getFastingOrthodoxGreatFasts() async {
    return _getBool(SettingsKeys.calendarFastingOrthodoxGreatFasts, true);
  }

  Future<void> setFastingOrthodoxGreatFasts(bool value) async {
    await _setBool(SettingsKeys.calendarFastingOrthodoxGreatFasts, value);
  }

  /// The personal practice schedule. When the JSON key is absent the retired
  /// weekday CSV seeds it, so upgrading never silently resets someone's
  /// practice — including the deliberate "no weekly fast" empty string. That
  /// is why the absent-vs-empty distinction is resolved here rather than
  /// inside the decoder: a null row means the weekdays were never chosen.
  /// [legacyWeekdayCsv] must stay nullable all the way down: `null` means the
  /// weekdays were never chosen, `''` means a deliberate "no weekly fast".
  static FastingSchedule _decodeFastingSchedule(
    String? raw,
    String? legacyWeekdayCsv,
  ) {
    if (raw != null && raw.isNotEmpty) return FastingSchedule.decode(raw);
    return FastingSchedule.decode(null, legacyWeekdayCsv: legacyWeekdayCsv);
  }

  Future<FastingSchedule> getFastingSchedule() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarFastingSchedule,
    );
    return _decodeFastingSchedule(
      raw,
      (raw != null && raw.isNotEmpty)
          ? null
          : await _db.userSettingsDao.getValue(
              SettingsKeys.calendarFastingWeekdays,
            ),
    );
  }

  Future<void> setFastingSchedule(FastingSchedule schedule) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarFastingSchedule,
      schedule.encode(),
    );
  }

  /// Keys [_decodeCalendarAppearance] reads. Listed explicitly so the bulk
  /// read stays O(keys): `user_settings` also holds a `note_position_<id>` row
  /// per note, so a full-table read would scale with the note count on the
  /// pre-first-paint path this is meant to speed up.
  static const List<String> _calendarAppearanceKeys = [
    SettingsKeys.calendarTodayStyle,
    SettingsKeys.calendarMarkerStyle,
    SettingsKeys.calendarWeekStart,
    SettingsKeys.calendarAccentColor,
    SettingsKeys.calendarHighlightWeekends,
    SettingsKeys.calendarShowWeekNumbers,
    SettingsKeys.calendarMaxDayBars,
    SettingsKeys.calendarShowRecurrenceLabels,
    SettingsKeys.calendarMissedDisplay,
    SettingsKeys.calendarEventTint,
    SettingsKeys.calendarTintConflict,
  ];

  static const List<String> _calendarPageKeys = [
    ..._calendarAppearanceKeys,
    SettingsKeys.markdownCustomColors,
    SettingsKeys.calendarFastingTraditions,
    SettingsKeys.calendarFastingAppearance,
    SettingsKeys.calendarFastingStyle,
    SettingsKeys.calendarFastingOrthodoxGreatFasts,
    SettingsKeys.calendarFastingSchedule,
    SettingsKeys.calendarFastingWeekdays,
  ];

  static CalendarAppearance _decodeCalendarAppearance(
    Map<String, String> values,
  ) {
    return CalendarAppearance(
      todayStyle: _decodeCalendarTodayStyle(
        values[SettingsKeys.calendarTodayStyle],
      ),
      markerStyle: _decodeCalendarMarkerStyle(
        values[SettingsKeys.calendarMarkerStyle],
      ),
      weekStart: _decodeCalendarWeekStart(
        values[SettingsKeys.calendarWeekStart],
      ),
      accentColorValue: _decodeCalendarAccentColor(
        values[SettingsKeys.calendarAccentColor],
      ),
      highlightWeekends: _decodeBool(
        values[SettingsKeys.calendarHighlightWeekends],
        SettingsKeys.defaultCalendarHighlightWeekends,
      ),
      showWeekNumbers: _decodeBool(
        values[SettingsKeys.calendarShowWeekNumbers],
        SettingsKeys.defaultCalendarShowWeekNumbers,
      ),
      maxDayBars: _decodeInt(
        values[SettingsKeys.calendarMaxDayBars],
        SettingsKeys.defaultCalendarMaxDayBars,
      ),
      showRecurrenceLabels: _decodeBool(
        values[SettingsKeys.calendarShowRecurrenceLabels],
        SettingsKeys.defaultCalendarShowRecurrenceLabels,
      ),
      missedDisplay: _decodeCalendarMissedDisplay(
        values[SettingsKeys.calendarMissedDisplay],
      ),
      eventTint: _decodeBool(
        values[SettingsKeys.calendarEventTint],
        SettingsKeys.defaultCalendarEventTint,
      ),
      tintConflict: _decodeCalendarTintConflict(
        values[SettingsKeys.calendarTintConflict],
      ),
    );
  }

  /// Loads every calendar look & feel option in one call.
  ///
  /// One statement rather than eleven: resolving this after the first frame
  /// visibly re-lays-out the grid, and eleven sequential single-row awaits are
  /// eleven round trips to the drift isolate whose latencies add rather than
  /// overlap.
  Future<CalendarAppearance> getCalendarAppearance() async {
    return _decodeCalendarAppearance(
      await _db.userSettingsDao.getValuesFor(_calendarAppearanceKeys),
    );
  }

  /// Every setting `CalendarPage` needs before it can paint, in one statement.
  ///
  /// `initState` previously issued 16-18 sequential single-row SELECTs here.
  /// The decoders are the same ones the individual getters use, so the bulk
  /// path cannot drift from them.
  Future<
    ({
      CalendarAppearance appearance,
      MarkdownColorPalette palette,
      Set<FastingTradition> fastingTraditions,
      FastingAppearance fastingAppearance,
      bool fastingGreatFasts,
      FastingSchedule fastingSchedule,
    })
  >
  getCalendarPageSettings() async {
    final values = await _db.userSettingsDao.getValuesFor(_calendarPageKeys);
    return (
      appearance: _decodeCalendarAppearance(values),
      palette: _decodeColorPalette(values[SettingsKeys.markdownCustomColors]),
      fastingTraditions: _decodeFastingTraditions(
        values[SettingsKeys.calendarFastingTraditions],
      ),
      fastingAppearance: _decodeFastingAppearance(
        values[SettingsKeys.calendarFastingAppearance],
        values[SettingsKeys.calendarFastingStyle],
      ),
      fastingGreatFasts: _decodeBool(
        values[SettingsKeys.calendarFastingOrthodoxGreatFasts],
        true,
      ),
      fastingSchedule: _decodeFastingSchedule(
        values[SettingsKeys.calendarFastingSchedule],
        values[SettingsKeys.calendarFastingWeekdays],
      ),
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

  /// Ids of the markdown settings sections the user left folded. An empty
  /// set means everything is expanded.
  Future<Set<String>> getCollapsedMarkdownSections() async {
    final value = await _db.userSettingsDao.getValue(
      SettingsKeys.markdownSectionsCollapsed,
    );
    if (value == null || value.isEmpty) return <String>{};
    return value.split(',').where((id) => id.isNotEmpty).toSet();
  }

  Future<void> setCollapsedMarkdownSections(Set<String> sectionIds) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.markdownSectionsCollapsed,
      sectionIds.join(','),
    );
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

  /// The cached pairing state for this database. A cache, not the truth: the
  /// server answers which active pair contains the signed-in uid, and
  /// `PairingService` reconciles this against it on sign-in and resume.
  Future<PairingSettings> getPairingSettings() async {
    final expiresAt = await _db.userSettingsDao.getValue(
      SettingsKeys.pairingPendingExpiresAt,
    );
    return PairingSettings(
      pairId: _nonEmpty(
        await _db.userSettingsDao.getValue(SettingsKeys.pairingPairId),
      ),
      accountUid: _nonEmpty(
        await _db.userSettingsDao.getValue(SettingsKeys.pairingAccountUid),
      ),
      partnerUid: _nonEmpty(
        await _db.userSettingsDao.getValue(SettingsKeys.pairingPartnerUid),
      ),
      partnerName: _nonEmpty(
        await _db.userSettingsDao.getValue(SettingsKeys.pairingPartnerName),
      ),
      pendingCode: _nonEmpty(
        await _db.userSettingsDao.getValue(SettingsKeys.pairingPendingCode),
      ),
      pendingExpiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(expiresAt) ?? 0,
              isUtc: true,
            ),
      endedNoticePending: await _getBool(
        SettingsKeys.pairingEndedNotice,
        false,
      ),
    );
  }

  /// Transactional on purpose: these seven rows are one value. A partial write
  /// (a `pairId` without the account it belongs to) is exactly the state
  /// [PairingSettings] exists to make unrepresentable.
  Future<void> setPairingSettings(PairingSettings settings) {
    return _db.transaction(() async {
      await _write(SettingsKeys.pairingPairId, settings.pairId);
      await _write(SettingsKeys.pairingAccountUid, settings.accountUid);
      await _write(SettingsKeys.pairingPartnerUid, settings.partnerUid);
      await _write(SettingsKeys.pairingPartnerName, settings.partnerName);
      await _write(SettingsKeys.pairingPendingCode, settings.pendingCode);
      await _write(
        SettingsKeys.pairingPendingExpiresAt,
        settings.pendingExpiresAt?.toUtc().millisecondsSinceEpoch.toString(),
      );
      await _setBool(
        SettingsKeys.pairingEndedNotice,
        settings.endedNoticePending,
      );
    });
  }

  /// Writes a value, or removes the row entirely when it is null — "absent"
  /// and "empty string" must not be the same state for pairing.
  Future<void> _write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _db.userSettingsDao.deleteValue(key);
    } else {
      await _db.userSettingsDao.setValue(key, value);
    }
  }

  String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}

/// The pairing rows of `user_settings`, read and written as one value so a
/// half-updated pairing (a `pairId` without the account it belongs to) is not
/// representable.
class PairingSettings extends Equatable {
  final String? pairId;
  final String? accountUid;
  final String? partnerUid;
  final String? partnerName;
  final String? pendingCode;
  final DateTime? pendingExpiresAt;
  final bool endedNoticePending;

  const PairingSettings({
    this.pairId,
    this.accountUid,
    this.partnerUid,
    this.partnerName,
    this.pendingCode,
    this.pendingExpiresAt,
    this.endedNoticePending = false,
  });

  static const PairingSettings empty = PairingSettings();

  bool get isPaired => pairId != null;

  bool get hasPendingInvite => pendingCode != null;

  /// Non-clearing by design: every field that needs to become null is cleared
  /// by building a fresh instance instead, so no call site can drop a field by
  /// forgetting to pass it.
  PairingSettings copyWith({
    String? pairId,
    String? accountUid,
    String? partnerUid,
    String? partnerName,
    String? pendingCode,
    DateTime? pendingExpiresAt,
    bool? endedNoticePending,
  }) => PairingSettings(
    pairId: pairId ?? this.pairId,
    accountUid: accountUid ?? this.accountUid,
    partnerUid: partnerUid ?? this.partnerUid,
    partnerName: partnerName ?? this.partnerName,
    pendingCode: pendingCode ?? this.pendingCode,
    pendingExpiresAt: pendingExpiresAt ?? this.pendingExpiresAt,
    endedNoticePending: endedNoticePending ?? this.endedNoticePending,
  );

  PairingSettings clearPendingInvite() => PairingSettings(
    pairId: pairId,
    accountUid: accountUid,
    partnerUid: partnerUid,
    partnerName: partnerName,
    endedNoticePending: endedNoticePending,
  );

  @override
  List<Object?> get props => [
    pairId,
    accountUid,
    partnerUid,
    partnerName,
    pendingCode,
    pendingExpiresAt,
    endedNoticePending,
  ];
}
