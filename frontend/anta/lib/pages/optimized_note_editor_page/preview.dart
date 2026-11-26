part of '../optimized_note_editor_page.dart';

/// The preview surface and the place in the note: feeding the preview its
/// text and its search matches, switching between it and the editor, the
/// text size, and saving and restoring where the reader is.
mixin _NoteEditorPreview on _NoteEditorState {
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
    // A line reveals for find only while a match sits on it: a query with
    // no match must not leave the last hop's line raw (U2.7).
    _findActive.value =
        _searchController.isSearching && _searchController.currentMatch != null;
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
  ///
  /// A new editor size reflows every line, so the caret the user was typing
  /// at can end up off screen; it is centred again once the reflowed frame
  /// has laid out — only for a focused editor, whose caret is the one the
  /// user is looking at.
  void _adjustFontSize(int direction) {
    if (_showPreview) {
      _editorSettings.adjustPreviewFontSize(direction);
      return;
    }
    final before = _editorSettings.value.editorFontSize;
    _editorSettings.adjustEditorFontSize(direction);
    if (!_contentFocusNode.hasFocus ||
        _editorSettings.value.editorFontSize == before) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorCenterIfInvisible();
    });
  }

  /// A note large by lines or by size takes the preview's lazy path: no
  /// offstage preview, no re-prepare per pause. Read off the editor, never
  /// the stats bar's counts, which stand still while the bar is hidden.
  bool get _isLargeNote =>
      _contentController.lineCount > AppConstants.previewPreloadLineThreshold ||
      _contentController.textLength >
          AppConstants.previewPreloadCodeUnitThreshold;

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
    if (_isLargeNote) return;
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
    final isLargeNote = _isLargeNote;

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
}
