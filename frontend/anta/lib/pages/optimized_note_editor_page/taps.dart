part of '../optimized_note_editor_page.dart';

/// What a tap in the text does — a link, a task box, a ghost placeholder,
/// a #tag, a wiki link, a money line, a double tap in the preview — and
/// the in-note search.
mixin _NoteEditorTaps on _NoteEditorNoteActions {
  void _toggleSearch() {
    if (_searchController.isSearching) {
      // The open row owns its one exit, its trailing X; the toggle only
      // brings the field back, so a second tap never throws the query away
      // (U2.7).
      _searchBarKey.currentState?.focusField();
      return;
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
      // Long enough to read the target before deciding.
      duration: CustomSnackbar.confirmActionDuration,
      // Above the toolbar, or the prompt sits on the bar the user's thumb
      // is already on.
      withToolbarOffset: true,
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
    if (_readOnly) {
      _sayReadOnlyOnce();
      return;
    }
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
  ///
  /// Obsidian's suffixes are read through [MarkdownWikiTarget]: when the
  /// title as typed names no note, `Note#heading`, `Note^block` and
  /// `Note.md` resolve `Note`, and a heading part lands on that heading —
  /// in place for this note (`[[#heading]]` names it outright), through
  /// [OptimizedNoteEditorPage.targetHeading] for another.
  Future<void> _handleWikiLinkTap(String rawTitle) async {
    final target = MarkdownWikiTarget.parse(rawTitle);
    final title = target.title;
    if (title.isEmpty) return;

    try {
      final storage = GetIt.I<NoteStorageService>();
      // The lookup gets the full trimmed title; only what the snackbar
      // shows is bounded (C10). It runs first, so a note whose own name
      // holds a `#` keeps resolving as it always has.
      final (note, byNote) = await target.resolve(
        // On this note's own side: a partner's note links to her notes, a
        // note of mine to mine (§6.13).
        (lookup) => storage.resolveNoteByTitle(
          lookup,
          preferFolderId: _folderId,
          fromPartner: _readOnly,
        ),
      );
      final heading = byNote ? target.wholeHeading : null;
      if (!mounted) return;
      if (!_isCurrentRoute) return;
      if (note == null && target.hasSuffix && target.note.isEmpty) {
        _centreHeading(target.wholeHeading);
        return;
      }
      if (note == null) {
        CustomSnackbar.show(
          context,
          AppLocalizations.of(
            context,
          )!.wikiLinkNoteNotFound(WikiLinkTitle.forDisplay(title)),
        );
        return;
      }
      if (note.id == (_saves.effectiveNoteId ?? widget.noteId)) {
        _centreHeading(heading);
        return;
      }

      await _saveCurrentPosition();
      if (!mounted) return;
      if (!_isCurrentRoute) return;
      AppNavigator.toNoteEditor(
        context,
        folderId: note.folderId,
        noteId: note.id,
        metadata: note,
        targetHeading: heading,
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

  /// Centres the first heading of this note whose text is [heading],
  /// leaving the caret where it is — the reader followed a link, they did
  /// not ask to edit there. Null, a heading the note does not hold, or
  /// the preview on screen leave everything as it was.
  void _centreHeading(String? heading) {
    if (heading == null || _showPreview) return;
    final line = _headingLine(heading);
    if (line < 0) return;
    _editorScrollController.makeCenterIfInvisible(
      CodeLinePosition(index: line, offset: 0),
    );
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

  /// Character offset of a line's first character, for the debug
  /// overlay's cursor/selection read-out.
  int _getLineStartOffset(int lineIndex) =>
      CodeLineOffsetUtils.lineStartOffset(_contentController, lineIndex);
}
