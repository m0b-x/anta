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
import '../models/item_label.dart';
import '../models/note_change.dart';
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
import '../services/folder_storage_service.dart';
import '../services/move_coordinator.dart';
import '../services/duplicate_name_exception.dart';
import '../services/note_storage_service.dart';
import '../services/sync/conflict_copy_title.dart';
import '../services/sync/open_note_registry.dart';
import '../widgets/label_swatch_strip.dart';
import '../widgets/note_overflow_menu.dart';
import '../widgets/unified_app_bars.dart';
import '../utils/editor_width_calculator.dart';
import '../utils/custom_snackbar.dart';
import '../utils/re_editor_search_controller.dart';
import '../utils/text_fit.dart';
import '../utils/text_history_observer.dart';
import '../utils/text_position_utils.dart';
import '../utils/wiki_link_title.dart';
import '../utils/markdown_line_shape.dart';
import '../utils/markdown_link_patterns.dart';
import '../utils/markdown_money_syntax.dart';
import '../utils/markdown_plain_text.dart';
import '../utils/money_display_config.dart';
import '../widgets/money_detail_sheet.dart';
import '../utils/list_aware_paste.dart';
import '../utils/paste_line_breaker.dart';
import '../controllers/editor_edit_tracker.dart';
import '../controllers/editor_render_controller.dart';
import '../controllers/editor_settings_controller.dart';
import '../controllers/list_indent_action.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/note_editor_position_controller.dart';
import '../controllers/note_editor_stats_tracker.dart';
import '../controllers/note_save_coordinator.dart';
import '../controllers/preview_scroll_controller.dart';
import '../controllers/shared_note_copy.dart';
import '../controllers/shortcut_applier.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../models/app_user.dart';
import '../services/pairing_service.dart';
import '../services/share_service.dart';
import '../utils/share_copy.dart';
import '../utils/share_leave_voice.dart';
import '../widgets/content_rows.dart';
import '../widgets/overlay_snackbar.dart';
import '../services/vocabulary_service.dart';
import '../services/tag_catalog_service.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/font_constants.dart';
import '../constants/semantics_ids.dart';

part 'optimized_note_editor_page/state.dart';
part 'optimized_note_editor_page/preview.dart';
part 'optimized_note_editor_page/typing.dart';
part 'optimized_note_editor_page/inputs.dart';
part 'optimized_note_editor_page/mount.dart';
part 'optimized_note_editor_page/loading.dart';
part 'optimized_note_editor_page/sharing.dart';
part 'optimized_note_editor_page/remote.dart';
part 'optimized_note_editor_page/note_actions.dart';
part 'optimized_note_editor_page/taps.dart';
part 'optimized_note_editor_page/toolbar.dart';
part 'optimized_note_editor_page/views.dart';

class OptimizedNoteEditorPage extends StatefulWidget {
  final String folderId;
  final String? noteId;
  final NoteMetadata? metadata;

  /// The heading a `[[Note#heading]]` tap asked for — the link's whole
  /// fragment, read as [MarkdownWikiTarget.headingReadingsOf] reads it:
  /// once the note has loaded and its stored position has been restored,
  /// the caret moves to the first heading of that text and the editor
  /// opens centred on it. Null opens the note where the reader left it.
  final String? targetHeading;

  const OptimizedNoteEditorPage({
    super.key,
    required this.folderId,
    this.noteId,
    this.metadata,
    this.targetHeading,
  });

  /// Where a page over a shared note reads the partner's name and face and
  /// the `shareMarkMine` setting; a suite swaps in its fake.
  @visibleForTesting
  static Future<ShareService> Function() shareService =
      ShareService.getInstance;

  /// What the share service built for the open database last evaluated,
  /// read from memory with no await: the partner a page names from its
  /// first frame. A suite hands in its own.
  @visibleForTesting
  static ShareAvailability? Function() knownShare = () =>
      ShareService.knownAvailability;

  /// The auto-save a page's save coordinator is built over; null builds the
  /// app's. A suite records what the coordinator asks of it.
  @visibleForTesting
  static AutoSaveFactory? autoSaveFactory;

