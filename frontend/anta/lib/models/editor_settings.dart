import 'package:equatable/equatable.dart';

import '../constants/font_constants.dart';
import '../constants/settings_keys.dart';
import 'utility_button_config.dart';

/// Value-equal snapshot of every setting the note editor page reads.
///
/// One object rather than nineteen `State` fields, for two reasons. The page
/// re-reads all of them on `didPopNext`, and value equality is what lets it
/// tell "the user changed something in settings" from "the user came back
/// without touching anything" — the difference between a repaint and none.
/// And the editor's `ValueKey` is derived from [liveMarkdownRendering], so the
/// whole bundle has to have landed before the first `CodeEditor` mounts or the
/// key changes underneath it and the editor remounts (B4).
///
/// Decoded in one statement by `SettingsService.getEditorSettings`; every
/// default here is the same `SettingsKeys.default*` constant the single-row
/// getters use, so the two paths cannot disagree about an absent row.
class EditorSettings extends Equatable {
  /// Swipe-to-navigate between sibling notes.
  final bool noteSwipeEnabled;

  /// Word/character/line counters under the editor.
  final bool showStatsBar;

  /// Obsidian-style rendering in the editor itself. Turning it off is one of
  /// the two ways the deprecated preview becomes reachable — see [canPreview].
  final bool liveMarkdownRendering;

  final bool showLineNumbers;
  final bool wordWrap;
  final bool showCursorLine;

  /// Reformat over-long pasted lines to the editor's width.
  final bool autoBreakLongLines;

  /// The **raw stored flag**, not the effective one: the page still has to
  /// gate it on [canPreview], because a stored `true` from before the preview
  /// was deprecated must not resurrect a surface the user can no longer reach.
  final bool previewWhenKeyboardHidden;

  final bool scrollCursorOnKeyboard;

  /// Master switch for the deprecated preview surface.
  final bool previewModeEnabled;

  final bool showPreviewScrollbar;
  final int previewLinesPerChunk;

  /// Share of the toolbar width given to shortcuts rather than utilities.
  final double toolbarShortcutRatio;

  final bool toolbarSplitEnabled;

  /// Order and visibility of the toolbar's utility buttons. Never empty — an
  /// absent or unreadable row decodes to [UtilityButtonConfig.defaults].
  final List<UtilityButtonConfig> toolbarUtilityConfig;

  final bool vocabularySuggestionsEnabled;

  /// Already validated against `VocabularyTrigger.availableTriggers`: a
  /// corrupted row reads as the default rather than silently disabling
  /// autocomplete.
  final String vocabularyTriggerChar;

  final double editorFontSize;
  final double previewFontSize;

  /// Not `const`: [toolbarUtilityConfig] defaults to a freshly built list, so
  /// the fill happens in the initializer rather than in a default value. The
  /// list is stored unmodifiable because [defaults] is one shared instance —
  /// a caller reordering it in place would corrupt every later read.
  EditorSettings({
    this.noteSwipeEnabled = SettingsKeys.defaultNoteSwipeEnabled,
    this.showStatsBar = SettingsKeys.defaultShowStatsBar,
    this.liveMarkdownRendering = SettingsKeys.defaultLiveMarkdownRendering,
    this.showLineNumbers = SettingsKeys.defaultShowLineNumbers,
    this.wordWrap = SettingsKeys.defaultWordWrap,
    this.showCursorLine = SettingsKeys.defaultShowCursorLine,
    this.autoBreakLongLines = SettingsKeys.defaultAutoBreakLongLines,
    this.previewWhenKeyboardHidden =
        SettingsKeys.defaultPreviewWhenKeyboardHidden,
    this.scrollCursorOnKeyboard = SettingsKeys.defaultScrollCursorOnKeyboard,
    this.previewModeEnabled = SettingsKeys.defaultPreviewModeEnabled,
    this.showPreviewScrollbar = SettingsKeys.defaultShowPreviewScrollbar,
    this.previewLinesPerChunk = SettingsKeys.defaultPreviewLinesPerChunk,
    this.toolbarShortcutRatio = SettingsKeys.defaultToolbarShortcutRatio,
    this.toolbarSplitEnabled = SettingsKeys.defaultToolbarSplitEnabled,
    List<UtilityButtonConfig>? toolbarUtilityConfig,
    this.vocabularySuggestionsEnabled =
        SettingsKeys.defaultVocabularySuggestionsEnabled,
    this.vocabularyTriggerChar = SettingsKeys.defaultVocabularyTriggerChar,
    this.editorFontSize = FontConstants.defaultFontSize,
    this.previewFontSize = FontConstants.defaultFontSize,
  }) : toolbarUtilityConfig = List.unmodifiable(
         toolbarUtilityConfig ?? UtilityButtonConfig.defaults(),
       );

