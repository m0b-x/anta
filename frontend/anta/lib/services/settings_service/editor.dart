part of '../settings_service.dart';

/// Anything other than a single character from
/// [VocabularyTrigger.availableTriggers] falls back to the default, so a
/// corrupted row can never disable the feature silently.
String _decodeVocabularyTrigger(String? raw) {
  if (raw == null || raw.length != 1) {
    return SettingsKeys.defaultVocabularyTriggerChar;
  }
  if (!VocabularyTrigger.availableTriggers.contains(raw)) {
    return SettingsKeys.defaultVocabularyTriggerChar;
  }
  return raw;
}

/// Every row [getEditorSettings] decodes. Keyed rather than a full-table
/// read for the same reason the calendar bundle is: `user_settings` also
/// holds one `note_position_<id>` row per note the user has ever opened.
const List<String> _editorSettingsKeys = [
  SettingsKeys.noteSwipeEnabled,
  SettingsKeys.showStatsBar,
  SettingsKeys.liveMarkdownRendering,
  SettingsKeys.showLineNumbers,
  SettingsKeys.wordWrap,
  SettingsKeys.showCursorLine,
  SettingsKeys.autoBreakLongLines,
  SettingsKeys.previewWhenKeyboardHidden,
  SettingsKeys.scrollCursorOnKeyboard,
  SettingsKeys.previewModeEnabled,
  SettingsKeys.showPreviewScrollbar,
  SettingsKeys.previewLinesPerChunk,
  SettingsKeys.toolbarShortcutRatio,
  SettingsKeys.toolbarSplitEnabled,
  SettingsKeys.toolbarUndoRedoPinned,
  SettingsKeys.toolbarUtilityConfig,
  SettingsKeys.vocabularySuggestionsEnabled,
  SettingsKeys.vocabularyTriggerChar,
  SettingsKeys.editorFontSize,
  SettingsKeys.previewFontSize,
  SettingsKeys.hapticFeedback,
  SettingsKeys.autoSaveEnabled,
  SettingsKeys.autoSaveInterval,
];

/// [UtilityButtonConfig.decode] parses JSON the user never types by hand,
/// but it is JSON all the same: a truncated or hand-edited row would throw
/// out of the decode and take the whole editor open with it. An unreadable
/// row is treated exactly like an absent one — the toolbar the user gets is
/// the default toolbar, never no toolbar.
List<UtilityButtonConfig> _decodeUtilityConfig(String? raw) {
  if (raw == null || raw.isEmpty) return UtilityButtonConfig.defaults();
  try {
    return UtilityButtonConfig.decode(raw);
  } catch (_) {
    return UtilityButtonConfig.defaults();
  }
}