  @override
  State<OptimizedNoteEditorPage> createState() =>
      _OptimizedNoteEditorPageState();
}

class _OptimizedNoteEditorPageState extends _NoteEditorState
    with
        _NoteEditorPreview,
        _NoteEditorTyping,
        _NoteEditorInputs,
        _NoteEditorMount,
        _NoteEditorLoading,
        _NoteEditorSharing,
        _NoteEditorRemote,
        _NoteEditorNoteActions,
        _NoteEditorTaps,
        _NoteEditorToolbar,
        _NoteEditorViews {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OpenNoteRegistry.register(_claimsConflictFiling);
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
    // Every write the page makes from code runs under the tracker's guard.
    // Read through a local, so a notification before the tracker is built
    // answers "not from code" instead of throwing on the late field.
    EditorEditTracker? edits;
    _vocabularySuggestions = VocabularySuggestionController(
      controller: _contentController,
      onInsert: _applyVocabularyInsertion,
      isProgrammaticEdit: () => edits?.isProcessing ?? false,
    );
    _historyObserver = TextHistoryObserver(_contentController);
    _contentFocusNode = FocusNode()..addListener(_onContentFocusChanged);
    // Rendering and the wrapper's taps must agree on whether the caret
    // line is revealed, and the wrapper already reads real focus.
    _render.bindFocus(_contentFocusNode);
    _render.bindRevealWhenUnfocused(_findActive);
    _editorScrollController = CodeScrollController();
    _searchController = ReEditorSearchController();
    _searchController.initialize(_contentController);
    _previewBloc = MarkdownPreviewBloc();
    _previewBloc.bindContentProvider(() => _contentController.text);
    _previewController.progress.addListener(_onPreviewProgressChanged);

    _stats = NoteEditorStatsTracker(
      // Per line, cached on the lines: a pause re-counts only what changed.
      snapshot: () => (
        lineCount: _contentController.lineCount,
        charCount: _contentController.codeLines.graphemeCount,
      ),
      isShown: () => _editorSettings.value.showStatsBar,
    );
    _edits = edits = EditorEditTracker(
      controller: _contentController,
      autoBreakLongLines: () => _editorSettings.value.autoBreakLongLines,
      pasteContext: _pasteReformatContext,
      onLinesReformatted: _showLinesFormatted,
      // Unconditional: whether a line is fenced is a property of the
      // document, not of the live-rendering setting.
      isFenceLine: _render.lineInFence,
      lineInFenceBody: _render.lineInFenceBody,
      blockStateAt: _render.blockStateAt,
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
      beforeWrite: _writesMayProceed,
      // The metadata the page was opened with, while its share sign is still
      // the page's: a move across a shared folder lets the save read once.
      current: () => widget.metadata?.inSharedFolder == _inSharedFolder
          ? widget.metadata
          : null,
      autoSaveFactory: OptimizedNoteEditorPage.autoSaveFactory,
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
    // Seeded so the first selection-only notification of a page with no
    // load (a new note) is not taken for an edit.
    _notifiedLines = _contentController.codeLines;
    _notifiedLength = _contentController.textLength;
    _contentController.addListener(_onContentNotified);
    _searchController.addListener(_onSearchChanged);
    _storageChanges = GetIt.I<NoteStorageService>().changes.listen(
      _onStorageChange,
    );
    _shareFactsChanges = GetIt.I<NoteStorageService>().shareFactsChanged.listen(
      (_) => unawaited(_refreshSharedSign()),
    );

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
    ShareLeaveVoice.open(this, _leavesWithThisRun);
    if (_readOnly) {
      _saves.disableSaves();
    } else {
      _saves.start();
    }
    if (_readOnly || _inSharedFolder) unawaited(_loadShareFacts());
    unawaited(_position.load().whenComplete(_onPositionLoaded));
    unawaited(_loadFolderName());
    // Last, so the settings listener can never fire against a
    // half-constructed page.
    _editorSettings.addListener(_onEditorSettingsChanged);
    unawaited(_reloadSettings());
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
    // The route's scope notifies when a route above it comes or goes — a
    // dialog included, which [didPopNext] never hears of.
    _leaveIfDeletedWhileCovered();
    _showFilingNoticeOwed();

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
      // Every growth step of the rising keyboard, after the body has shrunk
      // by it. Only for the editor's own keyboard: a stale inset after a
      // resume or the search field's keyboard must not scroll the note.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showPreview && _contentFocusNode.hasFocus) {
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

  /// Called when a route pushed above the editor is popped — the drawer's
  /// settings, backup and database pages among them, and since wiki links
  /// another editor. Editor flags live on the main settings page, so
  /// without this every one of them would stay stale until the note was
  /// closed and reopened; and the note itself may have been edited above
  /// this page, which is what the second call covers.
  ///
  /// The toolbar's bar is re-resolved for this note here rather than after
  /// awaiting the Markdown settings push: a restored Markdown settings page
  /// pops with no one awaiting it, and a linked editor above resolves the
  /// shared bloc for its own note.
  ///
  /// `RouteObserver<PageRoute>` only fires between page routes, so the
  /// toolbar, colour and money sheets do not reach here.
  @override
  void didPopNext() {
    unawaited(_reloadSettings());
    context.read<MarkdownBarBloc>().add(
      ResolveBarForNote(noteId: _saves.effectiveNoteId ?? widget.noteId),
    );
    unawaited(_reloadContentIfChanged());
    // The page above may have been the Sharing page.
    unawaited(_refreshSharedSign(returning: true));
    _leaveIfDeletedWhileCovered();
    _showFilingNoticeOwed();
  }

  /// Called when a route is pushed above the editor. The drawer's settings
  /// route leads to the database switcher, which restarts the app through
  /// `SystemNavigator.pop()` — the editor is never disposed and the
  /// debounce never fires, so the flush has to happen on the way out.
  @override
  void didPushNext() {
    unawaited(_saves.forceSave());
  }

  /// Gone from in front the moment it is popped, not when its closing ends:
  /// a leave heard meanwhile on a page of hers under it is said there.
  @override
  void didPop() => ShareLeaveVoice.popped(this);

  @override
  void dispose() {
    ShareLeaveVoice.exit(this);
    _storageChanges.cancel();
    _shareFactsChanges.cancel();
    AppNavigator.routeObserver.unsubscribe(this);
    _counterBloc.add(const SetNoteContext());
    ShortcutHandlerFactory.counterHandler.setActiveNoteId(null);
    WidgetsBinding.instance.removeObserver(this);
    OpenNoteRegistry.unregister(_claimsConflictFiling);
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
    _contentController.removeListener(_onContentNotified);
    _contentController.dispose();
    _contentFocusNode.removeListener(_onContentFocusChanged);
    _render.bindFocus(null);
    _contentFocusNode.dispose();
    _editorScrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _render.bindRevealWhenUnfocused(null);
    _findActive.dispose();
    _editorSettings.removeListener(_onEditorSettingsChanged);
    // Disposing flushes any font size the user tapped moments ago.
    _editorSettings.dispose();
    _stats.dispose();
    super.dispose();
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
                // In the turn the id is adopted: a press from here on counts
                // on the note itself, behind the presses made without it,
                // which are counted there now.
                _counterBloc.fileShortcutPresses(id, _unfiledCounterPresses);
                _saves.noteCreated(id);
                // From here on the note has an id, so its reading
                // position can start being persisted.
                _position.noteId = id;
                _counterBloc.add(SetNoteContext(noteId: id));
                ShortcutHandlerFactory.counterHandler.setActiveNoteId(id);
                // The app bar reads the id to decide whether it can offer a
                // Label row; nothing else here rebuilds, so without this the
                // row would stay missing until some unrelated setState.
                setState(() {});
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
                _adoptShareFlags(state.note.metadata);
                unawaited(_adoptFirstLoad(state.note.content ?? ''));
              } else if (state is OptimizedNoteError &&
                  state.errorType == NoteErrorType.notFound) {
                // The note was gone before it could load — un-shared under
                // the door that opened it, deleted elsewhere. It used to
                // leave the page blank for good; it leaves the page now.
                if (state.noteId != widget.noteId) return;
                if (!_awaitingContentLoad) return;
                _awaitingContentLoad = false;
                _goneAtLoad = true;
                _leaveRemotelyDeleted(
                  NoteChange(
                    type: NoteChangeType.deleted,
                    noteId: state.noteId!,
                  ),
                );
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
            if (didPop) return;
            final route = ModalRoute.of(context);
            if (route != null && route.willHandlePopInternally) {
              AppNavigator.pop(context);
              return;
            }
            if (_isExiting) {
              return;
            }
            _isExiting = true;
            // `canPop` is false, so this callback is the only way out:
            // a save that throws must never strand the user on the page.
            try {
              await _saveBeforeExit();
            } catch (e) {
              debugPrint('[NoteEditor] save before exit failed: $e');
            }
            if (!context.mounted) return;
            if (!await _keptDeletedNotesText()) {
              _isExiting = false;
              _saves.exitAborted();
              return;
            }
            if (!context.mounted) return;
            AppNavigator.pop(context);
            if (context.mounted &&
                (ModalRoute.of(context)?.isCurrent ?? false)) {
              _isExiting = false;
              _saves.exitAborted();
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
                // A page opened to create a note is "New Note" for its
                // whole session, even once autosave has given the note an
                // id; a saved note reopened without a title carries the
                // name the folder lists it under, so one note never has
                // two names.
                title: _titleController.text.isNotEmpty
                    ? _titleController.text
                    : widget.noteId == null
                    ? AppLocalizations.of(context)!.newNote
                    : AppLocalizations.of(context)!.untitledNote,
                // A read-only page has nothing to save and no title to edit,
                // so it says neither.
                hasChanges: !_readOnly && hasChanges,
                saveStatusNotifier: _readOnly ? null : _saves.saveStatus,
                onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                onTitleTap: _readOnly ? null : _editTitle,
                shared: _showsSharedSign,
                sharedLabel: _showsSharedSign
                    ? AppLocalizations.of(context)!.shareMarkMineLabel(
                        _partnerNameIn(AppLocalizations.of(context)!),
                      )
                    : null,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search),
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
                    onLabel: (_saves.effectiveNoteId ?? widget.noteId) == null
                        ? null
                        : _labelNote,
                    onShare: _showExportFormatDialog,
                    onDelete: _deleteNote,
                    onSettings: () => _scaffoldKey.currentState?.openDrawer(),
                    fromPartner: _readOnly,
                    onCopyToMine: _readOnly ? _copyToMine : null,
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
                          if (_readOnly) _buildSharedLine(),
                          // Search bar
                          if (_searchController.isSearching)
                            NoteSearchBar(
                              key: _searchBarKey,
                              searchController: _searchController,
                              onClose: () => setState(() {}),
                              onNavigateToMatch: _navigateToSearchMatch,
                              showReplaceField: !showPreview && !_readOnly,
                              onReplace: _handleSearchReplace,
                            ),
                          if (_editorSettings.value.showStatsBar)
                            RepaintBoundary(child: _buildNoteStats()),
                          Expanded(
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
                          // Always show toolbar — in preview mode it provides
                          // utility actions; in edit mode it appears with keyboard.
                          // A read-only note has nothing for it to do, and
                          // its body takes the room.
                          if (_readOnly)
                            SizedBox(height: bottomSpacing)
                          else
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
}

/// One thing a remote change left the editor to file (record §3.9): a
/// conflict copy, or — [keepsText] — the text of a note deleted elsewhere,
/// kept as a new note. Retried until [run] completes.
class _Filing {
  _Filing(this.run, {required this.keepsText});

  final Future<void> Function() run;
  final bool keepsText;

  /// The attempt running now, if any.
  Future<void>? attempt;

  /// Set at the first failure, so the notice is shown once.
  bool failed = false;

  /// That failure happened while another route covered the page.
  bool noticeOwed = false;
}