  /// What a virgin database resolves to, and what a controller reports before
  /// its first read lands.
  static final EditorSettings defaults = EditorSettings();

  /// Whether the deprecated preview surface is reachable at all.
  ///
  /// Either the user opted back into it, or live rendering is off — in which
  /// case the editor shows raw markdown and the preview is the only way to see
  /// the rendered note.
  bool get canPreview => previewModeEnabled || !liveMarkdownRendering;

  EditorSettings copyWith({
    bool? noteSwipeEnabled,
    bool? showStatsBar,
    bool? liveMarkdownRendering,
    bool? showLineNumbers,
    bool? wordWrap,
    bool? showCursorLine,
    bool? autoBreakLongLines,
    bool? previewWhenKeyboardHidden,
    bool? scrollCursorOnKeyboard,
    bool? previewModeEnabled,
    bool? showPreviewScrollbar,
    int? previewLinesPerChunk,
    double? toolbarShortcutRatio,
    bool? toolbarSplitEnabled,
    List<UtilityButtonConfig>? toolbarUtilityConfig,
    bool? vocabularySuggestionsEnabled,
    String? vocabularyTriggerChar,
    double? editorFontSize,
    double? previewFontSize,
  }) {
    return EditorSettings(
      noteSwipeEnabled: noteSwipeEnabled ?? this.noteSwipeEnabled,
      showStatsBar: showStatsBar ?? this.showStatsBar,
      liveMarkdownRendering:
          liveMarkdownRendering ?? this.liveMarkdownRendering,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      wordWrap: wordWrap ?? this.wordWrap,
      showCursorLine: showCursorLine ?? this.showCursorLine,
      autoBreakLongLines: autoBreakLongLines ?? this.autoBreakLongLines,
      previewWhenKeyboardHidden:
          previewWhenKeyboardHidden ?? this.previewWhenKeyboardHidden,
      scrollCursorOnKeyboard:
          scrollCursorOnKeyboard ?? this.scrollCursorOnKeyboard,
      previewModeEnabled: previewModeEnabled ?? this.previewModeEnabled,
      showPreviewScrollbar: showPreviewScrollbar ?? this.showPreviewScrollbar,
      previewLinesPerChunk: previewLinesPerChunk ?? this.previewLinesPerChunk,
      toolbarShortcutRatio: toolbarShortcutRatio ?? this.toolbarShortcutRatio,
      toolbarSplitEnabled: toolbarSplitEnabled ?? this.toolbarSplitEnabled,
      toolbarUtilityConfig: toolbarUtilityConfig ?? this.toolbarUtilityConfig,
      vocabularySuggestionsEnabled:
          vocabularySuggestionsEnabled ?? this.vocabularySuggestionsEnabled,
      vocabularyTriggerChar:
          vocabularyTriggerChar ?? this.vocabularyTriggerChar,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      previewFontSize: previewFontSize ?? this.previewFontSize,
    );
  }

  @override
  List<Object?> get props => [
    noteSwipeEnabled,
    showStatsBar,
    liveMarkdownRendering,
    showLineNumbers,
    wordWrap,
    showCursorLine,
    autoBreakLongLines,
    previewWhenKeyboardHidden,
    scrollCursorOnKeyboard,
    previewModeEnabled,
    showPreviewScrollbar,
    previewLinesPerChunk,
    toolbarShortcutRatio,
    toolbarSplitEnabled,
    toolbarUtilityConfig,
    vocabularySuggestionsEnabled,
    vocabularyTriggerChar,
    editorFontSize,
    previewFontSize,
  ];
}
