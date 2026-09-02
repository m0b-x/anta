import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/restore_location_mode.dart';
import '../widgets/app_dialogs.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_drawer.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// The app's main settings page — everything that shapes how ANTA behaves
/// day to day, grouped by the surface it affects.
///
/// Sections are grouped by *where you feel the setting*, not by what kind of
/// control it is: a swipe gesture lives with the screen it opens the drawer
/// on, and "show the preview when the keyboard hides" lives with the preview
/// rather than with the editor. The cross-cutting ones — startup, auto-save,
/// feedback — keep their own sections.
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
  static const String _sectionPreview = 'preview';
  static const String _sectionAutoSave = 'autosave';
  static const String _sectionFeedback = 'feedback';

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
  bool _showStatsBar = true;
  bool _hapticFeedback = true;
  RestoreLocationMode _restoreLocationMode = RestoreLocationMode.everything;
  // Editor settings
  bool _liveMarkdownRendering = true;
  bool _showLineNumbers = false;
  bool _wordWrap = true;
  bool _showCursorLine = false;
  bool _autoBreakLongLines = true;
  bool _previewWhenKeyboardHidden = false;
  bool _scrollCursorOnKeyboard = false;

  // Preview settings
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
      _autoSaveInterval = autoSaveInt;
      _showNotePreview = showPreview;
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
      drawer: const AppDrawer(),
      appBar: SettingsAppBar(title: l10n.appSettings),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                      footer: [
                        Center(
                          child: TextButton.icon(
                            onPressed: _showResetConfirmation,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(l10n.resetToDefaults),
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.error,
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
      _previewSection(l10n),
      _autoSaveSection(l10n),
      _feedbackSection(l10n),
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
          builder: (context, title, description) => _choiceRow(
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
          title: l10n.showStatsBar,
          description: l10n.showStatsBarDesc,
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

  /// Preview and its performance knob used to be two one-row sections; they
  /// are one section now. "Show the preview when the keyboard hides" joins
  /// them from the editor — it decides what the preview does, not how the
  /// editor types.
  SettingsSectionData _previewSection(AppLocalizations l10n) {
    return SettingsSectionData(
      id: _sectionPreview,
      icon: Icons.visibility_rounded,
      title: l10n.previewSection,
      entries: [
        SettingsEntry(
          title: l10n.previewWhenKeyboardHidden,
          description: l10n.previewWhenKeyboardHiddenDesc,
          keywords: _keywords(l10n.keyboardKeywords),
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _previewWhenKeyboardHidden,
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
          builder: (context, title, description) => _switchRow(
            title: title,
            description: description,
            value: _showPreviewScrollbar,
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
          builder: (context, title, description) => _sliderRow(
            title: title,
            description: description,
            value: _previewLinesPerChunk.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
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

  SettingsSectionData _autoSaveSection(AppLocalizations l10n) {
    return SettingsSectionData(
      id: _sectionAutoSave,
      icon: Icons.save_rounded,
      title: l10n.autoSaveSection,
      entries: [
        SettingsEntry(
          title: l10n.autoSave,
          description: l10n.autoSaveDesc,
          keywords: _keywords(l10n.autoSaveKeywords),
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
        // Only meaningful while auto-save is on; hidden otherwise, exactly
        // as before.
        if (_autoSaveEnabled)
          SettingsEntry(
            title: l10n.autoSaveInterval,
            description: l10n.autoSaveIntervalDesc(_autoSaveInterval),
            keywords: _keywords(l10n.autoSaveKeywords),
            builder: (context, title, description) => _sliderRow(
              title: title,
              description: description,
              value: _autoSaveInterval.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              labelBuilder: (v) => '${v}s',
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

  Widget _switchRow({
    required Widget title,
    required Widget? description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: title,
      subtitle: description,
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  /// A one-of-N row. The options sit under the title rather than beside it so
  /// three labels still fit on a narrow phone without the row reflowing as the
  /// locale changes.
  Widget _choiceRow<T extends Enum>({
    required Widget title,
    required Widget? description,
    required T value,
    required Map<T, String> labels,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 4),
          ?description,
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [
                for (final entry in labels.entries)
                  ButtonSegment<T>(
                    value: entry.key,
                    label: Text(entry.value, textAlign: TextAlign.center),
                  ),
              ],
              selected: {value},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required Widget title,
    required Widget? description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String Function(int)? labelBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 4),
          ?description,
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: labelBuilder != null
                ? labelBuilder(value.round())
                : '${value.round()}',
            onChanged: onChanged,
          ),
        ],
      ),
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
    if (!confirmed) return;
    await _resetToDefaults();
  }

  /// Restores every row this page owns — the three that used to be left
  /// behind (cursor-follows-keyboard, the preview scrollbar and lines per
  /// chunk) included, since a reset that quietly skips rows is worse than no
  /// reset at all. Values come from `SettingsKeys.default*` so this cannot
  /// drift away from what an untouched install actually reads.
  Future<void> _resetToDefaults() async {
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
    await _settings?.setRestoreLocationMode(RestoreLocationMode.everything);
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
    await _settings?.setShowPreviewScrollbar(
      SettingsKeys.defaultShowPreviewScrollbar,
    );
    await _settings?.setPreviewLinesPerChunk(
      SettingsKeys.defaultPreviewLinesPerChunk,
    );
    // The page ships open — leaving a section folded after a reset hides rows
    // the user just asked to see restored.
    await _settings?.setAppSettingsCollapsedSections(const {});

    setState(() {
      _collapsedSections = const {};
      _folderSwipeEnabled = SettingsKeys.defaultFolderSwipeEnabled;
      _noteSwipeEnabled = SettingsKeys.defaultNoteSwipeEnabled;
      _confirmDelete = SettingsKeys.defaultConfirmDelete;
      _autoSaveEnabled = SettingsKeys.defaultAutoSaveEnabled;
      _autoSaveInterval = SettingsKeys.defaultAutoSaveInterval;
      _showNotePreview = SettingsKeys.defaultShowNotePreview;
      _showStatsBar = SettingsKeys.defaultShowStatsBar;
      _hapticFeedback = SettingsKeys.defaultHapticFeedback;
      _restoreLocationMode = RestoreLocationMode.everything;
      _liveMarkdownRendering = SettingsKeys.defaultLiveMarkdownRendering;
      _showLineNumbers = SettingsKeys.defaultShowLineNumbers;
      _wordWrap = SettingsKeys.defaultWordWrap;
      _showCursorLine = SettingsKeys.defaultShowCursorLine;
      _autoBreakLongLines = SettingsKeys.defaultAutoBreakLongLines;
      _previewWhenKeyboardHidden = SettingsKeys.defaultPreviewWhenKeyboardHidden;
      _scrollCursorOnKeyboard = SettingsKeys.defaultScrollCursorOnKeyboard;
      _showPreviewScrollbar = SettingsKeys.defaultShowPreviewScrollbar;
      _previewLinesPerChunk = SettingsKeys.defaultPreviewLinesPerChunk;
    });

    if (!mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.settingsReset,
    );
  }
}