/// The editor and the preview: live rendering, line numbers, wrapping,
/// vocabulary suggestions, the keyboard's behaviour, the text sizes — and
/// the markdown bar's layout.
mixin _EditorSettings on _GeneralSettings {
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

  Future<bool> getPreviewModeEnabled() async {
    return _getBool(
      SettingsKeys.previewModeEnabled,
      SettingsKeys.defaultPreviewModeEnabled,
    );
  }

  Future<void> setPreviewModeEnabled(bool value) async {
    await _setBool(SettingsKeys.previewModeEnabled, value);
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

  /// The character that opens the suggestion bar.
  Future<String> getVocabularyTriggerChar() async {
    return _decodeVocabularyTrigger(
      await _db.userSettingsDao.getValue(SettingsKeys.vocabularyTriggerChar),
    );
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

  /// Every setting the note editor page needs before it can mount, in one
  /// statement.
  ///
  /// `initState` issued 17 sequential single-row SELECTs plus two raw DAO
  /// reads for the font sizes; each await is its own round trip to the drift
  /// isolate, so the latencies add rather than overlap. That cost is on the
  /// critical path now in a way it was not before: the editor's `ValueKey`
  /// depends on [EditorSettings.liveMarkdownRendering], so the loading
  /// skeleton stays up until this lands rather than letting the editor mount
  /// and remount.
  ///
  /// Flushes debounced writes first. The page re-reads this bundle when it
  /// returns from the settings page, and a font size adjusted a moment before
  /// leaving must not read back stale.
  ///
  /// The decoders are the ones the single-row getters use, so the bulk path
  /// cannot drift from them.
  Future<EditorSettings> getEditorSettings() async {
    await flushPendingWrites();
    final values = await _db.userSettingsDao.getValuesFor(_editorSettingsKeys);
    return EditorSettings(
      noteSwipeEnabled: _decodeBool(
        values[SettingsKeys.noteSwipeEnabled],
        SettingsKeys.defaultNoteSwipeEnabled,
      ),
      showStatsBar: _decodeBool(
        values[SettingsKeys.showStatsBar],
        SettingsKeys.defaultShowStatsBar,
      ),
      liveMarkdownRendering: _decodeBool(
        values[SettingsKeys.liveMarkdownRendering],
        SettingsKeys.defaultLiveMarkdownRendering,
      ),
      showLineNumbers: _decodeBool(
        values[SettingsKeys.showLineNumbers],
        SettingsKeys.defaultShowLineNumbers,
      ),
      wordWrap: _decodeBool(
        values[SettingsKeys.wordWrap],
        SettingsKeys.defaultWordWrap,
      ),
      showCursorLine: _decodeBool(
        values[SettingsKeys.showCursorLine],
        SettingsKeys.defaultShowCursorLine,
      ),
      autoBreakLongLines: _decodeBool(
        values[SettingsKeys.autoBreakLongLines],
        SettingsKeys.defaultAutoBreakLongLines,
      ),
      previewWhenKeyboardHidden: _decodeBool(
        values[SettingsKeys.previewWhenKeyboardHidden],
        SettingsKeys.defaultPreviewWhenKeyboardHidden,
      ),
      scrollCursorOnKeyboard: _decodeBool(
        values[SettingsKeys.scrollCursorOnKeyboard],
        SettingsKeys.defaultScrollCursorOnKeyboard,
      ),
      previewModeEnabled: _decodeBool(
        values[SettingsKeys.previewModeEnabled],
        SettingsKeys.defaultPreviewModeEnabled,
      ),
      showPreviewScrollbar: _decodeBool(
        values[SettingsKeys.showPreviewScrollbar],
        SettingsKeys.defaultShowPreviewScrollbar,
      ),
      previewLinesPerChunk: _decodeInt(
        values[SettingsKeys.previewLinesPerChunk],
        SettingsKeys.defaultPreviewLinesPerChunk,
      ),
      toolbarShortcutRatio: _decodeDouble(
        values[SettingsKeys.toolbarShortcutRatio],
        SettingsKeys.defaultToolbarShortcutRatio,
      ),
      toolbarSplitEnabled: _decodeBool(
        values[SettingsKeys.toolbarSplitEnabled],
        SettingsKeys.defaultToolbarSplitEnabled,
      ),
      toolbarUndoRedoPinned: _decodeBool(
        values[SettingsKeys.toolbarUndoRedoPinned],
        SettingsKeys.defaultToolbarUndoRedoPinned,
      ),
      toolbarUtilityConfig: _decodeUtilityConfig(
        values[SettingsKeys.toolbarUtilityConfig],
      ),
      vocabularySuggestionsEnabled: _decodeBool(
        values[SettingsKeys.vocabularySuggestionsEnabled],
        SettingsKeys.defaultVocabularySuggestionsEnabled,
      ),
      vocabularyTriggerChar: _decodeVocabularyTrigger(
        values[SettingsKeys.vocabularyTriggerChar],
      ),
      editorFontSize: _decodeDouble(
        values[SettingsKeys.editorFontSize],
        FontConstants.defaultFontSize,
      ),
      previewFontSize: _decodeDouble(
        values[SettingsKeys.previewFontSize],
        FontConstants.defaultFontSize,
      ),
      hapticFeedback: _decodeBool(
        values[SettingsKeys.hapticFeedback],
        SettingsKeys.defaultHapticFeedback,
      ),
      autoSaveEnabled: _decodeBool(
        values[SettingsKeys.autoSaveEnabled],
        SettingsKeys.defaultAutoSaveEnabled,
      ),
      autoSaveIntervalSeconds: _decodeInt(
        values[SettingsKeys.autoSaveInterval],
        SettingsKeys.defaultAutoSaveInterval,
      ),
    );
  }

  // Font sizes - the editor's own text size and the preview's
  Future<double> getEditorFontSize() async {
    return _decodeDouble(
      await _db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
      FontConstants.defaultFontSize,
    );
  }

  /// Debounced: the size is driven by repeated +/- taps, so the write waits
  /// for the taps to stop. Only this key is written — the preview size stays
  /// untouched, and stays absent on an install that never changed it.
  Future<void> setEditorFontSize(double value) async {
    _scheduleWrite(SettingsKeys.editorFontSize, value.toString());
  }

  Future<double> getPreviewFontSize() async {
    return _decodeDouble(
      await _db.userSettingsDao.getValue(SettingsKeys.previewFontSize),
      FontConstants.defaultFontSize,
    );
  }

  /// Debounced, like [setEditorFontSize].
  Future<void> setPreviewFontSize(double value) async {
    _scheduleWrite(SettingsKeys.previewFontSize, value.toString());
  }

  // Toolbar settings - Shortcut/utility ratio
  Future<double> getToolbarShortcutRatio() async {
    return _decodeDouble(
      await _db.userSettingsDao.getValue(SettingsKeys.toolbarShortcutRatio),
      SettingsKeys.defaultToolbarShortcutRatio,
    );
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

  Future<bool> getToolbarUndoRedoPinned() async {
    return _getBool(
      SettingsKeys.toolbarUndoRedoPinned,
      SettingsKeys.defaultToolbarUndoRedoPinned,
    );
  }

  Future<void> setToolbarUndoRedoPinned(bool value) async {
    await _setBool(SettingsKeys.toolbarUndoRedoPinned, value);
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
    return _decodeUtilityConfig(
      await _db.userSettingsDao.getValue(SettingsKeys.toolbarUtilityConfig),
    );
  }

  Future<void> setToolbarUtilityConfig(
    List<UtilityButtonConfig> configs,
  ) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.toolbarUtilityConfig,
      UtilityButtonConfig.encode(configs),
    );
  }
}
