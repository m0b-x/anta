import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_dialogs.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_drawer.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// Controls settings page for managing gestures and interactions
class ControlsSettingsPage extends StatefulWidget {
  const ControlsSettingsPage({super.key});

  @override
  State<ControlsSettingsPage> createState() => _ControlsSettingsPageState();
}

class _ControlsSettingsPageState extends State<ControlsSettingsPage> {
  SettingsService? _settings;
  bool _isLoading = true;

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

    setState(() {
      _settings = settings;
      _folderSwipeEnabled = folderSwipe;
      _noteSwipeEnabled = noteSwipe;
      _confirmDelete = confirmDel;
      _autoSaveEnabled = autoSave;
      _autoSaveInterval = autoSaveInt;
      _showNotePreview = showPreview;
      _showStatsBar = showStats;
      _hapticFeedback = haptic;
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
      appBar: SettingsAppBar(title: l10n.controlsSettings),
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
                      sections: _buildSections(context, l10n),
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

  List<SettingsSectionData> _buildSections(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return [
      SettingsSectionData(
        icon: Icons.swipe_rounded,
        title: l10n.gesturesSection,
        entries: [
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
      ),
      SettingsSectionData(
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
      ),
      SettingsSectionData(
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
      ),
      SettingsSectionData(
        icon: Icons.visibility_rounded,
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
        ],
      ),
      SettingsSectionData(
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
        ],
      ),
      SettingsSectionData(
        icon: Icons.visibility_rounded,
        title: l10n.previewSection,
        entries: [
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
        ],
      ),
      SettingsSectionData(
        icon: Icons.speed_rounded,
        title: l10n.previewPerformanceSection,
        entries: [
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
      ),
    ];
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

  Future<void> _resetToDefaults() async {
    await _settings?.setFolderSwipeEnabled(true);
    await _settings?.setNoteSwipeEnabled(true);
    await _settings?.setConfirmDelete(true);
    await _settings?.setAutoSaveEnabled(true);
    await _settings?.setAutoSaveInterval(5);
    await _settings?.setShowNotePreview(true);
    await _settings?.setShowStatsBar(true);
    await _settings?.setHapticFeedback(true);
    await _settings?.setLiveMarkdownRendering(true);
    await _settings?.setShowLineNumbers(false);
    await _settings?.setWordWrap(true);
    await _settings?.setShowCursorLine(false);
    await _settings?.setAutoBreakLongLines(true);
    await _settings?.setPreviewWhenKeyboardHidden(false);

    setState(() {
      _folderSwipeEnabled = true;
      _noteSwipeEnabled = true;
      _confirmDelete = true;
      _autoSaveEnabled = true;
      _autoSaveInterval = 5;
      _showNotePreview = true;
      _showStatsBar = true;
      _hapticFeedback = true;
      _liveMarkdownRendering = true;
      _showLineNumbers = false;
      _wordWrap = true;
      _showCursorLine = false;
      _autoBreakLongLines = true;
      _previewWhenKeyboardHidden = false;
    });

    if (!mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.settingsReset,
    );
  }
}
