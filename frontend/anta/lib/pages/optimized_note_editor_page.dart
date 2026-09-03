import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:re_editor/re_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_dialogs.dart';
import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../bloc/optimized_note/optimized_note_state.dart';
import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../bloc/markdown_preview/markdown_preview_bloc.dart';
import '../bloc/counter/counter_bloc.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/dev_options.dart';
import '../models/markdown_bar_profile.dart';
import '../models/note_metadata.dart';
import '../models/utility_button_config.dart';
import '../services/auto_save_service.dart';
import '../services/dev_options_service.dart';
import '../services/note_position_service.dart';
import '../services/settings_service.dart';
import '../factories/shortcut_handler_factory.dart';
import '../widgets/bar_switcher_sheet.dart';

import '../widgets/debug_overlays.dart';
import '../widgets/interactive_preview_scrollbar.dart';
import '../widgets/markdown_bar.dart';
import '../widgets/markdown_preview_bloc_view.dart';
import '../widgets/note_editor_chrome.dart';
import '../widgets/note_export_dialog.dart';
import '../widgets/modern_editor_wrapper.dart';
import '../models/checkbox_toggle_info.dart';
import '../widgets/source_mapped_markdown_view.dart';
import '../widgets/note_search_bar.dart';
import '../widgets/app_drawer.dart';
import '../services/app_navigator.dart';
import '../services/drawer_host_registry.dart';
import '../services/note_storage_service.dart';
import '../widgets/unified_app_bars.dart';
import '../utils/editor_width_calculator.dart';
import '../utils/custom_snackbar.dart';
import '../utils/re_editor_search_controller.dart';
import '../utils/text_history_observer.dart';
import '../utils/text_position_utils.dart';
import '../utils/markdown_list_utils.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_money_syntax.dart';
import '../utils/money_display_config.dart';
import '../widgets/money_detail_sheet.dart';
import '../utils/list_aware_paste.dart';
import '../utils/paste_line_breaker.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/preview_scroll_controller.dart';
import '../controllers/shortcut_applier.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../services/vocabulary_service.dart';
import '../database/database.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/font_constants.dart';
import '../constants/markdown_constants.dart';
import '../constants/settings_keys.dart';

class OptimizedNoteEditorPage extends StatefulWidget {
  final String folderId;
  final String? noteId;
  final NoteMetadata? metadata;

  const OptimizedNoteEditorPage({
    super.key,
    required this.folderId,
    this.noteId,
    this.metadata,
  });

  @override
  State<OptimizedNoteEditorPage> createState() =>
      _OptimizedNoteEditorPageState();
}

