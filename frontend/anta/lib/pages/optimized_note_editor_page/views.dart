part of '../optimized_note_editor_page.dart';

/// The pieces `build` assembles: the shared line, the stats, the markdown
/// bar, the preview and the editor.
mixin _NoteEditorViews on _NoteEditorToolbar {
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

  /// "From {name} · Read only", pinned between the bar and the body.
  Widget _buildSharedLine() {
    final l10n = AppLocalizations.of(context)!;
    return SharedReadOnlyLine(
      partner: _partner,
      text: l10n.sharedNoteLine(_partnerNameIn(l10n)),
      identifier: SemanticsIds.sharedNoteLine,
    );
  }

  Widget _buildNoteStats() {
    final metadata = widget.metadata;
    return NoteEditorStatsBar(
      stats: _stats.stats,
      // The content load reports exact counts, so the stored length only
      // stands in before it.
      fallbackCharCount: _contentLoaded ? null : metadata?.contentLength,
      chunkCount: DevOptions.instance.showChunkIndicators
          ? metadata?.chunkCount ?? 1
          : null,
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
    return Semantics(
      identifier: SemanticsIds.editorToolbar,
      explicitChildNodes: true,
      child: MarkdownBar(
        shortcuts: _shortcuts,
        isPreviewMode: showPreview,
        canUndo: history.canUndo,
        canRedo: history.canRedo,
        previewFontSize: showPreview
            ? _previewFontSize
            : settings.editorFontSize,
        shortcutRatio: settings.toolbarShortcutRatio,
        splitEnabled: settings.toolbarSplitEnabled,
        pinUndoRedo: settings.toolbarUndoRedoPinned,
        utilityConfigs: settings.toolbarUtilityConfig,
        onUndo: () => _historyObserver.undo(),
        onRedo: () => _historyObserver.redo(),
        onPaste: _pasteFromBar,
        onIndent: () => _shiftListIndent(outdent: false),
        onOutdent: () => _shiftListIndent(outdent: true),
        currentHeadingLevel: _caretHeadingLevel,
        hapticsEnabled: settings.hapticFeedback,
        // The switcher is offered once there is something to switch to; a
        // fresh install has one bar, and a button that opens a one-row sheet
        // is a dead end on the strip.
        onSwitchBar: (_bar?.profiles.length ?? 0) > 1 ? _showBarSwitcher : null,
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
        suggestionPalette: settings.liveMarkdownRendering
            ? _render.palette
            : null,
      ),
    );
  }

  Widget _buildPreview() {
    if (!_canPreview) {
      return const SizedBox.shrink();
    }

    // For large notes, don't pre-build preview to avoid memory/CPU overhead
    // The preview will build when actually needed (when switching to preview mode)
    if (!_showPreview && _isLargeNote) {
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

    return Semantics(
      identifier: SemanticsIds.editorBody,
      // The editor publishes a node per visible line plus its own text field;
      // an annotation that merged them would flatten the whole surface into
      // one label. This one is a container above them and changes nothing
      // underneath it.
      explicitChildNodes: true,
      child: KeyedSubtree(
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
          readOnly: _readOnly,
          onReadOnlyTaskTap: _readOnly ? _sayReadOnlyOnce : null,
          // Editor link taps confirm via snackbar before the preview's
          // opener runs (scheme validation + localized errors); fence
          // lines render raw so taps there stay plain editing.
          onOpenLink: markdownRendering ? _handleEditorLinkTap : null,
          onOpenTag: markdownRendering ? _handleTagTap : null,
          onOpenWikiLink: markdownRendering ? _handleWikiLinkTap : null,
          onMoneyTap: markdownRendering && _render.moneyConfig.enabled
              ? _handleMoneyTap
              : null,
          // Unconditional, like the tracker's and the paste controller's:
          // fencing is a property of the document, not of the rendering.
          isFenceLine: _render.lineInFence,
          hapticsEnabled: settings.hapticFeedback,
          // The span builder reads the same listenable, so a find match's
          // line reveals for render and taps alike.
          revealWhenUnfocused: _findActive,
          onFormatShortcut: _toggleFormatShortcut,
          hint: _readOnly ? null : AppLocalizations.of(context)!.editorHint,
          followsTextScale: true,
          colorPalette: _render.palette,
          lineNumbersKey: _lineNumbersKey,
          scrollIndicatorKey: _scrollIndicatorKey,
          // Chunk debug visualization (matches preview mode)
          linesPerChunk: _previewLinesPerChunk,
          showChunkColors: showChunkDebug && devOptions.colorMarkdownBlocks,
          showChunkBorders: showChunkDebug && devOptions.showBlockBoundaries,
        ),
      ),
    );
  }
}
