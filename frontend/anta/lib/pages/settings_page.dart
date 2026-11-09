import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/label_style.dart';
import '../models/restore_location_mode.dart';
import '../widgets/app_dialogs.dart';
import '../services/label_appearance_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// The app's main settings page — everything that shapes how ANTA behaves
/// day to day, grouped by the surface it affects.
///
/// Sections are grouped by *where you feel the setting*, not by what kind of
/// control it is: a swipe gesture lives with the screen it opens the drawer
/// on. The cross-cutting ones — startup, auto-save, feedback — keep their own
/// sections, and everything the live editor superseded sits last, under the
/// deprecated section's master switch.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Persisted fold state is keyed on these, so they are frozen strings, not
  // titles and not positions — renaming or reordering a section must not
  // reopen a card the user folded shut.
  static const String _sectionStartup = 'startup';
  static const String _sectionBrowsing = 'browsing';
  static const String _sectionEditor = 'editor';
  static const String _sectionAutoSave = 'autosave';
  static const String _sectionFeedback = 'feedback';
  static const String _sectionDeprecated = 'deprecated';

  SettingsService? _settings;
  bool _isLoading = true;
  Set<String> _collapsedSections = const {};

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  // Settings values
  bool _folderSwipeEnabled = true;
  bool _noteSwipeEnabled = true;
  bool _confirmDelete = true;
  bool _autoSaveEnabled = true;
  int _autoSaveInterval = 5;
  bool _showNotePreview = true;
  LabelStyle _labelStyle = LabelStyle.dot;
  bool _showStatsBar = SettingsKeys.defaultShowStatsBar;
  bool _hapticFeedback = true;
  RestoreLocationMode _restoreLocationMode = RestoreLocationMode.fromName(
    SettingsKeys.defaultRestoreLocationMode,
  );
  // Editor settings
  bool _liveMarkdownRendering = true;
  bool _showLineNumbers = false;
  bool _wordWrap = true;
  bool _showCursorLine = false;
  bool _autoBreakLongLines = true;
  bool _previewWhenKeyboardHidden = false;
  bool _scrollCursorOnKeyboard = SettingsKeys.defaultScrollCursorOnKeyboard;

  // Deprecated preview settings
  bool _previewModeEnabled = false;
  bool _showPreviewScrollbar = false;

  // Preview performance settings
  int _previewLinesPerChunk = 10;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final folderSwipe = await settings.getFolderSwipeEnabled();
    final noteSwipe = await settings.getNoteSwipeEnabled();
    final confirmDel = await settings.getConfirmDelete();
    final autoSave = await settings.getAutoSaveEnabled();
    final autoSaveInt = await settings.getAutoSaveInterval();
    final showPreview = await settings.getShowNotePreview();
    final labelStyle = await settings.getLabelStyle();
    final showStats = await settings.getShowStatsBar();
    final haptic = await settings.getHapticFeedback();
    final restoreLocationMode = await settings.getRestoreLocationMode();
    final liveMarkdownRendering = await settings.getLiveMarkdownRendering();
    final showLineNumbers = await settings.getShowLineNumbers();
    final wordWrap = await settings.getWordWrap();
    final showCursorLine = await settings.getShowCursorLine();
    final autoBreakLongLines = await settings.getAutoBreakLongLines();
    final previewWhenKeyboardHidden = await settings
        .getPreviewWhenKeyboardHidden();
    final scrollCursorOnKeyboard = await settings.getScrollCursorOnKeyboard();
    final previewModeEnabled = await settings.getPreviewModeEnabled();
    final showPreviewScrollbar = await settings.getShowPreviewScrollbar();
    final previewLinesPerChunk = await settings.getPreviewLinesPerChunk();
    final collapsedSections = await settings.getAppSettingsCollapsedSections();

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _collapsedSections = collapsedSections;
      _folderSwipeEnabled = folderSwipe;
      _noteSwipeEnabled = noteSwipe;
      _confirmDelete = confirmDel;
      _autoSaveEnabled = autoSave;
      // Clamped like the editor clamps it (record D23): a row imported or
      // edited by hand outside 1–30 would otherwise trip the slider's
      // value assertion and take the page down with it.
      _autoSaveInterval = autoSaveInt
          .clamp(
            SettingsKeys.autoSaveIntervalMinSeconds,
            SettingsKeys.autoSaveIntervalMaxSeconds,
          )
          .toInt();
      _showNotePreview = showPreview;
      _labelStyle = labelStyle;
      _showStatsBar = showStats;
      _hapticFeedback = haptic;
      _restoreLocationMode = restoreLocationMode;
      _liveMarkdownRendering = liveMarkdownRendering;
      _showLineNumbers = showLineNumbers;
      _wordWrap = wordWrap;
      _showCursorLine = showCursorLine;
      _autoBreakLongLines = autoBreakLongLines;
      _previewWhenKeyboardHidden = previewWhenKeyboardHidden;
      _scrollCursorOnKeyboard = scrollCursorOnKeyboard;
      _previewModeEnabled = previewModeEnabled;
      _showPreviewScrollbar = showPreviewScrollbar;
      _previewLinesPerChunk = previewLinesPerChunk;
      _isLoading = false;
    });
  }

  void _onHapticFeedback() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  /// Optimistic like every other row on this page: the fold is a view
  /// preference, so a failed write costs nothing worth blocking the tap for.
  Future<void> _toggleSection(String id) async {
    _onHapticFeedback();
    final next = {..._collapsedSections};
    if (!next.remove(id)) next.add(id);
    setState(() => _collapsedSections = next);
    await _settings?.setAppSettingsCollapsedSections(next);
  }

  /// Splits a localized comma-separated keyword string into search terms.
  List<String> _keywords(String csv) =>
      csv.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(
        // The hub's row name: a page titled "Settings" under the hub's
        // "Settings" told the user nothing about where they were (N98).
        title: l10n.settingsRowGeneral,
        identifier: SemanticsIds.settingsBarApp,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: FormMetrics.settingsSearchPadding,
                    child: SettingsSearchField(
                      controller: _searchController,
                      hint: l10n.searchSettings,
                      onChanged: (value) =>
                          setState(() => _query = SettingsQuery.parse(value)),
                    ),
                  ),
                  Expanded(
                    child: SettingsSectionList(
                      query: _query,
                      sections: _buildSections(l10n),
                      collapsedSections: _collapsedSections,
                      onToggleSection: _toggleSection,
                      listIdentifier: SemanticsIds.appSettingsList,
                      footer: [
                        Center(
                          child: Semantics(
                            container: true,
                            identifier: SemanticsIds.appSettingsReset,
                            child: TextButton.icon(
                              onPressed: _showResetConfirmation,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.resetToDefaults),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(AppLocalizations l10n) {
    return [
      _startupSection(l10n),
      _browsingSection(l10n),
      _editorSection(l10n),
      _autoSaveSection(l10n),
      _feedbackSection(l10n),
      _deprecatedSection(l10n),
    ];
  }

  /// First because it is the one setting about the app as a whole rather than
  /// about a screen inside it.
  SettingsSectionData _startupSection(AppLocalizations l10n) {
    return SettingsSectionData(
      id: _sectionStartup,
      icon: Icons.restore_rounded,
      title: l10n.startupSection,
      entries: [
        SettingsEntry(
          title: l10n.restoreLocation,
          description: l10n.restoreLocationDesc,
          keywords: _keywords(l10n.restoreLocationKeywords),
          identifier: SemanticsIds.appSettingsRestoreLocation,
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _restoreLocationMode,
            labels: {
              RestoreLocationMode.off: l10n.restoreLocationOff,
              RestoreLocationMode.notes: l10n.restoreLocationNotes,
              RestoreLocationMode.everything: l10n.restoreLocationEverything,
            },
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _restoreLocationMode = value);
              await _settings?.setRestoreLocationMode(value);
            },
          ),
        ),
      ],
    );
  }

  /// The folder/note browser. The folder swipe gesture belongs here rather
  /// than in a gestures-only section: it is the drawer gesture *for this
  /// screen*, and its sibling lives with the editor for the same reason.
  SettingsSectionData _browsingSection(AppLocalizations l10n) {
    return SettingsSectionData(
      id: _sectionBrowsing,
      icon: Icons.folder_open_rounded,
      title: l10n.displaySection,
      entries: [
        SettingsEntry(
          title: l10n.showNotePreview,
          description: l10n.showNotePreviewDesc,
          identifier: SemanticsIds.appSettingsNotePreview,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _showNotePreview,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _showNotePreview = value);
              await _settings?.setShowNotePreview(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.labelStyle,
          description: l10n.labelStyleDesc,
          keywords: _keywords(l10n.labelStyleKeywords),
          identifier: SemanticsIds.appSettingsLabelStyle,
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _labelStyle,
            labels: {
              LabelStyle.dot: l10n.labelStyleDot,
              LabelStyle.stripe: l10n.labelStyleStripe,
            },
            // Through the service, not the store: the browser sitting under
            // this page repaints off the published facade, so a write that
            // skipped it would only show up on the next launch.
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _labelStyle = value);
              await (await LabelAppearanceService.getInstance()).setStyle(
                value,
              );
            },
          ),
        ),
        SettingsEntry(
          title: l10n.showStatsBar,
          description: l10n.showStatsBarDesc,
          identifier: SemanticsIds.appSettingsStatsBar,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _showStatsBar,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _showStatsBar = value);
              await _settings?.setShowStatsBar(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.folderSwipeGesture,
          description: l10n.folderSwipeGestureDesc,
          keywords: _keywords(l10n.swipeKeywords),
          identifier: SemanticsIds.appSettingsFolderSwipe,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _folderSwipeEnabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _folderSwipeEnabled = value);
              await _settings?.setFolderSwipeEnabled(value);
            },
          ),
        ),
      ],
    );
  }

  SettingsSectionData _editorSection(AppLocalizations l10n) {
    return SettingsSectionData(
      id: _sectionEditor,
      icon: Icons.code_rounded,
      title: l10n.editorSection,
      entries: [
        SettingsEntry(
          title: l10n.liveMarkdownRendering,
          description: l10n.liveMarkdownRenderingDesc,
          keywords: _keywords(l10n.liveMarkdownKeywords),
          identifier: SemanticsIds.appSettingsLiveMarkdown,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _liveMarkdownRendering,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _liveMarkdownRendering = value);
              await _settings?.setLiveMarkdownRendering(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.wordWrap,
          description: l10n.wordWrapDesc,
          keywords: _keywords(l10n.wordWrapKeywords),
          identifier: SemanticsIds.appSettingsWordWrap,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _wordWrap,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _wordWrap = value);
              await _settings?.setWordWrap(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.autoBreakLongLines,
          description: l10n.autoBreakLongLinesDesc,
          keywords: _keywords(l10n.wordWrapKeywords),
          identifier: SemanticsIds.appSettingsAutoBreak,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _autoBreakLongLines,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _autoBreakLongLines = value);
              await _settings?.setAutoBreakLongLines(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.showLineNumbers,
          description: l10n.showLineNumbersDesc,
          keywords: _keywords(l10n.lineNumbersKeywords),
          identifier: SemanticsIds.appSettingsLineNumbers,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _showLineNumbers,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _showLineNumbers = value);
              await _settings?.setShowLineNumbers(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.showCursorLine,
          description: l10n.showCursorLineDesc,
          keywords: _keywords(l10n.cursorKeywords),
          identifier: SemanticsIds.appSettingsCursorLine,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _showCursorLine,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _showCursorLine = value);
              await _settings?.setShowCursorLine(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.scrollCursorOnKeyboard,
          description: l10n.scrollCursorOnKeyboardDesc,
          keywords: [
            ..._keywords(l10n.keyboardKeywords),
            ..._keywords(l10n.cursorKeywords),
          ],
          identifier: SemanticsIds.appSettingsScrollCursor,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _scrollCursorOnKeyboard,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _scrollCursorOnKeyboard = value);
              await _settings?.setScrollCursorOnKeyboard(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.noteSwipeGesture,
          description: l10n.noteSwipeGestureDesc,
          keywords: _keywords(l10n.swipeKeywords),
          identifier: SemanticsIds.appSettingsNoteSwipe,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _noteSwipeEnabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _noteSwipeEnabled = value);
              await _settings?.setNoteSwipeEnabled(value);
            },
          ),
        ),
      ],
    );
  }

  SettingsSectionData _autoSaveSection(AppLocalizations l10n) {
    final intervalStyle = _autoSaveEnabled
        ? null
        : TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.38),
          );
    return SettingsSectionData(
      id: _sectionAutoSave,
      icon: Icons.save_rounded,
      title: l10n.autoSaveSection,
      entries: [
        SettingsEntry(
          title: l10n.autoSave,
          description: l10n.autoSaveDesc,
          keywords: _keywords(l10n.autoSaveKeywords),
          identifier: SemanticsIds.appSettingsAutoSave,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _autoSaveEnabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _autoSaveEnabled = value);
              await _settings?.setAutoSaveEnabled(value);
            },
          ),
        ),
        // Only meaningful while auto-save is on, so disabled rather than
        // hidden while it is off (S14): the row stays where it is when the
        // switch above it flips, and search still finds it.
        SettingsEntry(
          title: l10n.autoSaveInterval,
          description: l10n.autoSaveIntervalDesc(_autoSaveInterval),
          keywords: _keywords(l10n.autoSaveKeywords),
          identifier: SemanticsIds.appSettingsAutoSaveInterval,
          titleStyle: intervalStyle,
          descriptionStyle: intervalStyle,
          builder: (context, title, description) => settingsSliderRow(
            title: title,
            description: description,
            value: _autoSaveInterval.toDouble(),
            min: SettingsKeys.autoSaveIntervalMinSeconds.toDouble(),
            max: SettingsKeys.autoSaveIntervalMaxSeconds.toDouble(),
            divisions:
                SettingsKeys.autoSaveIntervalMaxSeconds -
                SettingsKeys.autoSaveIntervalMinSeconds,
            labelBuilder: l10n.autoSaveSeconds,
            // The sentence, not the thumb's "12 s": the row's description is
            // out of semantics, so this is all TalkBack says of the value.
            semanticValue: l10n.autoSaveIntervalDesc,
            enabled: _autoSaveEnabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _autoSaveInterval = value.round());
              await _settings?.setAutoSaveInterval(value.round());
            },
          ),
        ),
      ],
    );
  }

  /// Last because these are the settings you set once and forget. Confirming
  /// a delete is not haptics, but it answers the same question — how much the
  /// app says back before it acts.
  SettingsSectionData _feedbackSection(AppLocalizations l10n) {
    return SettingsSectionData(
      id: _sectionFeedback,
      icon: Icons.vibration_rounded,
      title: l10n.feedbackSection,
      entries: [
        SettingsEntry(
          title: l10n.hapticFeedback,
          description: l10n.hapticFeedbackDesc,
          keywords: _keywords(l10n.hapticFeedbackKeywords),
          identifier: SemanticsIds.appSettingsHaptics,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _hapticFeedback,
            onChanged: (value) async {
              if (value) HapticFeedback.lightImpact();
              setState(() => _hapticFeedback = value);
              await _settings?.setHapticFeedback(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.confirmDelete,
          description: l10n.confirmDeleteDesc,
          keywords: _keywords(l10n.confirmDeleteKeywords),
          identifier: SemanticsIds.appSettingsConfirmDelete,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _confirmDelete,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _confirmDelete = value);
              await _settings?.setConfirmDelete(value);
            },
          ),
        ),
      ],
    );
  }

  /// Last on the page: what the live editor replaced. The master switch is
  /// the first row and gates the three below it — with the preview off they
  /// control nothing, so they read as disabled rather than vanishing and
  /// leaving the search with nothing to find.
  SettingsSectionData _deprecatedSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = _previewModeEnabled;
    final disabledStyle = enabled
        ? null
        : TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.38));

    return SettingsSectionData(
      id: _sectionDeprecated,
      icon: Icons.archive_rounded,
      title: l10n.deprecatedSection,
      intro: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(l10n.deprecatedSectionIntro),
      ),
      entries: [
        SettingsEntry(
          title: l10n.previewModeEnabled,
          description: l10n.previewModeEnabledDesc,
          keywords: _keywords(l10n.previewModeKeywords),
          identifier: SemanticsIds.appSettingsPreviewMode,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _previewModeEnabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _previewModeEnabled = value);
              await _settings?.setPreviewModeEnabled(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.previewWhenKeyboardHidden,
          description: l10n.previewWhenKeyboardHiddenDesc,
          keywords: _keywords(l10n.keyboardKeywords),
          identifier: SemanticsIds.appSettingsPreviewWhenHidden,
          titleStyle: disabledStyle,
          descriptionStyle: disabledStyle,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _previewWhenKeyboardHidden,
            enabled: enabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _previewWhenKeyboardHidden = value);
              await _settings?.setPreviewWhenKeyboardHidden(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.showPreviewScrollbar,
          description: l10n.showPreviewScrollbarDesc,
          identifier: SemanticsIds.appSettingsPreviewScrollbar,
          titleStyle: disabledStyle,
          descriptionStyle: disabledStyle,
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _showPreviewScrollbar,
            enabled: enabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _showPreviewScrollbar = value);
              await _settings?.setShowPreviewScrollbar(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.previewLinesPerChunk,
          description: l10n.previewLinesPerChunkDesc(_previewLinesPerChunk),
          keywords: _keywords(l10n.performanceKeywords),
          identifier: SemanticsIds.appSettingsPreviewChunk,
          titleStyle: disabledStyle,
          descriptionStyle: disabledStyle,
          builder: (context, title, description) => settingsSliderRow(
            title: title,
            description: description,
            value: _previewLinesPerChunk.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            semanticValue: l10n.previewLinesPerChunkDesc,
            enabled: enabled,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _previewLinesPerChunk = value.round());
              await _settings?.setPreviewLinesPerChunk(value.round());
            },
          ),
        ),
      ],
    );
  }

  Widget _switchRow({
    required Widget title,
    required Widget? description,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return SwitchListTile(
      title: title,
      subtitle: description,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }

  void _showResetConfirmation() async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.resetToDefaults,
      content: l10n.resetToDefaultsConfirm,
      confirmText: l10n.reset,
      icon: Icons.refresh_rounded,
    );
    // The page may have gone while the dialog was up: the reset reads its
    // context and writes nothing for a page that is no longer there.
    if (!confirmed || !mounted) return;
    await _resetToDefaults();
  }

  /// Restores every row this page owns — the three that used to be left
  /// behind (cursor-follows-keyboard, the preview scrollbar and lines per
  /// chunk) included, since a reset that quietly skips rows is worse than no
  /// reset at all. Values come from `SettingsKeys.default*` so this cannot
  /// drift away from what an untouched install actually reads.
  ///
  /// A write that throws stops the chain where it is (S13): the rows before
  /// it already hold their defaults, so the page re-reads the store rather
  /// than showing either the old values or the defaults it never reached.
  Future<void> _resetToDefaults() async {
    final l10n = AppLocalizations.of(context)!;
    final restoreDefault = RestoreLocationMode.fromName(
      SettingsKeys.defaultRestoreLocationMode,
    );
    try {
      await _writeDefaults(restoreDefault);
    } catch (e, st) {
      debugPrint('[SettingsPage] reset to defaults failed: $e\n$st');
      if (!mounted) return;
      CustomSnackbar.showError(context, l10n.settingsResetFailed);
      // A store that just threw may throw again on the read; nothing may
      // escape a `void async` handler.
      try {
        await _loadSettings();
      } catch (e, st) {
        debugPrint(
          '[SettingsPage] re-read after a failed reset failed: $e\n$st',
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() {
      _collapsedSections = const {};
      _folderSwipeEnabled = SettingsKeys.defaultFolderSwipeEnabled;
      _noteSwipeEnabled = SettingsKeys.defaultNoteSwipeEnabled;
      _confirmDelete = SettingsKeys.defaultConfirmDelete;
      _autoSaveEnabled = SettingsKeys.defaultAutoSaveEnabled;
      _autoSaveInterval = SettingsKeys.defaultAutoSaveInterval;
      _showNotePreview = SettingsKeys.defaultShowNotePreview;
      _labelStyle = LabelStyle.fromName(SettingsKeys.defaultLabelStyle);
      _showStatsBar = SettingsKeys.defaultShowStatsBar;
      _hapticFeedback = SettingsKeys.defaultHapticFeedback;
      _restoreLocationMode = restoreDefault;
      _liveMarkdownRendering = SettingsKeys.defaultLiveMarkdownRendering;
      _showLineNumbers = SettingsKeys.defaultShowLineNumbers;
      _wordWrap = SettingsKeys.defaultWordWrap;
      _showCursorLine = SettingsKeys.defaultShowCursorLine;
      _autoBreakLongLines = SettingsKeys.defaultAutoBreakLongLines;
      _previewWhenKeyboardHidden =
          SettingsKeys.defaultPreviewWhenKeyboardHidden;
      _scrollCursorOnKeyboard = SettingsKeys.defaultScrollCursorOnKeyboard;
      _previewModeEnabled = SettingsKeys.defaultPreviewModeEnabled;
      _showPreviewScrollbar = SettingsKeys.defaultShowPreviewScrollbar;
      _previewLinesPerChunk = SettingsKeys.defaultPreviewLinesPerChunk;
    });

    CustomSnackbar.showSuccess(context, l10n.settingsReset);
  }

  /// The reset's writes, in the order they have always run.
  Future<void> _writeDefaults(RestoreLocationMode restoreDefault) async {
    await _settings?.setFolderSwipeEnabled(
      SettingsKeys.defaultFolderSwipeEnabled,
    );
    await _settings?.setNoteSwipeEnabled(SettingsKeys.defaultNoteSwipeEnabled);
    await _settings?.setConfirmDelete(SettingsKeys.defaultConfirmDelete);
    await _settings?.setAutoSaveEnabled(SettingsKeys.defaultAutoSaveEnabled);
    await _settings?.setAutoSaveInterval(SettingsKeys.defaultAutoSaveInterval);
    await _settings?.setShowNotePreview(SettingsKeys.defaultShowNotePreview);
    await _settings?.setShowStatsBar(SettingsKeys.defaultShowStatsBar);
    await _settings?.setHapticFeedback(SettingsKeys.defaultHapticFeedback);
    await _settings?.setRestoreLocationMode(restoreDefault);
    await _settings?.setLiveMarkdownRendering(
      SettingsKeys.defaultLiveMarkdownRendering,
    );
    await _settings?.setShowLineNumbers(SettingsKeys.defaultShowLineNumbers);
    await _settings?.setWordWrap(SettingsKeys.defaultWordWrap);
    await _settings?.setShowCursorLine(SettingsKeys.defaultShowCursorLine);
    await _settings?.setAutoBreakLongLines(
      SettingsKeys.defaultAutoBreakLongLines,
    );
    await _settings?.setPreviewWhenKeyboardHidden(
      SettingsKeys.defaultPreviewWhenKeyboardHidden,
    );
    await _settings?.setScrollCursorOnKeyboard(
      SettingsKeys.defaultScrollCursorOnKeyboard,
    );
    await _settings?.setPreviewModeEnabled(
      SettingsKeys.defaultPreviewModeEnabled,
    );
    await _settings?.setShowPreviewScrollbar(
      SettingsKeys.defaultShowPreviewScrollbar,
    );
    await _settings?.setPreviewLinesPerChunk(
      SettingsKeys.defaultPreviewLinesPerChunk,
    );
    // The page ships open — leaving a section folded after a reset hides rows
    // the user just asked to see restored.
    await _settings?.setAppSettingsCollapsedSections(const {});
    // Last, and through the service rather than the store, so the browser
    // underneath repaints; it goes last because it is the one call in this
    // chain that can throw, and nothing after it should be skipped if it does.
    await (await LabelAppearanceService.getInstance()).setStyle(
      LabelStyle.fromName(SettingsKeys.defaultLabelStyle),
    );
  }
}