class _OptimizedNoteEditorPageState extends State<OptimizedNoteEditorPage>
    with WidgetsBindingObserver {
  /// Lets a restored settings page raise this page's drawer when it is popped
  /// — see [DrawerHostRegistry].
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TextEditingController _titleController;
  late CodeLineEditingController _contentController;
  final MarkdownEditorSpanBuilder _markdownSpanBuilder =
      MarkdownEditorSpanBuilder();
  late final VocabularySuggestionController _vocabularySuggestions;
  bool _liveMarkdownRendering = SettingsKeys.defaultLiveMarkdownRendering;
  MoneyDisplayConfig _moneyConfig = const MoneyDisplayConfig(
    enabled: SettingsKeys.defaultMoneyLedgerEnabled,
    startCents: SettingsKeys.defaultMoneyStartCents,
    currencySymbol: SettingsKeys.defaultMoneyCurrencySymbol,
    currencySuffix: SettingsKeys.defaultMoneyCurrencySuffix,
  );

  /// Last applied markdown colour palette. Only used to detect a real
  /// change (so the editor repaint nudge stays rare); the preview reads
  /// its palette from bloc state, not from here.
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;
  late FocusNode _contentFocusNode;
  late CodeScrollController _editorScrollController;
  late TextHistoryObserver _historyObserver;
  late ReEditorSearchController _searchController;
  late PreviewScrollController _previewController;
  final GlobalKey _editorWrapperKey = GlobalKey();
  final GlobalKey _lineNumbersKey = GlobalKey();
  final GlobalKey _scrollIndicatorKey = GlobalKey();

  /// GlobalKey for the [SourceMappedMarkdownView] inside the bloc-view.
  /// Owned by the page so the binding to [_previewController] is visible
  /// in one place instead of going page → controller → bloc-view.
  final GlobalKey<SourceMappedMarkdownViewState> _previewViewKey =
      GlobalKey<SourceMappedMarkdownViewState>();

  final ValueNotifier<bool> _hasChanges = ValueNotifier<bool>(false);
  bool _isPreviewMode = false;
  bool _isLoading = true;
  bool _noteSwipeEnabled = true;
  bool _showStatsBar = true;

  // Editor settings
  bool _showLineNumbers = false;
  bool _wordWrap = true;
  bool _showCursorLine = false;
  bool _autoBreakLongLines = true;
  bool _previewWhenKeyboardHidden = false;
  bool _scrollCursorOnKeyboard = false;

  // Preview settings
  bool _showPreviewScrollbar = false;

  // Toolbar settings
  double _toolbarShortcutRatio = SettingsKeys.defaultToolbarShortcutRatio;
  bool _toolbarSplitEnabled = SettingsKeys.defaultToolbarSplitEnabled;
  List<UtilityButtonConfig> _utilityConfigs = UtilityButtonConfig.defaults();

  /// The resolved bar profile currently active for this note.
  String _activeBarProfileId = MarkdownBarProfile.defaultProfileId;

  /// Saved editor selection for restoring cursor position after preview→editor.
  CodeLineSelection? _savedEditorSelection;

  AutoSaveService? _autoSaveService;
  NotePositionService? _notePositionService;
  NotePositionData? _pendingPosition;

  /// For new notes: becomes non-null once the note is persisted for the first time.
  String? _effectiveNoteId;
  bool _isCreatingNewNote = false;

  /// One-shot guard so the auto-save doesn't show the duplicate-title
  /// snackbar on every keystroke after a collision is detected. Reset to
  /// false the moment the user types a non-colliding title.
  bool _warnedDuplicateTitle = false;

  /// Cached reference so we can dispatch [SetNoteContext] during [dispose].
  late final CounterBloc _counterBloc;

  /// Owns the markdown preview render pipeline (parse, chunk cache,
  /// scroll progress, search highlights). Created in [initState] and
  /// disposed in [dispose]. Provided to descendants via
  /// [BlocProvider.value] in [build]. Preview font size and lines-per-chunk
  /// live in this bloc's state — read via getters below.
  late final MarkdownPreviewBloc _previewBloc;

  /// Convenience accessor for the current preview font size, sourced
  /// from [_previewBloc.state.fontSize]. Used by the toolbar build
  /// and by [_saveFontSizes].
  double get _previewFontSize => _previewBloc.state.fontSize;

  /// Convenience accessor for the current preview chunk size,
  /// sourced from [_previewBloc.state.linesPerChunk]. Used by the
  /// editor's chunk debug visualization so editor and preview always
  /// agree on chunk boundaries.
  int get _previewLinesPerChunk => _previewBloc.state.linesPerChunk;

  /// Localized placeholder shown in preview when the note is empty.
  /// Refreshed in [didChangeDependencies] whenever the locale
  /// changes so the bloc never holds a stale translation.
  String? _emptyPreviewPlaceholder;

  double _editorFontSize = FontConstants.defaultFontSize;
  List<CustomMarkdownShortcut> _allShortcuts = [];
  int _previousTextLength = 0;
  bool _isProcessingTextChange = false;
  final ValueNotifier<NoteEditorStats> _stats = ValueNotifier<NoteEditorStats>(
    emptyNoteEditorStats,
  );

  // Paste detection threshold - if text increases by more than this, it's likely a paste
  static const int _pasteThreshold = 20;

  Timer? _lineCountDebounceTimer;
  Timer? _restorePositionTimer;
  Timer? _previewProgressDebounce;
  Timer? _livePreviewDebounce;
  int _lastLineCountTextLength = 0;
  double _previousKeyboardHeight = 0;
  bool _isTogglingPreview = false;

  /// Mirrors [_contentFocusNode.hasFocus] so the bottom-inset gate in
  /// [build] re-runs when the editor gains or loses the IME.
  bool _contentHasFocus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DrawerHostRegistry.register(_scaffoldKey);
    _effectiveNoteId = widget.noteId;
    _loadEditorSettings();
    _initDevOptions();

    _titleController = TextEditingController(
      text: widget.metadata?.title ?? '',
    );
    // List-aware paste wraps the controller (fork's delegate API):
    // pasting multi-line plain text into a list item continues the
    // list. Everything else forwards to the inner controller.
    _contentController = ListAwarePasteController(
      delegate: CodeLineEditingController(spanBuilder: _buildEditorSpan),
    );
    _markdownSpanBuilder.bind(_contentController);
    _vocabularySuggestions = VocabularySuggestionController(
      controller: _contentController,
      onInsert: _applyVocabularyInsertion,
    );
    _historyObserver = TextHistoryObserver(_contentController);
    _previousTextLength = 0;
    _contentFocusNode = FocusNode()..addListener(_onContentFocusChanged);
    _editorScrollController = CodeScrollController();
    _searchController = ReEditorSearchController();
    _searchController.initialize(_contentController);
    _previewBloc = MarkdownPreviewBloc();
    _previewBloc.bindContentProvider(() => _contentController.text);
    _previewController = _previewBloc.scrollController
      ..bindView(_previewViewKey);
    _previewController.progress.addListener(_onPreviewProgressChanged);

    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onTextChanged);
    _searchController.addListener(_onSearchChanged);

    if (widget.noteId != null) {
      _loadNoteContent();
    } else {
      _isLoading = false;
    }

    context.read<MarkdownBarBloc>().add(
      LoadMarkdownBar(noteId: _effectiveNoteId ?? widget.noteId),
    );
    ShortcutHandlerFactory.counterHandler.setActiveNoteId(
      _effectiveNoteId ?? widget.noteId,
    );
    _counterBloc = context.read<CounterBloc>();
    _counterBloc.add(SetNoteContext(noteId: _effectiveNoteId));
    _initializeAutoSave();
    _loadFontSizes();
    _initializePositionService();
  }

  void _onContentFocusChanged() {
    final hasFocus = _contentFocusNode.hasFocus;
    if (hasFocus == _contentHasFocus || !mounted) return;
    setState(() => _contentHasFocus = hasFocus);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Save immediately when the app loses focus (backgrounded, switched, etc.)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveOnLifecycleEvent();
    }
  }

  /// Performs a synchronous-as-possible save when the OS is about to
  /// suspend / kill the app.  For existing notes we force-save via the
  /// auto-save service; for brand-new notes that haven't been persisted
  /// yet we trigger an early create.
  void _saveOnLifecycleEvent() {
    // Capture the current preview scroll position before the OS suspends
    // us so reopening the note restores where the user actually was.
    _saveCurrentPosition();
    final noteId = _effectiveNoteId;
    if (noteId != null) {
      // Existing (or already-created) note – force save via provider
      _autoSaveService?.forceSave(title: _titleController.text);
    } else {
      // Brand-new note never saved – create it now
      _createNewNoteEarly();
    }
  }

  /// Debounced reaction to preview scroll progress changes; persists the
  /// position so a hot reload / app suspend / page rebuild keeps the
  /// reader anchored.
  void _onPreviewProgressChanged() {
    if (!_isPreviewMode) return;
    _previewProgressDebounce?.cancel();
    _previewProgressDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _isPreviewMode) {
        _saveCurrentPosition();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Refresh the cached "no content yet" placeholder on locale
    // change. If the underlying note is empty, re-dispatch so the
    // bloc swaps the stale translation for the new one.
    final placeholder = AppLocalizations.of(context)!.noContentYet;
    if (_emptyPreviewPlaceholder != placeholder) {
      _emptyPreviewPlaceholder = placeholder;
      if (_contentController.text.isEmpty) {
        _pushPreviewContent('');
      }
    }

    // Same for the money config's localized error strings: rebuild the
    // config with the new locale's messages so preview error rows and
    // the detail sheet never hold a stale translation. Value equality
    // makes this a no-op on every rebuild where the locale is unchanged.
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      final messages = MoneyErrorMessages.of(l10n);
      if (_moneyConfig.errorMessages != messages) {
        final config = MoneyDisplayConfig(
          enabled: _moneyConfig.enabled,
          startCents: _moneyConfig.startCents,
          currencySymbol: _moneyConfig.currencySymbol,
          currencySuffix: _moneyConfig.currencySuffix,
          errorMessages: messages,
        );
        _moneyConfig = config;
        _previewBloc.add(PreviewMoneyConfigChanged(config));
      }
    }

    // Track keyboard visibility to scroll cursor into view when keyboard appears
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (_scrollCursorOnKeyboard &&
        keyboardHeight > _previousKeyboardHeight &&
        keyboardHeight > 0) {
      // Keyboard just appeared - scroll to make cursor visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isPreviewMode) {
          _contentController.makeCursorVisible();
        }
      });
    }

    // When keyboard dismisses and previewWhenKeyboardHidden is on,
    // refresh the cached preview content so the auto-shown preview
    // reflects the latest edits instead of stale text.
    if (_previewWhenKeyboardHidden &&
        _previousKeyboardHeight > 0 &&
        keyboardHeight == 0) {
      _pushPreviewContent(_contentController.text);
    }

    _previousKeyboardHeight = keyboardHeight;
  }

  /// Dispatches the latest preview source into [_previewBloc],
  /// substituting the cached localized "no content yet" placeholder
  /// when the note is empty so the preview still renders something
  /// readable.
  ///
  /// The bloc is a no-op when the content is identical to what was
  /// last prepared, so this is safe to call liberally on toggles,
  /// keyboard dismissal, content load, and checkbox toggles.
  ///
  /// [_emptyPreviewPlaceholder] is initialised in
  /// [didChangeDependencies] which is guaranteed by the framework to
  /// run before any user-driven event reaches this method, so the
  /// non-null assertion is safe.
  void _pushPreviewContent(String text) {
    final content = text.isEmpty ? _emptyPreviewPlaceholder! : text;
    _previewBloc.add(PreviewContentChanged(content));
    // Keep search-over-preview matches aligned with what the preview is
    // actually rendering. The controller dedupes on identical inputs and
    // skips work entirely when no search is active.
    if (_searchController.isSearching) {
      _searchController.updateContent(content);
    }
  }

  /// Forwards [_searchController]'s current matches into the preview
  /// bloc whenever the search state changes. The dispatch always
  /// runs (even when the editor is showing) so the bloc's cached
  /// highlights stay in sync — otherwise toggling back into preview
  /// after closing search in editor mode would render stale matches.
  ///
  /// Both bloc handlers short-circuit identical inputs so this is
  /// cheap, and search-controller change notifications are bounded
  /// to actual search activity (open / close / next / prev / typing
  /// in the search field), not per-character note edits.
  void _onSearchChanged() {
    if (_searchController.isSearching) {
      _previewBloc.add(
        PreviewSearchUpdated(
          highlights: _searchController.matches
              .map((m) => TextRange(start: m.start, end: m.end))
              .toList(growable: false),
          currentIndex: _searchController.currentMatchIndex,
        ),
      );
    } else {
      _previewBloc.add(
        const PreviewSearchUpdated(highlights: null, currentIndex: null),
      );
    }
  }

  Future<void> _initializePositionService() async {
    _notePositionService = await NotePositionService.getInstance();
    if (widget.noteId != null) {
      final position = await _notePositionService!.getPosition(widget.noteId!);
      if (mounted) {
        setState(() {
          _pendingPosition = position;
          _isPreviewMode = position.isPreviewMode;
        });
      }
    }
  }

  Future<void> _loadFontSizes() async {
    final db = await AppDatabase.getInstance();
    final previewSize = await db.userSettingsDao.getValue(
      SettingsKeys.previewFontSize,
    );
    final editorSize = await db.userSettingsDao.getValue(
      SettingsKeys.editorFontSize,
    );

    if (!mounted) return;

    if (previewSize != null) {
      _previewBloc.add(
        PreviewFontSizeChanged(
          double.tryParse(previewSize) ?? FontConstants.defaultFontSize,
        ),
      );
    }
    if (editorSize != null) {
      setState(() {
        _editorFontSize =
            double.tryParse(editorSize) ?? FontConstants.defaultFontSize;
      });
    }
  }

  Future<void> _saveFontSizes() async {
    final db = await AppDatabase.getInstance();
    await db.userSettingsDao.setValue(
      SettingsKeys.previewFontSize,
      _previewFontSize.toString(),
    );
    await db.userSettingsDao.setValue(
      SettingsKeys.editorFontSize,
      _editorFontSize.toString(),
    );
  }

  void _decreaseFontSize() => _adjustFontSize(-1);
  void _increaseFontSize() => _adjustFontSize(1);

  void _adjustFontSize(int direction) {
    final delta = FontConstants.fontSizeStep * direction;
    if (_isPreviewMode) {
      final next = (_previewFontSize + delta).clamp(
        FontConstants.minFontSize,
        FontConstants.maxFontSize,
      );
      _previewBloc.add(PreviewFontSizeChanged(next));
    } else {
      setState(() {
        _editorFontSize = (_editorFontSize + delta).clamp(
          FontConstants.minFontSize,
          FontConstants.maxFontSize,
        );
      });
    }
    _saveFontSizes();
  }

  Future<void> _loadEditorSettings() async {
    final settings = await SettingsService.getInstance();
    final noteSwipe = await settings.getNoteSwipeEnabled();
    final showStats = await settings.getShowStatsBar();
    final liveMarkdownRendering = await settings.getLiveMarkdownRendering();
    final showLineNumbers = await settings.getShowLineNumbers();
    final wordWrap = await settings.getWordWrap();
    final showCursorLine = await settings.getShowCursorLine();
    final showPreviewScrollbar = await settings.getShowPreviewScrollbar();
    final previewLinesPerChunk = await settings.getPreviewLinesPerChunk();
    final autoBreakLongLines = await settings.getAutoBreakLongLines();
    final previewWhenKeyboardHidden = await settings
        .getPreviewWhenKeyboardHidden();
    final scrollCursorOnKeyboard = await settings.getScrollCursorOnKeyboard();
    final toolbarRatio = await settings.getToolbarShortcutRatio();
    final toolbarSplit = await settings.getToolbarSplitEnabled();
    final utilityConfigs = await settings.getToolbarUtilityConfig();
    if (mounted) {
      setState(() {
        _noteSwipeEnabled = noteSwipe;
        _showStatsBar = showStats;
        _liveMarkdownRendering = liveMarkdownRendering;
        _showLineNumbers = showLineNumbers;
        _wordWrap = wordWrap;
        _showCursorLine = showCursorLine;
        _showPreviewScrollbar = showPreviewScrollbar;
        _autoBreakLongLines = autoBreakLongLines;
        _previewWhenKeyboardHidden = previewWhenKeyboardHidden;
        _scrollCursorOnKeyboard = scrollCursorOnKeyboard;
        _toolbarShortcutRatio = toolbarRatio;
        _toolbarSplitEnabled = toolbarSplit;
        _utilityConfigs = utilityConfigs;
      });
      _previewBloc.add(PreviewLinesPerChunkChanged(previewLinesPerChunk));
      await _refreshMoneyConfig(settings);
      await _refreshColorPalette(settings);
      await _refreshVocabularies(settings);
    }
  }

  /// Loads the user's vocabularies and hands the suggestion controller its
  /// settings. Called on note open and again when returning from settings.
  ///
  /// The service is a lazy singleton, so the first editor open is what pulls
  /// the tables into memory; later opens hit the cache. Failure is silent by
  /// design — autocomplete is an accelerator, and a note must always open.
  Future<void> _refreshVocabularies(SettingsService settings) async {
    final enabled = await settings.getVocabularySuggestionsEnabled();
    final trigger = await settings.getVocabularyTriggerChar();
    if (enabled) {
      try {
        await VocabularyService.getInstance();
      } catch (e) {
        debugPrint('[NoteEditor] Vocabulary load error: $e');
      }
    }
    if (!mounted) return;
    _vocabularySuggestions.configure(
      enabled: enabled,
      trigger: trigger,
      isFenceLine: _markdownSpanBuilder.lineInFence,
    );
  }

  /// Applies an accepted suggestion, with the same bookkeeping every other
  /// programmatic insert uses (see [_handleShortcut]): the reentrancy guard so
  /// the paste heuristic cannot fire mid-op, one revocable op so the whole
  /// completion is a single undo step, then a `_previousTextLength` resync so
  /// the next keystroke diffs correctly.
  void _applyVocabularyInsertion(VocabularyInsertion insertion) {
    _isProcessingTextChange = true;
    _contentController.runRevocableOp(() {
      _contentController.replaceSelection(
        insertion.text,
        CodeLineSelection(
          baseIndex: insertion.lineIndex,
          baseOffset: insertion.start,
          extentIndex: insertion.lineIndex,
          extentOffset: insertion.end,
        ),
      );
    });
    _isProcessingTextChange = false;
    _previousTextLength = _contentController.textLength;
    _onTextChanged();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// Resolves the effective money config (enabled flag, global start
  /// balance, this note's currency) and applies it to both render
  /// surfaces. Called on note open and again when returning from
  /// settings.
  ///
  /// The editor surface is refreshed non-destructively:
  /// [MarkdownEditorSpanBuilder.configureMoney] clears the builder's
  /// span memos, and — only when the config actually changed —
  /// `forceRepaint()` makes re_editor drop and rebuild its display
  /// paragraphs (re-running the span builder) without remounting,
  /// mutating text, or moving the caret. On the first open the render
  /// isn't attached yet, so `forceRepaint` is a null-safe no-op and the
  /// first layout paints fresh. (An earlier attempt folded the config
  /// into the editor's ValueKey to force a remount; that remounted the
  /// CodeEditor mid-initialization and crashed re_editor's controller-
  /// delegate handoff — never remount the editor for a settings change.)
  Future<void> _refreshMoneyConfig(SettingsService settings) async {
    final resolved = await settings.getMoneyConfig(
      noteId: _effectiveNoteId ?? widget.noteId,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // One value-equal object, built once here and handed to every
    // consumer — the span builder, the preview bloc, and the detail
    // sheet all read the same instance, so the surfaces can never
    // receive different halves of the config.
    final config = MoneyDisplayConfig(
      enabled: resolved.enabled,
      startCents: resolved.startCents,
      currencySymbol: resolved.symbol,
      currencySuffix: resolved.suffix,
      errorMessages: l10n == null ? null : MoneyErrorMessages.of(l10n),
    );
    final changed = config != _moneyConfig;
    _markdownSpanBuilder.configureMoney(config);
    if (changed) {
      setState(() => _moneyConfig = config);
      _contentController.forceRepaint();
    }
    _previewBloc.add(PreviewMoneyConfigChanged(config));
  }

  /// Resolves the markdown colour palette (presets + the user's custom
  /// colours) and applies it to both render surfaces. Same
  /// non-destructive refresh contract as [_refreshMoneyConfig]: the
  /// editor's span memos are cleared and a repaint is nudged only when
  /// the palette actually changed — never a remount.
  Future<void> _refreshColorPalette(SettingsService settings) async {
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    final changed = palette != _colorPalette;
    _markdownSpanBuilder.configureColors(palette);
    if (changed) {
      _colorPalette = palette;
      _contentController.forceRepaint();
    }
    _previewBloc.add(PreviewColorPaletteChanged(palette));
  }

  Future<void> _initDevOptions() async {
    // Initialize dev options service (loads settings from DB)
    await DevOptionsService.getInstance();
    // Listen for changes and rebuild if needed
    if (mounted) {
      DevOptions.instance.addListener(_onDevOptionsChanged);
    }
  }

  void _onDevOptionsChanged() {
    if (mounted) setState(() {});
  }

  void _initializeAutoSave() {
    _autoSaveService = AutoSaveService(
      onSave: (title, content) async {
        if (_effectiveNoteId != null) {
          // Pre-validate the title against sibling notes BEFORE dispatching
          // the save. If a duplicate is detected we still save the content
          // (so the user never loses keystrokes) but skip the title update
          // and warn once. This mirrors the rename-dialog behavior and
          // avoids drowning the user in repeated snackbars on every save.
          var titleToSave = title;
          final trimmed = title?.trim() ?? '';
          if (trimmed.isNotEmpty &&
              trimmed.toLowerCase() !=
                  (widget.metadata?.title.trim().toLowerCase() ?? '')) {
            final exists = await GetIt.I<NoteStorageService>()
                .noteTitleExistsInFolder(
                  folderId: widget.folderId,
                  title: trimmed,
                  excludeId: _effectiveNoteId,
                );
            if (exists) {
              titleToSave = widget.metadata?.title ?? '';
              if (!_warnedDuplicateTitle && mounted) {
                _warnedDuplicateTitle = true;
                CustomSnackbar.showError(
                  context,
                  AppLocalizations.of(context)!.noteTitleAlreadyExists(trimmed),
                );
              }
            } else {
              // Reset the one-shot warning once the user picks a unique
              // title so a future collision will warn again.
              _warnedDuplicateTitle = false;
            }
          }

          final completer = Completer<void>();
          if (!mounted) return;
          context.read<OptimizedNoteBloc>().add(
            UpdateOptimizedNote(
              noteId: _effectiveNoteId!,
              title: titleToSave,
              content: content,
              completer: completer,
            ),
          );
          await completer.future;
        }
      },
      onChangeDetected: (hasChanges) {
        if (!mounted || _hasChanges.value == hasChanges) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _hasChanges.value = hasChanges;
        });
      },
    );

    if (_effectiveNoteId != null) {
      _autoSaveService?.startTracking(
        _titleController.text,
        _contentController.text,
        contentProvider: () => _contentController.text,
      );
    }
  }

  Future<void> _loadNoteContent() async {
    context.read<OptimizedNoteBloc>().add(LoadNoteContent(widget.noteId!));
  }

  void _onTextChanged() {
    if (!_hasChanges.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hasChanges.value = true;
      });
    }

    _debouncedLineCountUpdate();
    _scheduleLivePreviewRefresh();

    if (_effectiveNoteId != null) {
      _autoSaveService?.onContentChanged(_titleController.text);
    } else {
      // New note: create early once there's meaningful content
      _maybeCreateNewNoteEarly();
    }
  }

  /// Keeps the offstage preview hot while the user is typing so a
  /// subsequent toggle (or `previewWhenKeyboardHidden` reveal) shows
  /// up-to-date content without a re-prepare hitch on the toggle
  /// frame. Skipped for large notes (lazy path) and while the page
  /// is still loading.
  ///
  /// The bloc tracks its own dirty version, so the cheap part
  /// ([MarkdownPreviewBloc.markContentDirty]) runs on every
  /// keystroke; the actual reprepare only fires once the user idles
  /// for [_kLivePreviewDebounce]. When nothing has changed by the
  /// time the timer fires, the bloc short-circuits the refresh.
  void _scheduleLivePreviewRefresh() {
    _previewBloc.markContentDirty();
    if (_isLoading) return;
    if (!_previewBloc.state.hasTheme) return;
    final lineCount = _contentController.lineCount;
    if (lineCount > AppConstants.previewPreloadLineThreshold) return;
    _livePreviewDebounce?.cancel();
    _livePreviewDebounce = Timer(_kLivePreviewDebounce, () {
      if (!mounted) return;
      _previewBloc.add(const PreviewContentRefreshRequested());
      if (_searchController.isSearching) {
        _searchController.updateContent(_contentController.text);
      }
    });
  }

  static const Duration _kLivePreviewDebounce = Duration(milliseconds: 500);

  /// Triggers early creation as soon as the note has any title or content.
  void _maybeCreateNewNoteEarly() {
    if (_effectiveNoteId != null || _isCreatingNewNote) return;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isNotEmpty || content.isNotEmpty) {
      _createNewNoteEarly();
    }
  }

  /// Immediately persists a brand-new note and switches to update mode.
  void _createNewNoteEarly() async {
    if (_effectiveNoteId != null || _isCreatingNewNote) return;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) return;

    // Apply the same per-folder uniqueness rule that rename + auto-save
    // use. If the user picked a colliding title for a brand-new note, save
    // it with an empty title so content isn't lost; the user can rename
    // later from the cards view.
    var titleToCreate = title;
    if (title.isNotEmpty) {
      final exists = await GetIt.I<NoteStorageService>()
          .noteTitleExistsInFolder(folderId: widget.folderId, title: title);
      if (!mounted) return;
      if (exists) {
        titleToCreate = '';
        _warnedDuplicateTitle = true;
        if (context.mounted) {
          CustomSnackbar.showError(
            context,
            AppLocalizations.of(context)!.noteTitleAlreadyExists(title),
          );
        }
      }
    }

    _isCreatingNewNote = true;
    if (!mounted) return;
    context.read<OptimizedNoteBloc>().add(
      CreateOptimizedNote(
        folderId: widget.folderId,
        title: titleToCreate,
        content: content,
      ),
    );
  }

  void _debouncedLineCountUpdate() {
    final currentLength = _contentController.textLength;
    final lengthDelta = (currentLength - _lastLineCountTextLength).abs();

    if (lengthDelta > MarkdownConstants.contentChangeDeltaThreshold) {
      _lineCountDebounceTimer?.cancel();
      _updateCachedStats();
      _lastLineCountTextLength = currentLength;
      return;
    }

    _lineCountDebounceTimer?.cancel();
    _lineCountDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _updateCachedStats();
      _lastLineCountTextLength = _contentController.textLength;
    });
  }

  void _updateCachedStats() {
    if (!mounted) return;
    // Use re_editor's built-in lineCount for efficiency
    _stats.value = (
      lineCount: _contentController.lineCount,
      charCount: _contentController.textLength,
    );
  }

  void _togglePreviewMode() {
    if (_isTogglingPreview) return;
    final switchingToPreview = !_isPreviewMode;
    final totalLines = _contentController.lineCount;
    final isLargeNote = totalLines > AppConstants.previewPreloadLineThreshold;

    // Force-save when switching to preview – a natural checkpoint
    // Compute text once — reused for force-save, cached preview, and search.
    final currentText = switchingToPreview ? _contentController.text : null;

    if (switchingToPreview && _effectiveNoteId != null) {
      _autoSaveService?.forceSave(
        title: _titleController.text,
        content: currentText!,
      );
    }

    // Update cached preview content BEFORE switching modes.
    //
    // Ordering note: [_pushPreviewContent] dispatches a bloc event,
    // whose handler runs as a microtask. Microtasks drain before
    // the next frame is built, so by the time
    // [WidgetsBinding.addPostFrameCallback] below fires, the bloc
    // has already emitted, the [BlocBuilder] has rebuilt, and the
    // [SourceMappedMarkdownView] has prepared its render service.
    // Scroll calls inside the post-frame callback therefore run
    // against a populated list.
    if (switchingToPreview) {
      _pushPreviewContent(currentText!);
      final lineIndex = _contentController.selection.baseIndex;

      // Save editor position so we can restore it when switching back.
      _savedEditorSelection = _contentController.selection;

      if (isLargeNote) {
        // LARGE NOTE: Switch immediately, scroll with short animation
        // Preview builds lazily - no freeze from parsing all content at once
        _isTogglingPreview = true;
        setState(() {
          _isPreviewMode = true;
        });

        // Scroll after preview is visible with a quick animation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isTogglingPreview = false;
          if (!mounted) return;
          _previewController.scrollToLineIndex(
            lineIndex,
            totalLines,
            animate: true,
            duration: const Duration(milliseconds: 150),
          );
        });
      } else {
        // SMALL NOTE: Pre-scroll while offstage, then reveal (instant)
        // First setState to rebuild preview with new content (still offstage)
        _isTogglingPreview = true;
        setState(() {});

        // After rebuild completes, scroll then reveal
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            _isTogglingPreview = false;
            return;
          }

          // Now scroll to position (preview is still offstage)
          if (totalLines > 0) {
            _previewController.scrollToLineIndex(
              lineIndex,
              totalLines,
              animate: false,
            );
          }

          // After scroll completes, reveal the preview
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isTogglingPreview = false;
            if (!mounted) return;
            setState(() {
              _isPreviewMode = true;
            });
            _saveCurrentPosition();
          });
        });
      }

      // Handle search: [_pushPreviewContent] above already synced the
      // search content into the controller and (when search is active)
      // re-ran the preview search synchronously, so there's nothing to
      // do here for the preview path. Editor-mode search is handled in
      // the "Switching to editor mode" branch below where the
      // CodeFindController takes over.

      if (!isLargeNote) {
        return; // Early return for small notes - async callbacks handle the rest
      }
      _saveCurrentPosition();
      return;
    }

    // Switching to editor mode
    if (_searchController.isSearching && _searchController.query.isNotEmpty) {
      final currentQuery = _searchController.query;
      Future.microtask(() {
        if (mounted) {
          _searchController.search(currentQuery);
        }
      });
    }

    // Capture the topmost source-line currently visible in the preview so
    // we can scroll the editor to the same logical position.
    //
    // Caveat: when entering preview we already scrolled to the cursor's
    // chunk, so a `currentLineIndex` that maps to the same chunk as the
    // saved selection means the user *didn't* meaningfully scroll — in
    // that case the saved selection is the truer target. Otherwise (the
    // user paged through the preview) we honor the new reading location
    // and also move the caret so subsequent typing happens at a visible
    // position.
    //
    // Chunks are block-aligned (variable line counts), so we compare the
    // preview's top line against the *chunk-start line* of the saved
    // cursor via the render service rather than assuming uniform chunks.
    final previewTopLine = _previewViewKey.currentState?.currentLineIndex;
    final savedBaseIndex = _savedEditorSelection?.baseIndex;
    final savedChunkStart = savedBaseIndex != null
        ? _previewBloc.renderService.chunkStartLineForLine(savedBaseIndex)
        : null;
    final userMovedPreview =
        previewTopLine != null &&
        savedChunkStart != null &&
        savedChunkStart != previewTopLine;

    // Just flip the mode
    setState(() {
      _isPreviewMode = switchingToPreview;
    });

    // Restore editor scroll: ensure the cursor line is visible after
    // the keyboard animation finishes.
    final lineCount = _contentController.lineCount;
    if (userMovedPreview && lineCount > 0) {
      final clamped = previewTopLine.clamp(0, lineCount - 1);
      // Move the caret to the new line so subsequent typing lands on a
      // visible row (otherwise the cursor stays at the pre-preview
      // position which may be far off-screen after this scroll).
      _contentController.selection = CodeLineSelection.collapsed(
        index: clamped,
        offset: 0,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editorScrollController.makeCenterIfInvisible(
          CodeLinePosition(index: clamped, offset: 0),
        );
      });
    } else {
      _restoreEditorPosition();
    }

    _saveCurrentPosition();
  }

  void _restoreSavedPosition() {
    final position = _pendingPosition;
    if (position == null) return;
    _pendingPosition = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (position.isPreviewMode) {
        // Restore preview scroll using progress ratio (0.0–1.0)
        // via the PreviewScrollController's deferred restore.
        _previewController.restoreProgress(
          position.previewScrollProgress.clamp(0.0, 1.0),
        );
      } else {
        final lineCount = _contentController.lineCount;
        final lineIndex = position.editorLineIndex.clamp(0, lineCount - 1);

        final lineText = lineIndex < _contentController.codeLines.length
            ? _contentController.codeLines[lineIndex].text
            : '';
        final columnOffset = position.editorColumnOffset.clamp(
          0,
          lineText.length,
        );

        _contentController.selection = CodeLineSelection.collapsed(
          index: lineIndex,
          offset: columnOffset,
        );

        _restorePositionTimer?.cancel();
        _restorePositionTimer = Timer(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          _editorScrollController.makeCenterIfInvisible(
            CodeLinePosition(index: lineIndex, offset: columnOffset),
          );
        });
      }
    });
  }

  Future<void> _saveCurrentPosition() async {
    final noteId = _effectiveNoteId ?? widget.noteId;
    if (noteId == null || _notePositionService == null) return;

    final position = NotePositionData(
      isPreviewMode: _isPreviewMode,
      previewScrollProgress: _previewController.progress.value,
      editorLineIndex: _contentController.selection.baseIndex,
      editorColumnOffset: _contentController.selection.baseOffset,
    );

    await _notePositionService!.savePosition(noteId, position);
  }

  /// Restores the editor cursor position after switching from preview mode.
  /// Uses a delayed callback to account for the keyboard animation.
  void _restoreEditorPosition() {
    final selection = _savedEditorSelection;
    if (selection == null) return;

    final position = CodeLinePosition(
      index: selection.baseIndex,
      offset: selection.baseOffset,
    );

    // The keyboard may animate open when the editor regains focus.
    // Wait for that animation before scrolling, otherwise the cursor
    // might end up behind the keyboard.
    _restorePositionTimer?.cancel();
    _restorePositionTimer = Timer(
      Duration(milliseconds: Platform.isIOS ? 300 : 350),
      () {
        if (!mounted) return;
        _editorScrollController.makeCenterIfInvisible(position);
      },
    );
  }

  @override
  void dispose() {
    _counterBloc.add(const SetNoteContext());
    WidgetsBinding.instance.removeObserver(this);
    DrawerHostRegistry.unregister(_scaffoldKey);
    DevOptions.instance.removeListener(_onDevOptionsChanged);
    _lineCountDebounceTimer?.cancel();
    _restorePositionTimer?.cancel();
    _previewProgressDebounce?.cancel();
    _livePreviewDebounce?.cancel();
    _previewController.progress.removeListener(_onPreviewProgressChanged);
    // _previewController is owned by _previewBloc — bloc disposes it.
    _previewBloc.close();
    _autoSaveService?.dispose();
    _titleController.dispose();
    _historyObserver.dispose();
    _vocabularySuggestions.dispose();
    _contentController.dispose();
    _contentFocusNode.removeListener(_onContentFocusChanged);
    _contentFocusNode.dispose();
    _editorScrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _hasChanges.dispose();
    _stats.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    if (_searchController.isSearching) {
      _searchController.closeSearch();
    } else {
      _searchController.openSearch();
    }
    setState(() {});
  }

  void _navigateToSearchMatch(int offset) {
    final match = _searchController.currentMatch;
    if (match == null) return;

    final textLen = _contentController.textLength;
    if (textLen == 0 ||
        match.start < 0 ||
        match.end < 0 ||
        match.start > textLen ||
        match.end > textLen) {
      return;
    }

    if (_isPreviewMode) {
      _scrollToOffsetInPreview(match.start);
    }
  }

  /// Schemes accepted from preview hyperlinks. Anything else (e.g.
  /// `javascript:`, `file:`, `data:`) is rejected with a localized
  /// snackbar so taps cannot be used as a code-execution surface.
  static const _allowedLinkSchemes = {'http', 'https', 'mailto', 'tel'};

  Future<void> _handleLinkTap(String rawUrl) async {
    final uri = _resolveAllowedLinkUri(rawUrl);
    if (uri == null) return;
    await _launchLink(uri);
  }

  /// Editor link taps confirm before leaving the app: a concealed link
  /// sits inside editable text, so mid-workout taps can land on it by
  /// accident. The snackbar's Open action launches the already
  /// validated target; preview link taps keep instant open.
  void _handleEditorLinkTap(String rawUrl) {
    final uri = _resolveAllowedLinkUri(rawUrl);
    if (uri == null) return;
    if (ScaffoldMessenger.maybeOf(context) == null) return;
    final l10n = AppLocalizations.of(context)!;
    final target = uri.host.isNotEmpty ? uri.host : uri.toString();
    CustomSnackbar.showWithAction(
      context,
      message: l10n.linkOpenPrompt(target),
      actionLabel: l10n.linkOpenAction,
      onAction: () => _launchLink(uri),
    );
  }

  /// Validates and normalizes a tapped link, or returns null (with a
  /// localized snackbar) when the scheme is not allowed.
  Uri? _resolveAllowedLinkUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    // Auto-prefix scheme-less URLs starting with `www.` so links like
    // `www.example.com` written in markdown still launch.
    final normalized = trimmed.toLowerCase().startsWith('www.')
        ? 'https://$trimmed'
        : trimmed;

    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme.isEmpty ||
        !_allowedLinkSchemes.contains(uri.scheme.toLowerCase())) {
      if (ScaffoldMessenger.maybeOf(context) != null && mounted) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.linkSchemeNotAllowed,
        );
      }
      return null;
    }
    return uri;
  }

  Future<void> _launchLink(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.linkOpenFailed,
        );
      }
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.linkOpenFailed,
        );
      }
    }
  }

  void _handleCheckboxToggle(CheckboxToggleInfo info) {
    final text = _contentController.text;
    final startLine = TextPositionUtils.getLineFromOffset(text, info.start);
    final startCol = TextPositionUtils.getColumnFromOffset(text, info.start);
    final endLine = TextPositionUtils.getLineFromOffset(text, info.end);
    final endCol = TextPositionUtils.getColumnFromOffset(text, info.end);

    // Select the checkbox bracket range [x] or [ ] and replace atomically
    _contentController.runRevocableOp(() {
      _contentController.selection = CodeLineSelection(
        baseIndex: startLine,
        baseOffset: startCol,
        extentIndex: endLine,
        extentOffset: endCol,
      );
      _contentController.replaceSelection(info.replacement);
    });
    _hasChanges.value = true;

    if (_isPreviewMode) {
      _pushPreviewContent(_contentController.text);
    }
  }

  /// Engages a ghost-text placeholder tapped in the preview: deletes the
  /// whole `{{ … }}` run from the note, switches to the editor, and
  /// drops the caret where the placeholder was so the user can type
  /// their real value. [start]/[end] are absolute source offsets.
  /// Engages a ghost-text placeholder tapped in the preview: switches to
  /// the editor and selects the whole `{{ … }}` run (highlighted) so the
  /// user can type to replace it or tap away to keep it. [start]/[end]
  /// are absolute source offsets. No text is mutated, so leaving without
  /// typing simply preserves the placeholder.
  void _handleGhostTap(int start, int end) {
    final text = _contentController.text;
    if (start < 0 || end > text.length || start >= end) return;

    final startLine = TextPositionUtils.getLineFromOffset(text, start);
    final startCol = TextPositionUtils.getColumnFromOffset(text, start);
    final endLine = TextPositionUtils.getLineFromOffset(text, end);
    final endCol = TextPositionUtils.getColumnFromOffset(text, end);

    // Leave preview and select the run so it reads as an active field.
    setState(() => _isPreviewMode = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _contentController.selection = CodeLineSelection(
        baseIndex: startLine,
        baseOffset: startCol,
        extentIndex: endLine,
        extentOffset: endCol,
      );
      _editorScrollController.makeCenterIfInvisible(
        CodeLinePosition(index: startLine, offset: startCol),
      );
      _contentFocusNode.requestFocus();
    });
    _saveCurrentPosition();
  }

  /// Opens cross-note search pre-filled with a tapped `#tag`. Searches
  /// across **all** notes (not just the current folder) so a tag works
  /// as a global filter. [tag] includes the leading `#`.
  Future<void> _handleTagTap(String tag) async {
    await _saveCurrentPosition();
    if (!mounted) return;
    AppNavigator.toSearch(context, query: tag);
  }

  /// Opens the ledger detail sheet for a tapped `$$` / `$?` / bare `$!`
  /// / `$^` / `$~` row — reached from both the preview pill and the
  /// editor's painted chip. Entries are collected on demand from the
  /// current editor content (grammar-shared, fence-aware), so preview
  /// and editor taps always agree with what is rendered. `$?` sheets
  /// list entries since the last `$=`; bare `$!` sheets list the budget
  /// window — the active target's declaration through the tapped row;
  /// `$^ N` sheets list the window it measures — the last N
  /// balance-changing entries (clamped to the current period) from
  /// their baseline through the tapped row; `$~ N` sheets span the last
  /// N `$=` checkpoints, reaching across period boundaries.
  void _handleMoneyTap(int lineIndex) {
    final codeLines = _contentController.codeLines;
    if (lineIndex < 0 || lineIndex >= codeLines.length) return;
    final tapped = MarkdownMoneySyntax.parse(codeLines[lineIndex].text);
    if (tapped == null) return;
    final collected = MarkdownMoneySyntax.collectEntries(
      lineCount: codeLines.length,
      lineAt: (i) => codeLines[i].text,
      isInert: _markdownSpanBuilder.lineInFence,
      toLine: lineIndex,
      startCents: _moneyConfig.startCents,
    );
    final anchorLines = collected.anchorLines;
    final lastAnchorLine = anchorLines.isEmpty ? -1 : anchorLines.last;
    final entries = switch (tapped.kind) {
      MoneyLineKind.delta => [
        for (final e in collected.entries)
          if (e.lineIndex > lastAnchorLine) e,
      ],
      MoneyLineKind.diff => MarkdownMoneySyntax.diffWindowEntries(
        collected,
        tapped,
        lineIndex,
      ),
      MoneyLineKind.span => MarkdownMoneySyntax.spanWindowEntries(
        collected,
        tapped,
        lineIndex,
      ),
      MoneyLineKind.remaining => MarkdownMoneySyntax.targetWindowEntries(
        collected,
        lineIndex,
      ),
      _ => collected.entries,
    };
    MoneyDetailSheet.show(
      context,
      entries: entries,
      tappedKind: tapped.kind,
      config: _moneyConfig,
    );
  }

  void _scrollToOffsetInPreview(int charOffset) {
    // Use the PreviewScrollController which delegates to the
    // SourceMappedMarkdownView's native scroll method.
    _previewController.scrollToSourceOffset(charOffset);
  }

  /// Handle double-tap on preview to navigate to source line in editor.
  ///
  /// [columnOffset] is reserved for a future detector that can resolve
  /// the tapped glyph's column from the rendered span layout. The
  /// current [DoubleTapLineDetector] always passes `0` because column
  /// resolution would require [TextPainter] introspection over styled
  /// markdown spans. Until that lands we park the cursor at end-of-line
  /// — a stable, predictable convention that avoids dropping the caret
  /// in front of leading markdown markup (e.g. `#`, `>`, `- [ ]`).
  void _handleDoubleTapLine(int lineIndex, int columnOffset) {
    if (!_isPreviewMode) return;

    final lineCount = _contentController.lineCount;
    if (lineCount == 0) return;

    // Clamp line index to valid range
    final clampedLineIndex = lineIndex.clamp(0, lineCount - 1);

    // Get the line text and resolve the cursor offset.
    final lineText = clampedLineIndex < _contentController.codeLines.length
        ? _contentController.codeLines[clampedLineIndex].text
        : '';
    final cursorOffset = columnOffset > 0
        ? columnOffset.clamp(0, lineText.length)
        : lineText.length;

    // Switch to editor mode
    setState(() {
      _isPreviewMode = false;
    });

    // Navigate to the line after mode switch completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _contentController.selection = CodeLineSelection.collapsed(
        index: clampedLineIndex,
        offset: cursorOffset,
      );

      // Scroll to make the line visible (centered if possible)
      _editorScrollController.makeCenterIfInvisible(
        CodeLinePosition(index: clampedLineIndex, offset: cursorOffset),
      );

      // Focus the editor
      _contentFocusNode.requestFocus();
    });

    _saveCurrentPosition();
  }

  void _handleSearchReplace(String _, String newContent) {
    // Note: Replace is handled by CodeFindController internally
    // The newContent parameter is kept for API compatibility
    // but the actual text change happens through the controller
    _hasChanges.value = true;
  }

  void _handleTextChange() {
    if (_isProcessingTextChange) return;

    final selection = _contentController.selection;

    final currentTextLength = _contentController.textLength;
    final textLengthDiff = currentTextLength - _previousTextLength;
    final textLengthIncreased = textLengthDiff > 0;

    // Detect paste: large text additions
    final isPaste = textLengthDiff > _pasteThreshold;

    // Calculate paste location before updating _previousTextLength
    int? pasteStartOffset;
    int? pasteEndOffset;
    if (isPaste && textLengthIncreased) {
      // The selection end is where the paste ended
      pasteEndOffset = _getOffsetFromSelection(selection.extent);
      // The paste started textLengthDiff characters before the end
      pasteStartOffset = pasteEndOffset - textLengthDiff;
      if (pasteStartOffset < 0) pasteStartOffset = 0;
    }

    _previousTextLength = currentTextLength;

    if (!textLengthIncreased) return;

    // Handle paste: break long lines to fit editor width.
    // _handlePasteLineBreaking sets controller.value directly (bypassing
    // runRevocableOp) so the reformatting overwrites the paste's undo
    // node — making paste + reformat a single undo entry.
    if (isPaste && pasteStartOffset != null && pasteEndOffset != null) {
      _handlePasteLineBreaking(pasteStartOffset, pasteEndOffset);
      return;
    }

    // Check if we just inserted a newline
    // In CodeLineEditingController, after pressing Enter:
    // - baseIndex is the new line (current line)
    // - baseOffset is 0 (start of new line)
    final currentLineIndex = selection.baseIndex;
    if (currentLineIndex > 0 && selection.baseOffset == 0) {
      _isProcessingTextChange = true;

      // Get the previous line text
      final prevLineIndex = currentLineIndex - 1;
      final prevLine = _contentController.codeLines[prevLineIndex].text;

      if (MarkdownListUtils.isEmptyListItem(prevLine)) {
        // Remove the empty list item line — merge with the Enter undo node
        // by setting value directly (bypasses runRevocableOp).
        // Need full text here for replaceRange (rare path: Enter on empty list item).
        final text = _contentController.text;
        final newText = text.replaceRange(
          _getLineStartOffset(prevLineIndex),
          _getLineStartOffset(currentLineIndex),
          '',
        );
        _contentController.value = CodeLineEditingValue(
          codeLines: newText.codeLines,
          selection: CodeLineSelection.collapsed(
            index: prevLineIndex,
            offset: 0,
          ),
        );
        _previousTextLength = _contentController.textLength;
        _isProcessingTextChange = false;
        return;
      }

      String? listPrefix = MarkdownListUtils.getListPrefix(prevLine);
      if (listPrefix != null) {
        // Insert the list prefix — merge with the Enter undo node
        // by setting value directly (bypasses runRevocableOp).
        final currentLine = _contentController.codeLines[currentLineIndex];
        final newLineText = '$listPrefix${currentLine.text}';
        final newCodeLines = CodeLines.of([
          for (int i = 0; i < _contentController.codeLines.length; i++)
            if (i == currentLineIndex)
              CodeLine(newLineText)
            else
              _contentController.codeLines[i],
        ]);
        _contentController.value = CodeLineEditingValue(
          codeLines: newCodeLines,
          selection: CodeLineSelection.collapsed(
            index: currentLineIndex,
            offset: listPrefix.length,
          ),
        );
        _previousTextLength = _contentController.textLength;
      }
      _isProcessingTextChange = false;
    }
  }

  /// Creates an EditorWidthCalculator with current configuration
  EditorWidthCalculator _createWidthCalculator() {
    return EditorWidthCalculator(
      config: EditorWidthConfig(
        editorContainerKey: _editorWrapperKey,
        lineNumbersKey: _showLineNumbers ? _lineNumbersKey : null,
        scrollIndicatorKey: _scrollIndicatorKey,
        fontSize: _editorFontSize,
        fontFamily: FontConstants.editorFontFamily,
      ),
      editorPadding: EdgeInsets.only(
        left: AppSpacing.lg,
        top: AppSpacing.lg,
        right: AppSpacing.lg + AppConstants.editorScrollbarPadding,
        bottom: AppSpacing.lg,
      ),
    );
  }

  /// Handle paste by breaking long lines to fit editor width.
  /// Respects markdown syntax and skips code blocks.
  /// Only formats lines within the pasted range.
  void _handlePasteLineBreaking(int pasteStartOffset, int pasteEndOffset) {
    if (!_autoBreakLongLines) return;

    _isProcessingTextChange = true;
    final result = PasteLineBreaker.run(
      controller: _contentController,
      calculator: _createWidthCalculator(),
      pasteStartOffset: pasteStartOffset,
      pasteEndOffset: pasteEndOffset,
    );
    if (result.reformatted) {
      _previousTextLength = _contentController.textLength;
      if (mounted) {
        CustomSnackbar.show(
          context,
          AppLocalizations.of(context)!.linesFormatted(result.linesModified),
          withToolbarOffset: true,
        );
      }
    }
    _isProcessingTextChange = false;
  }

  int _getLineStartOffset(int lineIndex) =>
      CodeLineOffsetUtils.lineStartOffset(_contentController, lineIndex);

  int _getOffsetFromSelection(CodeLinePosition position) =>
      CodeLineOffsetUtils.offsetFromPosition(_contentController, position);

  /// Bottom inset the body must give up to the on-screen keyboard.
  ///
  /// The raw `viewInsets.bottom` is only trusted while this page actually
  /// owns an input connection (editor caret or the search field). Android
  /// can report a stale keyboard inset after a resume — with nothing
  /// focused there is no keyboard to avoid, so the toolbar stays at the
  /// bottom instead of floating above an empty strip.
  double _keyboardInset(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset <= 0) return 0;
    final ownsInput = _contentHasFocus || _searchController.isSearching;
    return ownsInput ? inset : 0;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = _keyboardInset(context);
    final keyboardVisible = keyboardInset > 0;
    final bottomSpacing = keyboardVisible
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;
    return BlocProvider<MarkdownPreviewBloc>.value(
      value: _previewBloc,
      child: MultiBlocListener(
        listeners: [
          BlocListener<OptimizedNoteBloc, OptimizedNoteState>(
            listener: (context, state) {
              if (state is OptimizedNoteCreated) {
                _effectiveNoteId = state.metadata.id;
                _isCreatingNewNote = false;
                _counterBloc.add(SetNoteContext(noteId: _effectiveNoteId));
                ShortcutHandlerFactory.counterHandler.setActiveNoteId(
                  _effectiveNoteId,
                );
                _autoSaveService?.startTracking(
                  _titleController.text,
                  _contentController.text,
                  contentProvider: () => _contentController.text,
                );
              } else if (state is OptimizedNoteContentLoaded) {
                final content = state.note.content ?? '';
                _stats.value = (
                  lineCount: '\n'.allMatches(content).length + 1,
                  charCount: content.length,
                );
                setState(() {
                  _contentController.text = content;
                  _previousTextLength = content.length;
                  _isLoading = false;
                });
                _pushPreviewContent(content);
                _restoreSavedPosition();
              }
            },
          ),
          BlocListener<MarkdownBarBloc, MarkdownBarState>(
            listener: (context, state) {
              if (state is MarkdownBarLoaded) {
                setState(() {
                  _activeBarProfileId = state.activeProfileId;
                  _allShortcuts = List.from(state.currentShortcuts);
                });
                ShortcutHandlerFactory.counterHandler.setActiveNoteId(
                  _effectiveNoteId ?? widget.noteId,
                );
              }
            },
          ),
        ],
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              await _saveBeforeExit();
              if (context.mounted) {
                AppNavigator.pop(context);
              }
            }
          },
          child: Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: false,
            drawer: const AppDrawer(),
            drawerEnableOpenDragGesture: _noteSwipeEnabled,
            appBar: ValueListenableAppBar<bool>(
              valueListenable: _hasChanges,
              builder: (context, hasChanges) => NoteAppBar(
                title: _titleController.text.isEmpty
                    ? AppLocalizations.of(context)!.newNote
                    : _titleController.text,
                hasChanges: hasChanges,
                saveStatusNotifier: _autoSaveService?.saveStatusNotifier,
                onTitleTap: _editTitle,
                actions: [
                  IconButton(
                    icon: Icon(
                      _searchController.isSearching
                          ? Icons.search_off
                          : Icons.search,
                    ),
                    onPressed: _toggleSearch,
                    tooltip: AppLocalizations.of(context)!.search,
                  ),
                  Tooltip(
                    message: _isPreviewMode
                        ? AppLocalizations.of(context)!.previewMarkdown
                        : AppLocalizations.of(context)!.switchToEditMode,
                    waitDuration: AppConstants.debounceDelay,
                    child: IconButton(
                      icon: Icon(_isPreviewMode ? Icons.visibility : Icons.edit),
                      onPressed: () => _togglePreviewMode(),
                    ),
                  ),
                ],
              ),
            ),
            body: Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: _isLoading
                  ? Column(
                      children: [
                        if (_showStatsBar)
                          RepaintBoundary(child: _buildNoteStats()),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Container(
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                          ),
                        ),
                        if (_allShortcuts.isNotEmpty)
                          RepaintBoundary(
                            child: _buildMarkdownBar(enabled: false),
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        // Search bar
                        if (_searchController.isSearching)
                          NoteSearchBar(
                            searchController: _searchController,
                            onClose: () => setState(() {}),
                            onNavigateToMatch: _navigateToSearchMatch,
                            showReplaceField: !_isPreviewMode,
                            onReplace: _handleSearchReplace,
                          ),
                        if (_showStatsBar)
                          RepaintBoundary(child: _buildNoteStats()),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                            child: Builder(
                              builder: (context) {
                                // Show preview if:
                                // 1. User toggled preview mode manually, OR
                                // 2. previewWhenKeyboardHidden is enabled AND keyboard is hidden
                                final showPreview =
                                    _isPreviewMode ||
                                    (_previewWhenKeyboardHidden &&
                                        !keyboardVisible);

                                // Only calculate debug info if any debug option is enabled
                                final devOptions = DevOptions.instance;
                                if (!devOptions.anyEnabled) {
                                  return Stack(
                                    children: [
                                      Offstage(
                                        offstage: showPreview,
                                        child: IgnorePointer(
                                          ignoring: showPreview,
                                          child: _buildEditor(),
                                        ),
                                      ),
                                      Offstage(
                                        offstage: !showPreview,
                                        child: IgnorePointer(
                                          ignoring: !showPreview,
                                          child: _buildPreview(),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                final selection = _contentController.selection;
                                final cursorLine = selection.baseIndex + 1;
                                final cursorColumn = selection.baseOffset;
                                final cursorOffset =
                                    _getLineStartOffset(selection.baseIndex) +
                                    selection.baseOffset;
                                final int? selStart;
                                final int? selEnd;
                                if (selection.isCollapsed) {
                                  selStart = null;
                                  selEnd = null;
                                } else {
                                  // Get start and end offsets based on normalized selection
                                  final baseOff =
                                      _getLineStartOffset(selection.baseIndex) +
                                      selection.baseOffset;
                                  final extentOff =
                                      _getLineStartOffset(
                                        selection.extentIndex,
                                      ) +
                                      selection.extentOffset;
                                  if (baseOff <= extentOff) {
                                    selStart = baseOff;
                                    selEnd = extentOff;
                                  } else {
                                    selStart = extentOff;
                                    selEnd = baseOff;
                                  }
                                }
                                final noteSize = _contentController.textLength;

                                return DebugOverlayStack(
                                  cursorLine: cursorLine,
                                  cursorColumn: cursorColumn,
                                  cursorOffset: cursorOffset,
                                  selectionStart: selStart,
                                  selectionEnd: selEnd,
                                  noteSize: noteSize,
                                  child: Stack(
                                    children: [
                                      Offstage(
                                        offstage: showPreview,
                                        child: IgnorePointer(
                                          ignoring: showPreview,
                                          child: _buildEditor(),
                                        ),
                                      ),
                                      Offstage(
                                        offstage: !showPreview,
                                        child: IgnorePointer(
                                          ignoring: !showPreview,
                                          child: _buildPreview(),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        // Always show toolbar — in preview mode it provides
                        // utility actions; in edit mode it appears with keyboard.
                        RepaintBoundary(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMarkdownBar(enabled: true),
                              SizedBox(height: bottomSpacing),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteStats() {
    final metadata = widget.metadata;
    return NoteEditorStatsBar(
      stats: _stats,
      fallbackCharCount: metadata?.contentLength ?? 0,
      chunkCount: metadata?.chunkCount ?? 1,
      isCompressed: metadata?.isCompressed ?? false,
    );
  }

  /// Builds the markdown toolbar shared between the loading skeleton
  /// and the loaded note view. When [enabled] is `false` the toolbar
  /// renders with disabled history/font/settings hooks (still showing
  /// the layout) so the loading skeleton looks identical to the final
  /// chrome.
  Widget _buildMarkdownBar({required bool enabled}) {
    return MarkdownBar(
      shortcuts: _allShortcuts,
      isPreviewMode: _isPreviewMode,
      canUndo: enabled ? _historyObserver.canUndo : false,
      canRedo: enabled ? _historyObserver.canRedo : false,
      previewFontSize: enabled
          ? (_isPreviewMode ? _previewFontSize : _editorFontSize)
          : _previewFontSize,
      shortcutRatio: _toolbarShortcutRatio,
      splitEnabled: _toolbarSplitEnabled,
      utilityConfigs: _utilityConfigs,
      onUndo: enabled ? () => _historyObserver.undo() : () {},
      onRedo: enabled ? () => _historyObserver.redo() : () {},
      onPaste: enabled ? () => _contentController.paste() : null,
      onSwitchBar: _showBarSwitcher,
      onDecreaseFontSize: enabled ? _decreaseFontSize : () {},
      onIncreaseFontSize: enabled ? _increaseFontSize : () {},
      onSettings: enabled ? _openMarkdownSettings : () {},
      onShortcutPressed: enabled ? _handleShortcut : (_) {},
      onReorderComplete: enabled ? _handleReorderComplete : (_) {},
      onUtilityReorderComplete: enabled ? _handleUtilityReorderComplete : null,
      onShare: enabled ? _showExportFormatDialog : null,
      onCounter: enabled ? _showCounterPicker : null,
      onScrollToTop: () => _scrollToEdge(toTop: true),
      onScrollToBottom: () => _scrollToEdge(toTop: false),
      suggestions: enabled ? _vocabularySuggestions : null,
    );
  }

  Widget _buildPreview() {
    // For large notes, don't pre-build preview to avoid memory/CPU overhead
    // The preview will build when actually needed (when switching to preview mode)
    final isLargeNote =
        _stats.value.lineCount > AppConstants.previewPreloadLineThreshold;
    if (!_isPreviewMode && isLargeNote) {
      return const SizedBox.shrink();
    }

    // Keep the search controller's content in sync with what the
    // preview is rendering, so in-preview search continues to work.
    // NOTE: this used to call _searchController.updateContent(...) here
    // (a ChangeNotifier mutation during build, which is illegal). The
    // sync now happens once on toggle in [_togglePreviewMode] and on
    // every preview content push (see [_pushPreviewContent]).

    final markdownView = MarkdownPreviewBlocView(
      bloc: _previewBloc,
      viewKey: _previewViewKey,
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        top: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: kToolbarHeight,
      ),
      onCheckboxToggle: _handleCheckboxToggle,
      onTapLink: _handleLinkTap,
      onDoubleTapLine: _handleDoubleTapLine,
      onGhostTap: _handleGhostTap,
      onTagTap: _handleTagTap,
      onMoneyTap: _handleMoneyTap,
      // Forward scroll progress to the preview controller so the
      // interactive scrollbar (which listens on the same controller)
      // keeps tracking position. The bloc already mirrors progress
      // into [_previewController] via [_onScrollProgressChanged]
      // when [_previewController] is the bloc's own scroll controller,
      // so this callback is a defensive no-op when they match.
      onScrollProgress: null,
    );

    // If scrollbar is disabled, just return the markdown view
    if (!_showPreviewScrollbar) {
      return KeyedSubtree(key: const ValueKey('preview'), child: markdownView);
    }

    return Stack(
      key: const ValueKey('preview'),
      alignment: Alignment.topLeft,
      children: [
        Positioned.fill(child: markdownView),
        Positioned(
          top: 8,
          bottom: 8,
          right: 0,
          child: InteractivePreviewScrollbar(controller: _previewController),
        ),
      ],
    );
  }

  /// Routes line rendering: live markdown styling when the editor setting
  /// is on (unhandled lines fall through), the ghost-text builder
  /// otherwise.
  TextSpan _buildEditorSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    if (_liveMarkdownRendering) {
      final span = _markdownSpanBuilder.build(
        context: context,
        index: index,
        codeLine: codeLine,
        style: style,
      );
      if (span != null) return span;
    }
    return _buildGhostEditorSpan(
      context: context,
      index: index,
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
    );
  }

  Widget _buildEditor() {
    final devOptions = DevOptions.instance;
    final showChunkDebug = devOptions.showChunkIndicators;
    final markdownRendering = _liveMarkdownRendering;

    return KeyedSubtree(
      key: _editorWrapperKey,
      child: ModernEditorWrapper(
        // Toggling live markdown rendering remounts the editor so all
        // cached line paragraphs are rebuilt with the new span builder.
        // Money config is NOT folded into this key: it changes while the
        // editor is mid-initialization (note open resolves the config
        // asynchronously), and a remount there tears the CodeEditor down
        // during its own mount, crashing re_editor's controller-delegate
        // handoff. Money config is applied non-destructively via
        // _markdownSpanBuilder.configureMoney (cache clear) + a repaint
        // nudge in _refreshMoneyConfig instead.
        key: ValueKey(markdownRendering ? 'editor-md' : 'editor'),
        controller: _contentController,
        focusNode: _contentFocusNode,
        scrollController: _editorScrollController,
        searchController: _searchController,
        editorFontSize: _editorFontSize,
        onTextChanged: _handleTextChange,
        showLineNumbers: _showLineNumbers,
        wordWrap: _wordWrap,
        showCursorLine: _showCursorLine,
        checkboxTapToggle: markdownRendering,
        // Editor link taps confirm via snackbar before the preview's
        // opener runs (scheme validation + localized errors); fence
        // lines render raw so taps there stay plain editing.
        onOpenLink: markdownRendering ? _handleEditorLinkTap : null,
        onMoneyTap: markdownRendering && _moneyConfig.enabled
            ? _handleMoneyTap
            : null,
        isFenceLine: markdownRendering
            ? _markdownSpanBuilder.lineInFence
            : null,
        lineNumbersKey: _lineNumbersKey,
        scrollIndicatorKey: _scrollIndicatorKey,
        // Chunk debug visualization (matches preview mode)
        linesPerChunk: _previewLinesPerChunk,
        showChunkColors: showChunkDebug && devOptions.colorMarkdownBlocks,
        showChunkBorders: showChunkDebug && devOptions.showBlockBoundaries,
      ),
    );
  }

  Future<void> _handleReorderComplete(
    List<CustomMarkdownShortcut> reorderedShortcuts,
  ) async {
    setState(() {
      _allShortcuts = reorderedShortcuts;
    });
    context.read<MarkdownBarBloc>().add(
      UpdateShortcuts(
        profileId: _activeBarProfileId,
        shortcuts: reorderedShortcuts,
      ),
    );
  }

  Future<void> _handleUtilityReorderComplete(
    List<UtilityButtonConfig> reorderedUtilities,
  ) async {
    setState(() {
      _utilityConfigs = reorderedUtilities;
    });
    final settings = await SettingsService.getInstance();
    await settings.setToolbarUtilityConfig(reorderedUtilities);
  }

  Future<void> _saveBeforeExit() async {
    _contentFocusNode.unfocus();

    await _saveCurrentPosition();

    if (_effectiveNoteId != null) {
      await _autoSaveService?.forceSave(title: _titleController.text);
    } else if (!_isCreatingNewNote) {
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();
      if (title.isEmpty && content.isEmpty) return;
      _createNewNoteEarly();
    }
  }

  void _showExportFormatDialog() {
    NoteExportDialog.show(
      context,
      title: _titleController.text,
      content: _contentController.text,
      noteId: widget.noteId,
      createdAt: widget.metadata?.createdAt,
      updatedAt: widget.metadata?.updatedAt,
    );
  }

  void _editTitle() async {
    final newTitle = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.editTitle,
      hintText: AppLocalizations.of(context)!.enterNoteTitle,
      initialValue: _titleController.text,
      confirmText: AppLocalizations.of(context)!.save,
    );
    if (newTitle == null) return;
    setState(() {
      _titleController.text = newTitle;
    });
  }

  void _scrollToEdge({required bool toTop}) {
    if (_isPreviewMode) {
      if (toTop) {
        _previewController.scrollToTop();
      } else {
        _previewController.scrollToBottom();
      }
    } else {
      if (toTop) {
        _contentController.selection = CodeLineSelection.collapsed(
          index: 0,
          offset: 0,
        );
      } else {
        final lastIndex = _contentController.codeLines.length - 1;
        final lastLineLength =
            _contentController.codeLines[lastIndex].text.length;
        _contentController.selection = CodeLineSelection.collapsed(
          index: lastIndex,
          offset: lastLineLength,
        );
      }
      _editorScrollController.makeCenterIfInvisible(
        _contentController.selection.extent,
      );
    }
  }

  /// Increments the given counter and returns its post-increment value.
  /// Also refreshes counter state in the BLoC.
  Future<int> _incrementCounter(String counterId) async {
    final bloc = context.read<CounterBloc>();
    final counterState = bloc.state;
    if (counterState is! CounterLoaded) return 0;

    final counter = counterState.counters
        .where((c) => c.id == counterId)
        .firstOrNull;
    if (counter == null) return 0;

    final currentValue =
        counterState.counterValues[counterId] ?? counter.startValue;
    final noteId = _effectiveNoteId ?? widget.noteId;
    bloc.add(IncrementCounter(counterId: counterId, noteId: noteId));
    return currentValue + counter.step;
  }

  /// Decrements the given counter and returns its post-decrement value.
  Future<int> _decrementCounter(String counterId) async {
    final bloc = context.read<CounterBloc>();
    final counterState = bloc.state;
    if (counterState is! CounterLoaded) return 0;

    final counter = counterState.counters
        .where((c) => c.id == counterId)
        .firstOrNull;
    if (counter == null) return 0;

    final currentValue =
        counterState.counterValues[counterId] ?? counter.startValue;
    final noteId = _effectiveNoteId ?? widget.noteId;
    bloc.add(DecrementCounter(counterId: counterId, noteId: noteId));
    return currentValue - counter.step;
  }

  Future<void> _showCounterPicker() async {
    final counterState = context.read<CounterBloc>().state;
    if (counterState is! CounterLoaded) return;

    final selected = await AppDialogs.counterPicker(
      context,
      counters: counterState.counters,
      counterValues: counterState.counterValues,
      noteId: _effectiveNoteId,
      onManageCounters: () async {
        await AppNavigator.toCounterManagement(
          context,
          noteId: _effectiveNoteId,
        );
        if (!mounted) return null;
        final bloc = context.read<CounterBloc>();
        bloc.add(RefreshCounters(noteId: _effectiveNoteId));
        final updated = await bloc.stream
            .where((s) => s is CounterLoaded)
            .first
            .timeout(const Duration(seconds: 2), onTimeout: () => bloc.state);
        if (updated is! CounterLoaded) return null;
        return (
          counters: updated.counters,
          counterValues: updated.counterValues,
        );
      },
    );

    if (selected == null || !mounted) return;

    final currentValue = await _incrementCounter(selected.id);
    _contentController.runRevocableOp(() {
      _contentController.replaceSelection(currentValue.toString());
    });
    _onTextChanged();
  }

  /// Wraps the current editor selection as ghost text (`{{ … }}`). With
  /// no selection, inserts an empty `{{  }}` and parks the caret between
  /// the markers so the user can type the placeholder.
  void _insertGhostText() {
    MarkdownShortcutInserter.insertGhost(_contentController);
    _onTextChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// Wraps the selection in [shortcut]'s before/after text, dropping a
  /// selected ghost placeholder into the slot when there is no selection —
  /// see [MarkdownShortcutInserter.insertWithGhostSlot].
  void _insertWithGhostSlot(CustomMarkdownShortcut shortcut) {
    MarkdownShortcutInserter.insertWithGhostSlot(_contentController, shortcut);
    _onTextChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  void _handleShortcut(CustomMarkdownShortcut shortcut) {
    // Ghost text has bespoke insert behavior (on an empty selection the
    // caret lands inside the placeholder), so it bypasses the generic
    // applier — mirroring how the header shortcut has its own handling.
    if (shortcut.id == 'default_ghost') {
      _insertGhostText();
      return;
    }

    // Colour constructs wrap a selection like Bold, but on an empty
    // selection they drop a ghost placeholder into the slot so the
    // fill-in is visible and tappable instead of a bare caret.
    if (shortcut.id == 'default_color_text' ||
        shortcut.id == 'default_color_highlight') {
      _insertWithGhostSlot(shortcut);
      return;
    }

    // Store length before applying the shortcut to calculate inserted range
    final beforeLength = _contentController.textLength;

    // Prevent _handleTextChange from running during runRevocableOp.
    // Without this, replaceSelection fires notifyListeners synchronously
    // which triggers _handleTextChange → _handlePasteLineBreaking inside
    // the revocable op, then we'd call _handlePasteLineBreaking again
    // below — double-formatting with stale offsets.
    _isProcessingTextChange = true;

    // Wrap the entire shortcut operation in an atomic undo entry
    // so that e.g. date insertion + repeat + wrapper text all revert together.
    _contentController.runRevocableOp(() {
      _applyShortcut(shortcut);
    });

    _isProcessingTextChange = false;

    // Sync _previousTextLength so subsequent edits diff correctly
    _previousTextLength = _contentController.textLength;

    _onTextChanged();

    // Format the inserted text if auto-break is enabled
    if (_autoBreakLongLines) {
      final afterLength = _contentController.textLength;
      final textLengthDiff = afterLength - beforeLength;
      if (textLengthDiff > 0) {
        final afterSelection = _contentController.selection;
        final insertEndOffset = _getOffsetFromSelection(afterSelection.extent);
        final insertStartOffset = insertEndOffset - textLengthDiff;

        if (insertStartOffset >= 0 && insertEndOffset <= afterLength) {
          _handlePasteLineBreaking(insertStartOffset, insertEndOffset);
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _contentController.makeCursorVisible();
      }
    });
  }

  Future<void> _applyShortcut(CustomMarkdownShortcut shortcut) {
    return ShortcutApplier.apply(
      controller: _contentController,
      shortcut: shortcut,
      mutateCounter: (counterId, op) async {
        final counterState = context.read<CounterBloc>().state;
        if (counterState is! CounterLoaded) return null;
        if (!counterState.counters.any((c) => c.id == counterId)) return null;
        switch (op) {
          case CounterOp.increment:
            return _incrementCounter(counterId);
          case CounterOp.decrement:
            return _decrementCounter(counterId);
          case CounterOp.keep:
            // Counter existence already confirmed by the .any() guard above.
            final counter = counterState.counters.firstWhere(
              (c) => c.id == counterId,
            );
            return counterState.counterValues[counterId] ?? counter.startValue;
        }
      },
    );
  }

  /// Opens the bar switcher bottom sheet and applies the selection.
  Future<void> _showBarSwitcher() async {
    final result = await BarSwitcherSheet.show(
      context,
      currentProfileId: _activeBarProfileId,
      noteId: _effectiveNoteId ?? widget.noteId,
    );
    if (result == null || !mounted) return;

    final noteId = _effectiveNoteId ?? widget.noteId;

    if (result.clearedOverride) {
      if (noteId != null) {
        context.read<MarkdownBarBloc>().add(
          SetNoteBarAssignment(noteId: noteId, profileId: null),
        );
      }
      return;
    }

    if (result.profile != null) {
      final selected = result.profile!;
      if (noteId != null) {
        context.read<MarkdownBarBloc>().add(
          SetNoteBarAssignment(noteId: noteId, profileId: selected.id),
        );
      } else {
        context.read<MarkdownBarBloc>().add(
          SetActiveProfile(profileId: selected.id),
        );
      }
    }
  }

  Future<void> _openMarkdownSettings() async {
    await AppNavigator.toMarkdownSettings(context, allShortcuts: _allShortcuts);

    if (!mounted) return;

    context.read<MarkdownBarBloc>().add(
      ResolveBarForNote(noteId: _effectiveNoteId ?? widget.noteId),
    );
    final settings = await SettingsService.getInstance();
    final ratio = await settings.getToolbarShortcutRatio();
    final splitEnabled = await settings.getToolbarSplitEnabled();
    final utilityConfigs = await settings.getToolbarUtilityConfig();
    if (mounted) {
      setState(() {
        _toolbarShortcutRatio = ratio;
        _toolbarSplitEnabled = splitEnabled;
        _utilityConfigs = utilityConfigs;
      });
      await _refreshMoneyConfig(settings);
      await _refreshColorPalette(settings);
    }
  }
}

/// re_editor [CodeLineSpanBuilder] that renders `{{ … }}` ghost-text
/// runs as dimmed inner text with the markers visually concealed.
///
/// The marker characters are kept in the line (re_editor maps caret /
/// selection offsets through the rendered span, so removing them would
/// desync the model) but are painted transparent and collapsed to a
/// near-zero width, so only the grey inner text shows. A whitespace-only
/// placeholder gets an underline so the empty slot stays findable.
/// Lines without the opening marker short-circuit so the common path
/// stays allocation-free.
TextSpan _buildGhostEditorSpan({
  required BuildContext context,
  required int index,
  required CodeLine codeLine,
  required TextSpan textSpan,
  required TextStyle style,
}) {
  final text = codeLine.text;
  if (!GhostText.mightContain(text)) return textSpan;
  final ghosts = GhostText.findGhosts(text);
  if (ghosts.isEmpty) return textSpan;

  final baseColor =
      style.color ??
      Theme.of(context).textTheme.bodyLarge?.color ??
      Colors.grey;
  final ghostColor = baseColor.withValues(alpha: 0.45);
  final ghostStyle = style.copyWith(color: ghostColor);
  // Markers stay in the model (offset integrity) but are painted
  // transparent and collapsed to ~0 width so they read as invisible.
  final concealStyle = style.copyWith(
    color: const Color(0x00000000),
    fontSize: 0.01,
  );

  final children = <TextSpan>[];
  int pos = 0;
  for (final g in ghosts) {
    if (g.start > pos) {
      children.add(TextSpan(text: text.substring(pos, g.start), style: style));
    }
    // Opening `{{` — concealed.
    children.add(
      TextSpan(
        text: text.substring(g.start, g.innerStart),
        style: concealStyle,
      ),
    );
    // Inner text — dimmed; underline when blank so the slot stays visible.
    final inner = text.substring(g.innerStart, g.innerEnd);
    children.add(
      TextSpan(
        text: inner,
        style: inner.trim().isEmpty
            ? ghostStyle.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: ghostColor,
              )
            : ghostStyle,
      ),
    );
    // Closing `}}` — concealed.
    children.add(
      TextSpan(text: text.substring(g.innerEnd, g.end), style: concealStyle),
    );
    pos = g.end;
  }
  if (pos < text.length) {
    children.add(TextSpan(text: text.substring(pos), style: style));
  }
  return TextSpan(style: style, children: children);
}
