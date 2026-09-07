import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:re_editor/re_editor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_dialogs.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
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
import '../widgets/note_search_bar.dart';
import '../widgets/app_drawer.dart';
import '../services/app_navigator.dart';
import '../services/drawer_host_registry.dart';
import '../services/folder_storage_service.dart';
import '../services/move_coordinator.dart';
import '../services/note_storage_service.dart';
import '../widgets/note_overflow_menu.dart';
import '../widgets/unified_app_bars.dart';
import '../utils/editor_width_calculator.dart';
import '../utils/custom_snackbar.dart';
import '../utils/re_editor_search_controller.dart';
import '../utils/text_history_observer.dart';
import '../utils/text_position_utils.dart';
import '../utils/wiki_link_title.dart';
import '../utils/markdown_money_syntax.dart';
import '../utils/money_display_config.dart';
import '../widgets/money_detail_sheet.dart';
import '../utils/list_aware_paste.dart';
import '../utils/paste_line_breaker.dart';
import '../controllers/editor_edit_tracker.dart';
import '../controllers/editor_render_controller.dart';
import '../controllers/editor_settings_controller.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/note_editor_position_controller.dart';
import '../controllers/note_editor_stats_tracker.dart';
import '../controllers/note_save_coordinator.dart';
import '../controllers/preview_scroll_controller.dart';
import '../controllers/shortcut_applier.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../services/vocabulary_service.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/font_constants.dart';

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
    with WidgetsBindingObserver, RouteAware {
  /// Lets a restored settings page raise this page's drawer when it is popped
  /// — see [DrawerHostRegistry].
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TextEditingController _titleController;
  late CodeLineEditingController _contentController;
  late FocusNode _contentFocusNode;
  late CodeScrollController _editorScrollController;
  late TextHistoryObserver _historyObserver;
  late ReEditorSearchController _searchController;
  late final VocabularySuggestionController _vocabularySuggestions;

  /// The two vocabulary settings [_refreshVocabularies] last applied, or
  /// null before the first load. The settings bundle notifies on every
  /// font-size tap too, and re-running the refresh there would await the
  /// vocabulary service once per tap — on the typing path's own listener.
  ({bool enabled, String trigger})? _appliedVocabularySettings;

  final GlobalKey _editorWrapperKey = GlobalKey();
  final GlobalKey _lineNumbersKey = GlobalKey();
  final GlobalKey _scrollIndicatorKey = GlobalKey();

  /// Every setting this page reads, as one listenable bundle, plus the
  /// font-size taps. Also half of the editor-mount gate: the skeleton
  /// stays up until it has loaded, so the `CodeEditor`'s [ValueKey] is
  /// already final the first time it is built (B4).
  final EditorSettingsController _editorSettings = EditorSettingsController();

  /// The note's persisted reading position, and the join that decides
  /// when it may be applied (B2).
  late final NoteEditorPositionController _position;

  /// Auto-save, the early create for brand-new notes, and the
  /// duplicate-title rules.
  late final NoteSaveCoordinator _saves;

  /// The paste reflow, the Enter list continuation, and the re-entrancy
  /// guard every programmatic edit runs under.
  late final EditorEditTracker _edits;

  /// Line and character counts for the stats bar.
  late final NoteEditorStatsTracker _stats;

  /// The span builder plus the two resolved render settings (money
  /// display, colour palette) both surfaces have to agree on.
  final EditorRenderController _render = EditorRenderController();

  /// Cached reference so we can dispatch [SetNoteContext] during [dispose].
  late final CounterBloc _counterBloc;

  /// Owns the markdown preview render pipeline (parse, chunk cache,
  /// scroll progress, search highlights). Created in [initState] and
  /// disposed in [dispose]. Provided to descendants via
  /// [BlocProvider.value] in [build]. Preview font size and lines-per-chunk
  /// live in this bloc's state — read via getters below.
  late final MarkdownPreviewBloc _previewBloc;

  /// The toolbar's resolved profile and shortcuts, or null until the bar
  /// bloc first answers.
  MarkdownBarLoaded? _bar;

  bool _isPreviewMode = false;
  bool _isTogglingPreview = false;
  Timer? _livePreviewDebounce;

  /// Whether the note's text has reached the editor — one part of
  /// [_isLoading].
  bool _contentLoaded = false;

  /// Whether the initial [_reloadSettings] has resolved the money config
  /// and the colour palette on top of the settings bundle. Part of
  /// [_isLoading]: both are render inputs, and applying either after the
  /// editor's first frame restyles every money row or coloured run in
  /// front of the reader.
  bool _renderConfigLoaded = false;

  /// Whether the toolbar bloc has answered this page's [LoadMarkdownBar]
  /// — with a profile or with an error. Part of [_isLoading]: the bar is
  /// built from the answer, and a bar that lands after the mount reflows
  /// under the editor.
  bool _barSettled = false;

  /// Whether the [LoadNoteContent] *this page* dispatched is still
  /// unanswered.
  ///
  /// One app-wide [OptimizedNoteBloc] serves every editor, and two editors
  /// can be open over the same note at once — a `[[wiki link]]` from B back
  /// to A, or the same note reached twice through search. The id guard in
  /// the content listener cannot tell those two pages apart; this flag can,
  /// because only the page that asked has it raised (C1).
  bool _awaitingContentLoad = false;

  /// The folder the note lives in *now*: `widget.folderId` until the note is
  /// moved from the page's own menu, which is why it is not read straight
  /// off the widget.
  late String _folderId = widget.folderId;

  /// That folder's name, for the menu's first row. Null until the read
  /// answers, and at root — where a note cannot live, so the fallback is
  /// only ever defensive.
  String? _folderName;

  double _previousKeyboardHeight = 0;

  /// Last keyboard-visibility decision taken by [build], mirrored so
  /// callbacks outside the build phase can read [_showPreview].
  bool _lastKeyboardVisible = false;

  /// The preview's scroll controller, owned by [_previewBloc]. The
  /// bloc-view binds its own view key to it on mount, so the page holds
  /// no key of its own.
  PreviewScrollController get _previewController =>
      _previewBloc.scrollController;

  /// Whether the loading skeleton is still up.
  ///
  /// Every input the first frame is built from. The note's text is the
  /// obvious one; the settings bundle is the subtle one (B4), because the
  /// editor's [ValueKey] is derived from `liveMarkdownRendering` —
  /// mounting before that landed would remount the `CodeEditor` the moment
  /// it arrived, mid initialization. The stored position is applied before
  /// the editor's first layout, so that frame is already scrolled to it.
  /// The money config, the colour palette and the toolbar profile are the
  /// rest: each used to land a frame or two after the mount and restyle or
  /// reflow what was already on screen. With all of them gated, the body
  /// appears exactly once, fully formed — the loading state is a blank
  /// body, never half-built chrome that then shifts.
  bool get _isLoading =>
      !_contentLoaded ||
      !_editorSettings.loaded ||
      !_position.loaded ||
      !_renderConfigLoaded ||
      !_barSettled;

  /// Convenience accessor for the current preview font size, sourced
  /// from [_previewBloc.state.fontSize]. Used by the toolbar build.
  double get _previewFontSize => _previewBloc.state.fontSize;

  /// Convenience accessor for the current preview chunk size,
  /// sourced from [_previewBloc.state.linesPerChunk]. Used by the
  /// editor's chunk debug visualization so editor and preview always
  /// agree on chunk boundaries.
  int get _previewLinesPerChunk => _previewBloc.state.linesPerChunk;

  /// Whether the (deprecated) preview surface is reachable at all: either
  /// the user opted back in, or live markdown rendering is off and the raw
  /// editor still needs a way to see rendered output.
  bool get _canPreview => _editorSettings.canPreview;

  /// The stored auto-reveal flag, gated on reachability: a `true` left
  /// over from before the preview was deprecated must not resurrect a
  /// surface the user can no longer reach.
  bool get _previewWhenKeyboardHidden =>
      _canPreview && _editorSettings.value.previewWhenKeyboardHidden;

  /// Whether the preview surface is what the user is looking at *right now*
  /// — the manual toggle, or the keyboard-hidden auto-reveal.
  bool get _showPreview =>
      _canPreview &&
      (_isPreviewMode || (_previewWhenKeyboardHidden && !_lastKeyboardVisible));

  /// The toolbar's shortcuts for the active profile, empty until the bar
  /// bloc answers.
  List<CustomMarkdownShortcut> get _shortcuts =>
      _bar?.currentShortcuts ?? const [];

  /// The bar profile currently active for this note.
  String get _activeBarProfileId =>
      _bar?.activeProfileId ?? MarkdownBarProfile.defaultProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DrawerHostRegistry.register(_scaffoldKey);
    _initDevOptions();

    _titleController = TextEditingController(
      text: widget.metadata?.title ?? '',
    );
    // List-aware paste wraps the controller (fork's delegate API):
    // pasting multi-line plain text into a list item continues the
    // list. Everything else forwards to the inner controller.
    _contentController = ListAwarePasteController(
      delegate: CodeLineEditingController(
        // Live markdown first, ghost text as the fallback — the routing
        // itself lives in [EditorRenderController.buildSpan]; the page
        // only supplies the setting that chooses between them.
        spanBuilder:
            ({
              required BuildContext context,
              required int index,
              required CodeLine codeLine,
              required TextSpan textSpan,
              required TextStyle style,
            }) => _render.buildSpan(
              context: context,
              index: index,
              codeLine: codeLine,
              textSpan: textSpan,
              style: style,
              liveRendering: _editorSettings.value.liveMarkdownRendering,
            ),
      ),
      isFenceLine: _render.lineInFence,
    );
    _render.bind(_contentController);
    _vocabularySuggestions = VocabularySuggestionController(
      controller: _contentController,
      onInsert: _applyVocabularyInsertion,
    );
    _historyObserver = TextHistoryObserver(_contentController);
    _contentFocusNode = FocusNode()..addListener(_onContentFocusChanged);
    _editorScrollController = CodeScrollController();
    _searchController = ReEditorSearchController();
    _searchController.initialize(_contentController);
    _previewBloc = MarkdownPreviewBloc();
    _previewBloc.bindContentProvider(() => _contentController.text);
    _previewController.progress.addListener(_onPreviewProgressChanged);

    _stats = NoteEditorStatsTracker(
      snapshot: () => (
        lineCount: _contentController.lineCount,
        charCount: _contentController.textLength,
      ),
    );
    _edits = EditorEditTracker(
      controller: _contentController,
      autoBreakLongLines: () => _editorSettings.value.autoBreakLongLines,
      pasteContext: _pasteReformatContext,
      onLinesReformatted: _showLinesFormatted,
      // Unconditional: whether a line is fenced is a property of the
      // document, not of the live-rendering setting.
      isFenceLine: _render.lineInFence,
      lineInFenceBody: _render.lineInFenceBody,
    );
    _saves = NoteSaveCoordinator(
      folderId: widget.folderId,
      noteId: widget.noteId,
      originalTitle: widget.metadata?.title,
      title: () => _titleController.text,
      content: () => _contentController.text,
      titleExists: ({required String title, String? excludeId}) =>
          GetIt.I<NoteStorageService>().noteTitleExistsInFolder(
            folderId: _folderId,
            title: title,
            excludeId: excludeId,
          ),
      dispatch: context.read<OptimizedNoteBloc>().add,
      onDuplicateTitle: _showDuplicateTitleWarning,
    );
    _position = NoteEditorPositionController(
      noteId: widget.noteId,
      loadPosition: (id) async =>
          (await NotePositionService.getInstance()).getPosition(id),
      savePosition: (id, position) async =>
          (await NotePositionService.getInstance()).savePosition(id, position),
      onRestore: _applyRestoredPosition,
    );

    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onTextChanged);
    _searchController.addListener(_onSearchChanged);

    if (widget.noteId != null) {
      _loadNoteContent();
    } else {
      // A brand-new note has nothing to wait for on the content side.
      _contentLoaded = true;
    }

    context.read<MarkdownBarBloc>().add(LoadMarkdownBar(noteId: widget.noteId));
    ShortcutHandlerFactory.counterHandler.setActiveNoteId(widget.noteId);
    _counterBloc = context.read<CounterBloc>();
    _counterBloc.add(SetNoteContext(noteId: widget.noteId));
    _saves.start();
    unawaited(_position.load().whenComplete(_onPositionLoaded));
    unawaited(_loadFolderName());
    // Last, so the settings listener can never fire against a
    // half-constructed page.
    _editorSettings.addListener(_onEditorSettingsChanged);
    unawaited(_reloadSettings());
  }

  /// The editor gained or lost the IME. [_keyboardInset] reads the focus
  /// state directly, so the listener only has to ask for a rebuild.
  void _onContentFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// The settings bundle changed — the first load, or a return from a
  /// page that edited one of them (B3). Rebuilds, then re-derives
  /// everything the page keeps outside the bundle.
  void _onEditorSettingsChanged() {
    if (!mounted) return;
    final settings = _editorSettings.value;
    setState(() {
      // The preview just became unreachable while the user was looking at
      // it — the only mode change a settings load may force. On the first
      // load [_isPreviewMode] is still false, so this is a no-op there and
      // [_applySavedPreviewMode] stays the only thing that turns it on.
      if (!settings.canPreview) _isPreviewMode = false;
    });
    _previewBloc.add(
      PreviewLinesPerChunkChanged(settings.previewLinesPerChunk),
    );
    // The preview owns its font size in bloc state, so the settings row
    // is pushed across only when the two have actually drifted apart —
    // which is what a font-size tap does.
    if (settings.previewFontSize != _previewBloc.state.fontSize) {
      _previewBloc.add(PreviewFontSizeChanged(settings.previewFontSize));
    }
    // Only when one of the two settings it consumes actually moved: the
    // bundle notifies on every font-size tap as well.
    if (_appliedVocabularySettings !=
        (
          enabled: settings.vocabularySuggestionsEnabled,
          trigger: settings.vocabularyTriggerChar,
        )) {
      unawaited(_refreshVocabularies());
    }
    _markEditorReady();
  }

  /// Re-reads the settings bundle plus the two resolved render settings
  /// that are not part of it. Called from [initState] and from
  /// [didPopNext], which is what makes an editor flag changed on the
  /// settings page apply on the way back (B3).
  ///
  /// The first run also opens the render half of the mount gate — in a
  /// `finally`, so a read that throws still lets the editor mount rather
  /// than leaving the page blank for good. The two resolved settings are
  /// independent reads and run side by side.
  Future<void> _reloadSettings() async {
    try {
      await _editorSettings.reload();
      if (!mounted) return;
      await Future.wait([_refreshMoneyConfig(), _refreshColorPalette()]);
    } finally {
      if (!_renderConfigLoaded && mounted) {
        setState(() => _renderConfigLoaded = true);
        _markEditorReady();
      }
    }
  }

  /// The stored position has settled (read, failed or nothing to read), so
  /// the mount gate may open. Runs off the unawaited load, hence the
  /// `mounted` check; the rebuild is what mounts the editor when this was
  /// the last of the three loads.
  void _onPositionLoaded() {
    if (!mounted) return;
    setState(() {});
    _markEditorReady();
  }

  /// Every part of the mount gate has landed: the controller holds the
  /// note and the stored position is known, so a restored caret set now
  /// will stick and the editor — which mounts on the very next frame —
  /// lays itself out around it. Called from every load; the position
  /// controller latches, so whichever lands last is the one that opens
  /// the restore (B2).
  void _markEditorReady() {
    if (_isLoading) return;
    _position.contentReady();
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

  /// Persists everything that must survive the OS suspending or killing
  /// the app: the reading position, the note itself, and any font size
  /// the user tapped moments ago (whose write is debounced).
  void _saveOnLifecycleEvent() {
    unawaited(_saveCurrentPosition());
    _saves.saveOnLifecyclePause();
    unawaited(_editorSettings.flushPendingWrites());
  }

  /// Debounced reaction to preview scroll progress changes; persists the
  /// position so a hot reload / app suspend / page rebuild keeps the
  /// reader anchored.
  void _onPreviewProgressChanged() {
    if (!_isPreviewMode) return;
    _position.debounceSave(
      const Duration(milliseconds: 500),
      _positionSnapshot,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }

    // Swap the localized "no content yet" placeholder on a locale
    // change. Only an empty note is showing it, and the bloc's own
    // content is what says which translation it currently holds.
    if (_contentController.text.isEmpty &&
        _previewBloc.state.content !=
            AppLocalizations.of(context)!.noContentYet) {
      _pushPreviewContent('');
    }

    // Same for the money config's localized error strings: rebuild the
    // config with the new locale's messages so preview error rows and
    // the detail sheet never hold a stale translation. Value equality
    // makes this a no-op on every rebuild where the locale is unchanged.
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      final messages = MoneyErrorMessages.of(l10n);
      final current = _render.moneyConfig;
      if (current.errorMessages != messages) {
        final config = MoneyDisplayConfig(
          enabled: current.enabled,
          startCents: current.startCents,
          currencySymbol: current.currencySymbol,
          currencySuffix: current.currencySuffix,
          errorMessages: messages,
        );
        // No repaint nudge: the editor never renders money error text —
        // only the preview and the detail sheet do, so nothing on the
        // editor surface changed. The preview holds its config in bloc
        // state.
        _render.applyMoneyConfig(config);
        _previewBloc.add(PreviewMoneyConfigChanged(config));
      }
    }

    // Track keyboard visibility to scroll cursor into view when keyboard appears
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (_editorSettings.value.scrollCursorOnKeyboard &&
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
  /// substituting the localized "no content yet" placeholder when the
  /// note is empty so the preview still renders something readable.
  ///
  /// The bloc is a no-op when the content is identical to what was
  /// last prepared, so this is safe to call liberally on toggles,
  /// keyboard dismissal, content load, and checkbox toggles.
  ///
  /// Every caller runs after [didChangeDependencies], which the
  /// framework guarantees before any user-driven event reaches the
  /// page, so the localizations lookup cannot fail.
  void _pushPreviewContent(String text) {
    if (!_canPreview) return;
    final content = text.isEmpty
        ? AppLocalizations.of(context)!.noContentYet
        : text;
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

  /// Re-applies the note's persisted preview flag against [_canPreview].
  ///
  /// Runs once, from [_applyRestoredPosition]. By then the settings
  /// bundle has landed too: the restore join only opens once the editor
  /// mounted, and the editor waits on the bundle (B4) — so both inputs
  /// this decision needs are available exactly when it runs, which is
  /// what the two racing loads never guaranteed before.
  void _applySavedPreviewMode() {
    final saved = _position.savedIsPreviewMode;
    if (saved == null || !mounted) return;
    final next = _canPreview && saved;
    if (next == _isPreviewMode) return;
    setState(() => _isPreviewMode = next);
    if (next && !_isLoading) {
      _pushPreviewContent(_contentController.text);
    }
  }

  void _decreaseFontSize() => _adjustFontSize(-1);
  void _increaseFontSize() => _adjustFontSize(1);

  /// Steps the text size of whichever surface the user is looking at.
  /// Only that surface's row is written, and the write is debounced by
  /// [SettingsService]; the preview picks the new size up through the
  /// settings listener.
  void _adjustFontSize(int direction) {
    if (_showPreview) {
      _editorSettings.adjustPreviewFontSize(direction);
    } else {
      _editorSettings.adjustEditorFontSize(direction);
    }
  }

  /// Loads the user's vocabularies and hands the suggestion controller its
  /// settings. Runs off the settings listener, so it re-applies whenever
  /// the flag or the trigger character changes.
  ///
  /// The service is a lazy singleton, so the first editor open is what pulls
  /// the tables into memory; later opens hit the cache. Failure is silent by
  /// design — autocomplete is an accelerator, and a note must always open.
  Future<void> _refreshVocabularies() async {
    final settings = _editorSettings.value;
    if (settings.vocabularySuggestionsEnabled) {
      try {
        await VocabularyService.getInstance();
      } catch (e) {
        debugPrint('[NoteEditor] Vocabulary load error: $e');
      }
    }
    if (!mounted) return;
    _appliedVocabularySettings = (
      enabled: settings.vocabularySuggestionsEnabled,
      trigger: settings.vocabularyTriggerChar,
    );
    _vocabularySuggestions.configure(
      enabled: settings.vocabularySuggestionsEnabled,
      trigger: settings.vocabularyTriggerChar,
      isFenceLine: _render.lineInFence,
    );
  }

  /// Applies an accepted suggestion, with the same bookkeeping every other
  /// programmatic insert uses (see [_handleShortcut]): the edit tracker's
  /// guard so the paste heuristic cannot fire mid-op and the length is
  /// resynced afterwards, wrapped in one revocable op so the whole
  /// completion is a single undo step.
  void _applyVocabularyInsertion(VocabularyInsertion insertion) {
    _edits.runGuarded(() {
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
    });
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
  /// [EditorRenderController.applyMoneyConfig] clears the builder's span
  /// memos, and — only when the config actually changed —
  /// `forceRepaint()` makes re_editor drop and rebuild its display
  /// paragraphs (re-running the span builder) without remounting,
  /// mutating text, or moving the caret. On the first open the render
  /// isn't attached yet, so `forceRepaint` is a null-safe no-op and the
  /// first layout paints fresh. (An earlier attempt folded the config
  /// into the editor's ValueKey to force a remount; that remounted the
  /// CodeEditor mid-initialization and crashed re_editor's controller-
  /// delegate handoff — never remount the editor for a settings change.)
  Future<void> _refreshMoneyConfig() async {
    final settings = await SettingsService.getInstance();
    final resolved = await settings.getMoneyConfig(
      noteId: _saves.effectiveNoteId ?? widget.noteId,
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
    if (_render.applyMoneyConfig(config)) {
      // The wrapper's money tap zone reads `enabled` off the config, so
      // the rebuild is what keeps the tap surface in step with the paint.
      setState(() {});
      _contentController.forceRepaint();
    }
    _previewBloc.add(PreviewMoneyConfigChanged(config));
  }

  /// Resolves the markdown colour palette (presets + the user's custom
  /// colours) and applies it to both render surfaces. Same
  /// non-destructive refresh contract as [_refreshMoneyConfig]: the
  /// editor's span memos are cleared and a repaint is nudged only when
  /// the palette actually changed — never a remount.
  Future<void> _refreshColorPalette() async {
    final settings = await SettingsService.getInstance();
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    if (_render.applyPalette(palette)) {
      // The wrapper takes the palette as a widget field (its tap zones
      // resolve `{name:…}` runs with it), so this needs the rebuild as
      // much as the repaint.
      setState(() {});
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

  /// Warns once that the title the user typed is already taken in this
  /// folder. The content is still saved — under the note's original
  /// title — so a rename that cannot be applied never costs keystrokes.
  void _showDuplicateTitleWarning(String title) {
    if (!mounted) return;
    CustomSnackbar.showError(
      context,
      AppLocalizations.of(context)!.noteTitleAlreadyExists(title),
    );
  }

  /// The measurements [EditorEditTracker] needs to reflow a paste, or
  /// null while the editor has no laid-out width to break lines against
  /// (a paste into a page that has not been measured yet).
  PasteReformatContext? _pasteReformatContext() {
    final calculator = _createWidthCalculator();
    final width = calculator.getAvailableTextWidth();
    if (width == null) return null;
    return (calculator: calculator, availableWidth: width);
  }

  /// Tells the user a paste was reflowed to the editor's width, so the
  /// rewrapped lines do not read as text they did not type.
  void _showLinesFormatted(int linesModified) {
    if (!mounted) return;
    CustomSnackbar.show(
      context,
      AppLocalizations.of(context)!.linesFormatted(linesModified),
      withToolbarOffset: true,
    );
  }

  /// Asks the shared bloc for this note's text. The only dispatch site of
  /// [LoadNoteContent] in the app, and the only place [_awaitingContentLoad]
  /// is raised — which is what makes the answer *this* page's (C1).
  Future<void> _loadNoteContent() async {
    _awaitingContentLoad = true;
    context.read<OptimizedNoteBloc>().add(LoadNoteContent(widget.noteId!));
  }

  /// Puts [content] into the editor and re-baselines everything derived
  /// from the text it replaces: the stats bar, the edit tracker's length,
  /// and auto-save's saved-content baseline.
  ///
  /// The one path for both the first load and the reload
  /// ([_reloadContentIfChanged]), so the two can never drift apart on which
  /// of those re-baselines they remember to take.
  ///
  /// The undo history necessarily restarts at [content]: `loadText` resets
  /// it, and that is the point — undo must never be able to reach the empty
  /// document the controller was constructed with, nor, on a reload, text
  /// the note no longer holds.
  ///
  /// [keepCaret] re-places the collapsed caret at the (line, column) it
  /// held, clamped to the new document. The reload path needs it: coming
  /// back to a note that changed underneath must not also throw the reader
  /// back to the top of it.
  void _adoptLoadedContent(String content, {bool keepCaret = false}) {
    final previous = keepCaret ? _contentController.selection : null;
    // Counted from the string rather than asked of the editor: it is
    // exact and already in hand.
    _stats.set((
      lineCount: '\n'.allMatches(content).length + 1,
      charCount: content.length,
    ));
    // A load, not an edit: the loaded text is the undo baseline.
    setState(() {
      _contentController.loadText(content);
      _contentLoaded = true;
    });
    if (previous != null) {
      final lines = _contentController.codeLines;
      final index = previous.baseIndex.clamp(0, lines.length - 1);
      final offset = previous.baseOffset.clamp(0, lines[index].text.length);
      // The fork folds a selection-only change into the current undo node,
      // so re-placing the caret here does not give the reload something to
      // undo.
      _contentController.selection = CodeLineSelection.collapsed(
        index: index,
        offset: offset,
      );
    }
    // The tracker never saw the assignment above — only the wrapper calls
    // `onTextChanged`, and on the first load it is not mounted yet — so its
    // baseline is still the previous text's length. Adopt the loaded length
    // before the wrapper starts diffing, or the next keystroke reads as a
    // whole-document paste.
    _edits.syncLength();
    // `loadText` above fired the page's text listener, so auto-save thinks
    // the note was edited into this. Re-baseline before the debounce
    // rewrites what was just read back, with a new `updatedAt`, version and
    // HLC.
    _saves.contentLoaded();
    _pushPreviewContent(content);
    _markEditorReady();
  }

  /// Re-reads the note on the way back from a route pushed over this page,
  /// for the case that route was *another editor for the same note* — a
  /// `[[wiki link]]` back to a note already open, or the same note reached
  /// twice through search. Without it this page would keep serving the text
  /// it loaded, and its next keystroke would auto-save that stale text over
  /// everything typed above (C1).
  ///
  /// Only a page with nothing of its own to lose reloads. [didPushNext]
  /// force-saved on the way out, so `hasChanges` being false means the
  /// editor's text is what the row held when we left; a page that is still
  /// dirty (a save that failed, a write still in flight) holds the newer
  /// text and auto-save will write it, so it is left exactly as it is.
  ///
  /// Layering: Page -> Service, like every other read this page owns. A
  /// note that has been deleted meanwhile reads as null and changes
  /// nothing — the page keeps its text rather than blanking under the user.
  Future<void> _reloadContentIfChanged() async {
    if (!_contentLoaded) return;
    if (_saves.hasChanges.value) return;
    if (_saves.saveStatus.value == SaveStatus.saving) return;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    if (noteId == null) return;

    final lazy = await GetIt.I<NoteStorageService>().loadNoteWithContent(
      noteId,
    );
    if (!mounted || lazy == null) return;
    // Re-checked after the await: a keystroke landing during the read makes
    // the editor's text the newer one again.
    if (_saves.hasChanges.value) return;

    // The title is held in a plain controller seeded from `widget.metadata`,
    // not by a bloc, so a rename made in the editor above this one would
    // otherwise leave a stale app-bar title for as long as this page lives.
    final titleChanged = lazy.metadata.title != _titleController.text;
    if (titleChanged) {
      setState(() => _titleController.text = lazy.metadata.title);
    }

    final content = lazy.content ?? '';
    if (content == _contentController.text) {
      // Nothing changed, so nothing is adopted: an unchanged round trip
      // must cost neither the caret nor the undo history. The title write
      // above still fired the page's text listener, so re-baseline
      // auto-save on it before the debounce writes it back.
      if (titleChanged) _saves.contentLoaded();
      return;
    }
    _adoptLoadedContent(content, keepCaret: true);
  }

  void _onTextChanged() {
    _stats.onTextChanged(_contentController.textLength);
    _scheduleLivePreviewRefresh();
    _saves.onContentChanged();
    _syncHistoryButtons();
  }

  /// The undo/redo state the toolbar was last built with, so a keystroke
  /// rebuilds the page only when that state actually flips (the first edit
  /// after a load, an undo that bottoms out, a redo that reaches the top) —
  /// never per keystroke.
  ({bool canUndo, bool canRedo}) _builtHistory = (
    canUndo: false,
    canRedo: false,
  );

  ({bool canUndo, bool canRedo}) get _historyState =>
      (canUndo: _historyObserver.canUndo, canRedo: _historyObserver.canRedo);

  /// Rebuilds the toolbar's undo/redo buttons when the history state moved
  /// away from what they show. The controller can notify mid-build (the
  /// editor's delegate handoff does), so a change seen during a frame's
  /// build phase is applied after that frame instead of throwing.
  void _syncHistoryButtons() {
    if (_historyState == _builtHistory) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncHistoryButtons();
      });
      return;
    }
    if (mounted) setState(() {});
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
    if (!_canPreview) return;
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

  void _togglePreviewMode() {
    if (!_canPreview) return;
    if (_isTogglingPreview) return;
    final switchingToPreview = !_isPreviewMode;
    final totalLines = _contentController.lineCount;
    final isLargeNote = totalLines > AppConstants.previewPreloadLineThreshold;

    // Force-save when switching to preview – a natural checkpoint
    // Compute text once — reused for force-save, cached preview, and search.
    final currentText = switchingToPreview ? _contentController.text : null;

    if (switchingToPreview) {
      unawaited(_saves.forceSave(content: currentText));
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
      _position.savedEditorSelection = _contentController.selection;

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
    final previewTopLine = _previewController.currentLineIndex;
    final savedBaseIndex = _position.savedEditorSelection?.baseIndex;
    final savedChunkStart = savedBaseIndex != null
        ? _previewBloc.renderService.chunkStartLineForLine(savedBaseIndex)
        : null;
    final userMovedPreview =
        savedChunkStart != null && savedChunkStart != previewTopLine;

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

  /// Applies the persisted caret or preview progress. Runs exactly once,
  /// when the position record, the content and the settings have all
  /// landed — the join lives in
  /// [NoteEditorPositionController.restoreWhenReady], so this body no
  /// longer has to guess which side it is being called from (B2).
  ///
  /// The editor itself mounts on the next frame (the gate opens in the
  /// same callback that runs this), so the caret is set on the controller
  /// synchronously and the scroll is handed to the fork as a
  /// layout-time centring: the editor's first layout consumes it, and the
  /// first frame it paints already shows the stored line. The old
  /// post-frame-plus-timer scroll painted the top of the note first and
  /// then jumped, which on slower devices read as a fast scroll down.
  void _applyRestoredPosition(NotePositionData position) {
    _applySavedPreviewMode();

    if (_canPreview && position.isPreviewMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Restore preview scroll using progress ratio (0.0–1.0)
        // via the PreviewScrollController's deferred restore.
        _previewController.restoreProgress(
          position.previewScrollProgress.clamp(0.0, 1.0),
        );
      });
      return;
    }

    // The record stores an absolute line number; this resolves it back
    // to a visible index (and clamps a stale line/column against the
    // note as it is now).
    final target = NoteEditorPositionController.editorTarget(
      position,
      _contentController,
    );
    _contentController.selection = CodeLineSelection.collapsed(
      index: target.index,
      offset: target.offset,
    );
    _editorScrollController.makeCenterIfInvisibleOnLayout(target);
  }

  /// The record describing where the reader is right now.
  NotePositionData _positionSnapshot() => NoteEditorPositionController.snapshot(
    controller: _contentController,
    isPreviewMode: _isPreviewMode,
    previewScrollProgress: _previewController.progress.value,
  );

  Future<void> _saveCurrentPosition() => _position.save(_positionSnapshot());

  /// Restores the editor cursor position after switching from preview mode.
  /// Uses a delayed callback to account for the keyboard animation.
  void _restoreEditorPosition() {
    final selection = _position.savedEditorSelection;
    if (selection == null) return;

    final position = CodeLinePosition(
      index: selection.baseIndex,
      offset: selection.baseOffset,
    );

    // The keyboard may animate open when the editor regains focus.
    // Wait for that animation before scrolling, otherwise the cursor
    // might end up behind the keyboard.
    _position.scheduleScroll(
      Duration(milliseconds: Platform.isIOS ? 300 : 350),
      () {
        if (!mounted) return;
        _editorScrollController.makeCenterIfInvisible(position);
      },
    );
  }

  /// Called when a route pushed above the editor is popped — the drawer's
  /// settings, backup and database pages among them, and since wiki links
  /// another editor. Editor flags live on the main settings page, so
  /// without this every one of them would stay stale until the note was
  /// closed and reopened; and the note itself may have been edited above
  /// this page, which is what the second call covers.
  ///
  /// `RouteObserver<PageRoute>` only fires between page routes, so the
  /// toolbar, colour and money sheets do not reach here.
  @override
  void didPopNext() {
    unawaited(_reloadSettings());
    unawaited(_reloadContentIfChanged());
  }

  /// Called when a route is pushed above the editor. The drawer's settings
  /// route leads to the database switcher, which restarts the app through
  /// `SystemNavigator.pop()` — the editor is never disposed and the
  /// debounce never fires, so the flush has to happen on the way out.
  @override
  void didPushNext() {
    unawaited(_saves.forceSave());
  }

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    _counterBloc.add(const SetNoteContext());
    ShortcutHandlerFactory.counterHandler.setActiveNoteId(null);
    WidgetsBinding.instance.removeObserver(this);
    DrawerHostRegistry.unregister(_scaffoldKey);
    DevOptions.instance.removeListener(_onDevOptionsChanged);
    // Cancels the restore-scroll and position-save timers.
    _position.dispose();
    _livePreviewDebounce?.cancel();
    _previewController.progress.removeListener(_onPreviewProgressChanged);
    // _previewController is owned by _previewBloc — bloc disposes it.
    _previewBloc.close();
    _saves.dispose();
    _titleController.removeListener(_onTextChanged);
    _titleController.dispose();
    _historyObserver.dispose();
    _vocabularySuggestions.dispose();
    _contentController.removeListener(_onTextChanged);
    _contentController.dispose();
    _contentFocusNode.removeListener(_onContentFocusChanged);
    _contentFocusNode.dispose();
    _editorScrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _editorSettings.removeListener(_onEditorSettingsChanged);
    // Disposing flushes any font size the user tapped moments ago.
    _editorSettings.dispose();
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

    if (_showPreview) {
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
    _saves.markChanged();

    if (_showPreview) {
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

  /// Whether nothing has been pushed over this page yet. Both tap handlers
  /// take it after their awaits, because the tap interceptor fires on every
  /// re-tap by design: without it two quick taps on one `[[wiki link]]` (or
  /// one `#tag`) each finish their round trip and push their own page (B2).
  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? false;

  /// Opens cross-note search pre-filled with a tapped `#tag`. Searches
  /// across **all** notes (not just the current folder) so a tag works
  /// as a global filter. [tag] includes the leading `#`.
  Future<void> _handleTagTap(String tag) async {
    await _saveCurrentPosition();
    if (!mounted) return;
    if (!_isCurrentRoute) return;
    AppNavigator.toSearch(context, query: tag);
  }

  /// Opens the note a tapped `[[title]]` names — from the editor's painted
  /// link and from the preview's, which both hand over the raw inner text.
  ///
  /// Resolution prefers a note in the folder this one lives in, since a link
  /// written here most likely means the neighbour of that name. A title that
  /// resolves to nothing is a fact about the text, not a failure, so it
  /// reports through the neutral snackbar rather than the error one.
  ///
  /// A link to the note already open is swallowed rather than pushed: a
  /// second editor over the same note would give it two save coordinators
  /// writing the same row, which is the shape the Session 6 review's B3
  /// guards exist for. That check only covers *this* page's note, though —
  /// a link back to a note open further down the stack still pushes, which
  /// is what [_awaitingContentLoad] and [_reloadContentIfChanged] handle.
  ///
  /// The whole body is guarded: the wrapper calls this detached, so an
  /// exception from the lookup or the position write would otherwise land
  /// as an unhandled async error with nothing on screen to show for it
  /// (C11).
  Future<void> _handleWikiLinkTap(String rawTitle) async {
    final title = rawTitle.trim();
    if (title.isEmpty) return;

    try {
      // The lookup gets the full trimmed title; only what the snackbar
      // shows is bounded (C10).
      final note = await GetIt.I<NoteStorageService>().resolveNoteByTitle(
        title,
        preferFolderId: _folderId,
      );
      if (!mounted) return;
      if (!_isCurrentRoute) return;
      if (note == null) {
        CustomSnackbar.show(
          context,
          AppLocalizations.of(
            context,
          )!.wikiLinkNoteNotFound(WikiLinkTitle.forDisplay(title)),
        );
        return;
      }
      if (note.id == (_saves.effectiveNoteId ?? widget.noteId)) return;

      await _saveCurrentPosition();
      if (!mounted) return;
      if (!_isCurrentRoute) return;
      AppNavigator.toNoteEditor(
        context,
        folderId: note.folderId,
        noteId: note.id,
        metadata: note,
      );
    } catch (e) {
      debugPrint('[NoteEditor] wiki link tap failed: $e');
      if (!mounted) return;
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.linkOpenFailed,
      );
    }
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
      isInert: _render.lineInFence,
      toLine: lineIndex,
      startCents: _render.moneyConfig.startCents,
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
      config: _render.moneyConfig,
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
    if (!_showPreview) return;

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
    _saves.markChanged();
  }

  /// Creates an EditorWidthCalculator with current configuration
  EditorWidthCalculator _createWidthCalculator() {
    return EditorWidthCalculator(
      config: EditorWidthConfig(
        editorContainerKey: _editorWrapperKey,
        lineNumbersKey: _editorSettings.value.showLineNumbers
            ? _lineNumbersKey
            : null,
        scrollIndicatorKey: _scrollIndicatorKey,
        fontSize: _editorSettings.value.editorFontSize,
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

  /// Character offset of a line's first character, for the debug
  /// overlay's cursor/selection read-out.
  int _getLineStartOffset(int lineIndex) =>
      CodeLineOffsetUtils.lineStartOffset(_contentController, lineIndex);

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
    final ownsInput =
        _contentFocusNode.hasFocus || _searchController.isSearching;
    return ownsInput ? inset : 0;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = _keyboardInset(context);
    final keyboardVisible = keyboardInset > 0;
    _lastKeyboardVisible = keyboardVisible;
    final showPreview = _showPreview;
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
                // One app-wide bloc serves every editor, and a buried one
                // stays mounted: only the page that asked for this create
                // may adopt its id.
                if (widget.noteId != null || !_saves.isCreatingNewNote) return;
                final id = state.metadata.id;
                _saves.noteCreated(id);
                // From here on the note has an id, so its reading
                // position can start being persisted.
                _position.noteId = id;
                _counterBloc.add(SetNoteContext(noteId: id));
                ShortcutHandlerFactory.counterHandler.setActiveNoteId(id);
              } else if (state is OptimizedNoteContentLoaded) {
                // Same shared bloc, so two guards, and the id alone is not
                // enough. The id keeps *another note's* text out of this
                // editor. The flag keeps out an emission for this very note
                // that answers a *second editor over it* — a `[[wiki link]]`
                // from B back to A leaves two live pages for A, and the load
                // that fills the new one would otherwise reload the buried
                // one too, resetting its caret, its undo baseline and its
                // auto-save baseline under text the user is still editing
                // (C1). Deliberately not `ModalRoute.isCurrent`: a launch
                // restore pushes the whole saved stack at once, so a page
                // can legitimately be covered when its own first content
                // arrives.
                if (state.note.id != widget.noteId) return;
                if (!_awaitingContentLoad) return;
                _awaitingContentLoad = false;
                _adoptLoadedContent(state.note.content ?? '');
              }
            },
          ),
          BlocListener<MarkdownBarBloc, MarkdownBarState>(
            listener: (context, state) {
              if (state is MarkdownBarLoaded) {
                setState(() {
                  _bar = state;
                  _barSettled = true;
                });
                ShortcutHandlerFactory.counterHandler.setActiveNoteId(
                  _saves.effectiveNoteId ?? widget.noteId,
                );
                _markEditorReady();
              } else if (state is MarkdownBarError) {
                // A bar that failed to load is still an answer: the editor
                // mounts with an empty shortcut row rather than never.
                setState(() => _barSettled = true);
                _markEditorReady();
              }
            },
          ),
        ],
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              // `canPop` is false, so this callback is the only way out:
              // a save that throws must never strand the user on the page.
              try {
                await _saveBeforeExit();
              } catch (e) {
                debugPrint('[NoteEditor] save before exit failed: $e');
              }
              if (context.mounted) {
                AppNavigator.pop(context);
              }
            }
          },
          child: Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: false,
            drawer: const AppDrawer(),
            drawerEnableOpenDragGesture: _editorSettings.value.noteSwipeEnabled,
            appBar: ValueListenableAppBar<bool>(
              valueListenable: _saves.hasChanges,
              builder: (context, hasChanges) => NoteAppBar(
                title: _titleController.text.isEmpty
                    ? AppLocalizations.of(context)!.newNote
                    : _titleController.text,
                hasChanges: hasChanges,
                saveStatusNotifier: _saves.saveStatus,
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
                  if (_canPreview)
                    Tooltip(
                      message: _isPreviewMode
                          ? AppLocalizations.of(context)!.previewMarkdown
                          : AppLocalizations.of(context)!.switchToEditMode,
                      waitDuration: AppConstants.debounceDelay,
                      child: IconButton(
                        icon: Icon(
                          _isPreviewMode ? Icons.visibility : Icons.edit,
                        ),
                        onPressed: () => _togglePreviewMode(),
                      ),
                    ),
                  NoteOverflowMenu(
                    folderName:
                        _folderName ?? AppLocalizations.of(context)!.folders,
                    onOpenFolder: _openFolder,
                    onEditTitle: _editTitle,
                    onMove: _moveNote,
                    onShare: _showExportFormatDialog,
                    onDelete: _deleteNote,
                    onSettings: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ],
              ),
            ),
            // The body appears once, fully formed. While any input of the
            // first frame is still loading the body is blank — no stats
            // bar, no toolbar built from default settings, nothing that
            // would shift or restyle when the real values land — and the
            // finished editor then fades in over the scaffold background
            // instead of popping. The chrome (app bar, title) is stable
            // throughout, so the only motion the reader sees is one fade.
            body: Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: AnimatedSwitcher(
                duration: AppConstants.animationDuration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: _isLoading
                    ? const SizedBox.expand(key: ValueKey('note-body-loading'))
                    : Column(
                        key: const ValueKey('note-body'),
                        children: [
                          // Search bar
                          if (_searchController.isSearching)
                            NoteSearchBar(
                              searchController: _searchController,
                              onClose: () => setState(() {}),
                              onNavigateToMatch: _navigateToSearchMatch,
                              showReplaceField: !showPreview,
                              onReplace: _handleSearchReplace,
                            ),
                          if (_editorSettings.value.showStatsBar)
                            RepaintBoundary(child: _buildNoteStats()),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                              ),
                              child: Builder(
                                builder: (context) {
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

                                  final selection =
                                      _contentController.selection;
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
                                        _getLineStartOffset(
                                          selection.baseIndex,
                                        ) +
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
                                  final noteSize =
                                      _contentController.textLength;

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
                                _buildMarkdownBar(),
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
      ),
    );
  }

  Widget _buildNoteStats() {
    final metadata = widget.metadata;
    return NoteEditorStatsBar(
      stats: _stats.stats,
      fallbackCharCount: metadata?.contentLength ?? 0,
      chunkCount: metadata?.chunkCount ?? 1,
      isCompressed: metadata?.isCompressed ?? false,
    );
  }

  /// Builds the markdown toolbar. Only the loaded note view has one: the
  /// loading state is a blank body by design, so there is no half-built
  /// bar for the real one to differ from.
  Widget _buildMarkdownBar() {
    final showPreview = _showPreview;
    final settings = _editorSettings.value;
    final history = _historyState;
    _builtHistory = history;
    return MarkdownBar(
      shortcuts: _shortcuts,
      isPreviewMode: showPreview,
      canUndo: history.canUndo,
      canRedo: history.canRedo,
      previewFontSize: showPreview ? _previewFontSize : settings.editorFontSize,
      shortcutRatio: settings.toolbarShortcutRatio,
      splitEnabled: settings.toolbarSplitEnabled,
      utilityConfigs: settings.toolbarUtilityConfig,
      onUndo: () => _historyObserver.undo(),
      onRedo: () => _historyObserver.redo(),
      onPaste: () => _contentController.paste(),
      onSwitchBar: _showBarSwitcher,
      onDecreaseFontSize: _decreaseFontSize,
      onIncreaseFontSize: _increaseFontSize,
      onSettings: _openMarkdownSettings,
      onShortcutPressed: _handleShortcut,
      onReorderComplete: _handleReorderComplete,
      onUtilityReorderComplete: _handleUtilityReorderComplete,
      onShare: _showExportFormatDialog,
      onCounter: _showCounterPicker,
      onScrollToTop: () => _scrollToEdge(toTop: true),
      onScrollToBottom: () => _scrollToEdge(toTop: false),
      suggestions: _vocabularySuggestions,
    );
  }

  Widget _buildPreview() {
    if (!_canPreview) {
      return const SizedBox.shrink();
    }

    // For large notes, don't pre-build preview to avoid memory/CPU overhead
    // The preview will build when actually needed (when switching to preview mode)
    final isLargeNote =
        _stats.stats.value.lineCount > AppConstants.previewPreloadLineThreshold;
    if (!_showPreview && isLargeNote) {
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
      onTapWikiLink: _handleWikiLinkTap,
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
    if (!_editorSettings.value.showPreviewScrollbar) {
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

  Widget _buildEditor() {
    final devOptions = DevOptions.instance;
    final showChunkDebug = devOptions.showChunkIndicators;
    final settings = _editorSettings.value;
    final markdownRendering = settings.liveMarkdownRendering;

    return KeyedSubtree(
      key: _editorWrapperKey,
      child: ModernEditorWrapper(
        // Toggling live markdown rendering remounts the editor so all
        // cached line paragraphs are rebuilt with the new span builder.
        // That is also why the whole settings bundle has to have landed
        // before this first mounts (B4) — a key that flips one frame in
        // would remount the CodeEditor mid-initialization.
        //
        // Money config is NOT folded into this key: it resolves
        // asynchronously on note open, and a remount there tears the
        // CodeEditor down during its own mount, crashing re_editor's
        // controller-delegate handoff. It is applied non-destructively
        // via [EditorRenderController.applyMoneyConfig] (cache clear) +
        // a repaint nudge in [_refreshMoneyConfig] instead.
        key: ValueKey(markdownRendering ? 'editor-md' : 'editor'),
        controller: _contentController,
        focusNode: _contentFocusNode,
        scrollController: _editorScrollController,
        searchController: _searchController,
        editorFontSize: settings.editorFontSize,
        onTextChanged: _edits.onTextChanged,
        showLineNumbers: settings.showLineNumbers,
        wordWrap: settings.wordWrap,
        showCursorLine: settings.showCursorLine,
        checkboxTapToggle: markdownRendering,
        // Editor link taps confirm via snackbar before the preview's
        // opener runs (scheme validation + localized errors); fence
        // lines render raw so taps there stay plain editing.
        onOpenLink: markdownRendering ? _handleEditorLinkTap : null,
        onOpenTag: markdownRendering ? _handleTagTap : null,
        onOpenWikiLink: markdownRendering ? _handleWikiLinkTap : null,
        onMoneyTap: markdownRendering && _render.moneyConfig.enabled
            ? _handleMoneyTap
            : null,
        isFenceLine: markdownRendering ? _render.lineInFence : null,
        colorPalette: _render.palette,
        lineNumbersKey: _lineNumbersKey,
        scrollIndicatorKey: _scrollIndicatorKey,
        // Chunk debug visualization (matches preview mode)
        linesPerChunk: _previewLinesPerChunk,
        showChunkColors: showChunkDebug && devOptions.colorMarkdownBlocks,
        showChunkBorders: showChunkDebug && devOptions.showBlockBoundaries,
      ),
    );
  }

  /// Adopts a dragged shortcut order locally before the bloc answers, so
  /// the row does not snap back for the length of the write.
  Future<void> _handleReorderComplete(
    List<CustomMarkdownShortcut> reorderedShortcuts,
  ) async {
    final bar = _bar;
    if (bar != null) {
      setState(() {
        _bar = bar.copyWith(currentShortcuts: reorderedShortcuts);
      });
    }
    context.read<MarkdownBarBloc>().add(
      UpdateShortcuts(
        profileId: _activeBarProfileId,
        shortcuts: reorderedShortcuts,
      ),
    );
  }

  /// Same for the utility half of the toolbar; the settings controller
  /// updates its value before writing, so nothing is re-read here.
  Future<void> _handleUtilityReorderComplete(
    List<UtilityButtonConfig> reorderedUtilities,
  ) => _editorSettings.setToolbarUtilityConfig(reorderedUtilities);

  Future<void> _saveBeforeExit() async {
    _contentFocusNode.unfocus();
    await _saveCurrentPosition();
    await _saves.saveBeforeExit();
  }

  Future<void> _loadFolderName() async {
    try {
      final folder = await GetIt.I<FolderStorageService>().getFolderById(
        _folderId,
      );
      if (!mounted || folder == null) return;
      setState(() => _folderName = folder.name);
    } catch (e) {
      debugPrint('[NoteEditor] folder name lookup failed: $e');
    }
  }

  /// The note as it is stored right now.
  ///
  /// Every menu row that hands the note to another layer — move, share —
  /// needs the persisted row, not the editor's text: the move writes a new
  /// `folderId` onto it, and the export re-reads the content by id. So the
  /// editor flushes first and reads back what landed.
  Future<NoteMetadata?> _currentNoteMetadata() async {
    await _saves.saveBeforeExit();
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    if (noteId == null) return null;
    return GetIt.I<NoteStorageService>().getNoteMetadata(noteId);
  }

  /// Returns to the folder this note lives in, playing one transition even
  /// when the note was reached through a chain of wiki links.
  Future<void> _openFolder() async {
    try {
      await _saveBeforeExit();
    } catch (e) {
      debugPrint('[NoteEditor] save before open folder failed: $e');
    }
    if (!mounted) return;
    await AppNavigator.popToFolder(
      context,
      folderId: _folderId,
      title: _folderName ?? '',
    );
  }

  Future<void> _moveNote() async {
    final metadata = await _currentNoteMetadata();
    if (!mounted) return;
    if (metadata == null) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.noteNotFound,
      );
      return;
    }
    await MoveCoordinator.moveNote(
      context,
      metadata: metadata,
      currentFolderId: _folderId,
    );
    if (!mounted) return;
    final moved = await GetIt.I<NoteStorageService>().getNoteMetadata(
      metadata.id,
    );
    if (!mounted || moved == null || moved.folderId == _folderId) return;
    setState(() {
      _folderId = moved.folderId;
      _folderName = null;
    });
    unawaited(_loadFolderName());
  }

  /// Deletes the note the editor is showing, then leaves.
  ///
  /// The order is the whole point: saving is switched off *before* the
  /// delete is dispatched, because a debounced auto-save landing afterwards
  /// would write into a row that is already a tombstone, and the early
  /// create of a never-persisted note would bring it back outright.
  Future<void> _deleteNote() async {
    final l10n = AppLocalizations.of(context)!;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    final title = _titleController.text.trim();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteNote,
      content: l10n.deleteNoteConfirm(
        title.isEmpty ? l10n.deleteThisNote : title,
      ),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    _saves.disableSaves();
    if (noteId != null) {
      context.read<OptimizedNoteBloc>().add(DeleteOptimizedNote(noteId));
    }
    AppNavigator.pop(context);
  }

  Future<void> _showExportFormatDialog() async {
    final format = await NoteExportDialog.chooseFormat(context);
    if (format == null || !mounted) return;
    final metadata = await _currentNoteMetadata();
    if (!mounted) return;
    if (metadata == null) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.noteNotFound,
      );
      return;
    }
    context.read<ImportExportBloc>().add(
      ExportNoteRequested(metadata: metadata, format: format, share: true),
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
    if (_showPreview) {
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
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
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
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
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
      noteId: _saves.effectiveNoteId,
      onManageCounters: () async {
        await AppNavigator.toCounterManagement(
          context,
          noteId: _saves.effectiveNoteId,
        );
        if (!mounted) return null;
        final bloc = context.read<CounterBloc>();
        bloc.add(RefreshCounters(noteId: _saves.effectiveNoteId));
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
    _edits.runGuarded(() {
      _contentController.runRevocableOp(() {
        _contentController.replaceSelection(currentValue.toString());
      });
    });
    _onTextChanged();
  }

  /// Wraps the current editor selection as ghost text (`{{ … }}`). With
  /// no selection, inserts an empty `{{  }}` and parks the caret between
  /// the markers so the user can type the placeholder.
  void _insertGhostText() {
    final beforeLength = _contentController.textLength;
    _edits.runGuarded(
      () => MarkdownShortcutInserter.insertGhost(_contentController),
    );
    _onTextChanged();
    // Same reflow the generic shortcut path gets: wrapping a wide
    // selection in `{{ … }}` grows the line exactly as Bold does.
    _edits.reformatInserted(beforeLength: beforeLength);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// Wraps the selection in [shortcut]'s before/after text, dropping a
  /// selected ghost placeholder into the slot when there is no selection —
  /// see [MarkdownShortcutInserter.insertWithGhostSlot].
  void _insertWithGhostSlot(CustomMarkdownShortcut shortcut) {
    final beforeLength = _contentController.textLength;
    _edits.runGuarded(
      () => MarkdownShortcutInserter.insertWithGhostSlot(
        _contentController,
        shortcut,
      ),
    );
    _onTextChanged();
    // Same reflow the generic shortcut path gets: `{name: … }` around a
    // wide selection is exactly as likely to overflow as Bold's markers.
    _edits.reformatInserted(beforeLength: beforeLength);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  Future<void> _handleShortcut(CustomMarkdownShortcut shortcut) async {
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

    // Counter mutations and date resolution are awaited *first*, with the
    // document untouched. The write below has to be synchronous: an insert
    // landing in a microtask would arrive after both wrappers around it had
    // returned, so the tracker would diff it as a paste (and a one-newline
    // insert at the end of a list line as an Enter, growing a marker), and
    // the reflow below would measure a length nothing had changed yet.
    final text = await ShortcutApplier.resolve(
      controller: _contentController,
      shortcut: shortcut,
      mutateCounter: _mutateShortcutCounter,
    );
    if (!mounted) return;

    // Store length before applying the shortcut to calculate inserted range
    final beforeLength = _contentController.textLength;

    // The guard keeps the tracker's paste heuristic out of the revocable
    // op — `replaceSelection` notifies synchronously, and a reformat
    // running mid-op would work off stale offsets and then be repeated
    // below. It also resyncs the length, so the next keystroke diffs
    // against what the shortcut actually left behind.
    //
    // The revocable op inside it makes the whole shortcut one undo entry
    // whatever the insert does — the header rewrite is a selectLine plus a
    // replace, and an insert that wrote the value directly would otherwise
    // merge into the typing burst before it.
    _edits.runGuarded(() {
      _contentController.runRevocableOp(() {
        // A null resolution is the header shortcut: it rewrites the caret
        // line rather than inserting at the selection.
        if (text == null) {
          ShortcutApplier.applyHeader(_contentController);
        } else {
          _contentController.replaceSelection(text);
        }
      });
    });

    _onTextChanged();

    // Reflow whatever the shortcut inserted, if it was wide enough to
    // need it and auto-break is on (the tracker checks both).
    _edits.reformatInserted(beforeLength: beforeLength);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _contentController.makeCursorVisible();
      }
    });
  }

  /// Resolves one `{cN}` binding for [ShortcutApplier.resolve]: applies the
  /// bound operation and reports the value the token expands to, or `null`
  /// when the counter is unknown to the loaded state.
  Future<int?> _mutateShortcutCounter(String counterId, CounterOp op) async {
    if (!mounted) return null;
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
  }

  /// Opens the bar switcher bottom sheet and applies the selection.
  Future<void> _showBarSwitcher() async {
    final result = await BarSwitcherSheet.show(
      context,
      currentProfileId: _activeBarProfileId,
      noteId: _saves.effectiveNoteId ?? widget.noteId,
    );
    if (result == null || !mounted) return;

    final noteId = _saves.effectiveNoteId ?? widget.noteId;

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

  /// Opens the markdown settings page and re-resolves the toolbar's bar
  /// profile on the way back.
  ///
  /// Nothing else is re-read here: this is a page route, so [didPopNext]
  /// has already fired [_reloadSettings] by the time the push returns —
  /// re-reading the toolbar rows here would be a second round trip for
  /// values that already landed.
  Future<void> _openMarkdownSettings() async {
    await AppNavigator.toMarkdownSettings(context, allShortcuts: _shortcuts);
    if (!mounted) return;
    context.read<MarkdownBarBloc>().add(
      ResolveBarForNote(noteId: _saves.effectiveNoteId ?? widget.noteId),
    );
  }
}
